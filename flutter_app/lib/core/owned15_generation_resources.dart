import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as paths;
import 'image_dimensions.dart';
import 'complex_editor_document.dart';
import 'local_data_paths.dart';
import 'local_generation_content_repository.dart';
import 'local_legacy_upload_alias_index.dart';

final class Owned15Raster {
  const Owned15Raster(this.bytes, this.mime, this.sha256Hex);
  final Uint8List bytes;
  final String mime, sha256Hex;
}

/// Borrows a sealed owner's content/index; never opens a database or network.
/// Factory must capture references from the exact persisted document, and retire
/// this scope before adopting any changed/imported draft. No authorization cache.
final class Owned15GenerationResources {
  Owned15GenerationResources({
    required this.index,
    required this.content,
    required this.generation,
    required this.sourceDigest,
    required this.fullFingerprint,
    required this.scopeIdentity,
    required Set<String> references,
    required bool Function() isCurrent,
    this._confirmCurrent,
  }) : _current = isCurrent,
       _references = Set.unmodifiable(references) {
    if (references.length > 32 ||
        content.metadata.generationId != generation.generationId ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fullFingerprint) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scopeIdentity)) {
      throw ArgumentError('Verified generation resource scope required');
    }
    ComplexEditorDocument.validateText(content.source);
    if (sha256.convert(utf8.encode(content.source)).toString() !=
        sourceDigest) {
      throw ArgumentError('Persisted source digest mismatch');
    }
    // Reject unsupported references at construction; do not derive new URLs.
    for (final raw in references) {
      final canonical = index.policy.canonicalPath(raw);
      if (canonical == null || canonical != raw) {
        throw ArgumentError('Canonical local upload references required');
      }
    }
  }
  final LegacyUploadAliasIndex index;
  final GenerationContentHandle content;
  final LocalDataPaths generation;
  final String sourceDigest, fullFingerprint, scopeIdentity;
  final Set<String> _references;
  final bool Function() _current;
  final Future<void> Function()? _confirmCurrent;
  final Set<_AssetJob> _jobs = {};
  final List<Uint8List> _issued = [];
  bool _retired = false, _joinFailed = false;
  int _requests = 0, _acceptedBytes = 0;
  bool get drained =>
      _retired && _jobs.isEmpty && _issued.isEmpty && !_joinFailed;
  bool get current {
    try {
      return !_retired && _current() && content.isCurrent;
    } catch (_) {
      return false;
    }
  }

  bool owns(Uri uri) =>
      current &&
      !uri.hasScheme &&
      !uri.hasAuthority &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      _references.contains(index.policy.canonicalPath(uri.toString()));

  Future<Owned15Raster?> read(Uri uri) async {
    if (!current ||
        _jobs.length >= 4 ||
        _requests >= 32 ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final path = index.policy.canonicalPath(uri.toString());
    if (path == null || !_references.contains(path)) return null;
    _requests++;
    final job = _AssetJob();
    _jobs.add(job);
    final timer = Timer(const Duration(seconds: 10), job.cancel);
    Uint8List? bytes;
    final chunks = BytesBuilder(copy: false);
    try {
      void check() {
        if (!current || job.cancelled) throw const _AssetCancelled();
      }

      Future<T> step<T>(Future<T> pending) async {
        try {
          final result = await Future.any<T>([
            pending,
            job.stopped.future.then<T>((_) => throw const _AssetCancelled()),
          ]);
          check();
          return result;
        } catch (_) {
          // Cancellation revokes delivery immediately, but never confuses the
          // response race with actual filesystem/SQL completion. Root drain
          // must join this real pending operation before retiring its database.
          try {
            await pending;
          } catch (_) {}
          rethrow;
        }
      }

      check();
      final confirm = _confirmCurrent;
      if (confirm != null) await step(confirm());
      final reference = await step(
        index.lookup(path, maxBytes: 5 * 1024 * 1024),
      );
      if (reference == null || !reference.isCurrent) return null;
      final support = await step(
        generation.privateSupport.resolveSymbolicLinks(),
      );
      final expected = paths.join(
        support,
        'local-data-v1',
        'generations',
        generation.generationId!,
      );
      // Each intervening component must be a real directory, not a symlink.
      var cursor = support;
      for (final part in [
        'local-data-v1',
        'generations',
        generation.generationId!,
        'attachments',
      ]) {
        cursor = paths.join(cursor, part);
        if (await step(FileSystemEntity.type(cursor, followLinks: false)) !=
            FileSystemEntityType.directory) {
          return null;
        }
      }
      if (await step(generation.attachments.resolveSymbolicLinks()) !=
          paths.join(expected, 'attachments')) {
        return null;
      }
      final file = File(paths.join(cursor, reference.attachmentId));
      if (await step(FileSystemEntity.type(file.path, followLinks: false)) !=
              FileSystemEntityType.file ||
          await step(file.length()) != reference.bytes) {
        return null;
      }
      final iterator = StreamIterator<List<int>>(file.openRead());
      job.iterator = iterator;
      var count = 0;
      while (await step(iterator.moveNext())) {
        check();
        if (!reference.isCurrent) return null;
        final chunk = iterator.current;
        count += chunk.length;
        if (count > reference.bytes ||
            count > 5 * 1024 * 1024 ||
            _acceptedBytes + count > 20 * 1024 * 1024) {
          return null;
        }
        chunks.add(chunk);
      }
      check();
      if (count != reference.bytes ||
          await step(FileSystemEntity.type(file.path, followLinks: false)) !=
              FileSystemEntityType.file ||
          await step(file.length()) != count) {
        return null;
      }
      bytes = chunks.takeBytes();
      if (sha256.convert(bytes).toString() != reference.sha256Hex) return null;
      final mime = lookupMimeType('', headerBytes: bytes);
      if (!{
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      }.contains(mime)) {
        return null;
      }
      final (width, height) = encodedImageDimensions(bytes);
      if (width > 8192 || height > 8192 || width * height > 16 * 1024 * 1024) {
        return null;
      }
      check();
      if (!reference.isCurrent) return null;
      if (confirm != null) await step(confirm());
      check();
      _acceptedBytes += bytes.length;
      _issued.add(bytes);
      final accepted = Owned15Raster(
        bytes.asUnmodifiableView(),
        mime!,
        reference.sha256Hex,
      );
      bytes = null;
      return accepted;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
      try {
        await job.cancelStream();
      } catch (_) {
        _joinFailed = true;
        rethrow;
      } finally {
        final rejected = bytes;
        rejected?.fillRange(0, rejected.length, 0);
        final discarded = chunks.takeBytes();
        discarded.fillRange(0, discarded.length, 0);
        _jobs.remove(job);
        job.done.complete();
      }
    }
  }

  /// Rejects synchronously; completion joins actual file streams and SQL lookups.
  Future<void> retire() async {
    _retired = true;
    index.dispose();
    final pending = _jobs.toList(growable: false);
    for (final job in pending) {
      job.cancel();
    }
    await Future.wait(pending.map((job) => job.done.future));
    for (final bytes in _issued) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _issued.clear();
    if (_joinFailed) throw StateError('Generation resource drain unavailable');
  }
}

final class _AssetCancelled implements Exception {
  const _AssetCancelled();
}

final class _AssetJob {
  final stopped = Completer<void>();
  final done = Completer<void>();
  StreamIterator<List<int>>? iterator;
  Future<void>? _cancelStream;
  Future<void> cancelStream() =>
      _cancelStream ??= iterator?.cancel() ?? Future<void>.value();
  bool get cancelled => stopped.isCompleted;
  void cancel() {
    if (!stopped.isCompleted) stopped.complete();
    if (iterator != null) {
      // Consume the cancellation future here; read.finally also joins it.
      unawaited(cancelStream().catchError((Object _) {}));
    }
  }
}
