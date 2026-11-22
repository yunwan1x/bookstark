import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'local_backup_codec.dart';
import 'local_backup_content.dart';
import 'local_backup_schema.dart';
import 'local_data_paths.dart';
import 'local_generation_state.dart';
import 'native_local_data_control.dart';

class LocalBackupSpaceUnavailable implements Exception {
  const LocalBackupSpaceUnavailable();
  @override
  String toString() =>
      'Insufficient free space; current local data is retained';
}

class LocalBackupCandidate {
  LocalBackupCandidate._(
    this._discard, {
    required this.id,
    required this.layout,
    required this.manifest,
    required this.manifestSHA256,
    required this.sourceSHA256,
    required this.sourceBytes,
    required this.contentReport,
  });
  final String id, manifestSHA256, sourceSHA256;
  final int sourceBytes;
  final LocalDataPaths layout;
  final LocalBackupManifest manifest;
  final LocalBackupContentReport contentReport;
  final Future<void> Function(String) _discard;
  bool _activationStarted = false, _discarded = false;

  /// Conservative retention only, not Native submission/success proof.
  bool get preservedForActivation => _activationStarted;

  /// Call BEFORE submitting native prepare. Uncertain results retain this copy.
  void preserveForActivation() {
    if (_discarded) throw StateError('Candidate has been discarded');
    _activationStarted = true;
  }

  Future<void> discardUnprepared() async {
    if (_discarded) return;
    if (_activationStarted) {
      throw StateError('Submitted candidates require explicit result review');
    }
    await _discard(id); // Native rechecks active/pending references atomically.
    _discarded = true;
  }
}

/// Inputs are fixed private SAF-inbox or retained paths, never caller file URLs.
/// It never opens the active DB, publishes a pointer or writes to source files.
class LocalBackupCandidateImporter {
  LocalBackupCandidateImporter({
    required this.privateSupport,
    required this.privateCache,
    required this.factory,
    Future<int> Function()? availableBytes,
    Future<void> Function(String)? discardCandidate,
    String Function()? identity,
  }) : _space = availableBytes ?? NativeLocalDataControl().availableBytes,
       _discard =
           discardCandidate ??
           ((id) async {
             await NativeLocalDataControl().discardCandidate(id);
           }),
       _identity = identity ?? attachmentId {
    if (!paths.isAbsolute(privateSupport.path) ||
        !paths.isAbsolute(privateCache.path)) {
      throw const FormatException('Trusted private roots must be absolute');
    }
  }
  static const reserveBytes = 128 * 1024 * 1024;
  final Directory privateSupport, privateCache;
  final DatabaseFactory factory;
  final Future<int> Function() _space;
  final Future<void> Function(String) _discard;
  final String Function() _identity;

  Future<LocalBackupCandidate> inspectPicked(
    String inboxId, {
    AttachmentCancellation? cancellation,
  }) async {
    _id(inboxId);
    await _base(privateCache);
    final inbox = await _folder(privateCache, 'local-backup-inbox-v1');
    return _inspect(
      File(paths.join(inbox.path, '$inboxId.bsbackup')),
      cancellation: cancellation,
    );
  }

  Future<LocalBackupCandidate> inspectRetained(
    LocalRetention reviewed, {
    AttachmentCancellation? cancellation,
  }) async {
    await _base(privateSupport);
    final control = await _folder(privateSupport, 'local-data-v1');
    final retained = await _folder(control, 'retained');
    final directory = await _folder(retained, reviewed.id);
    final ready = File(paths.join(directory.path, '_ready.json'));
    if (await FileSystemEntity.type(ready.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await ready.length() > 4096 ||
        await _small(ready, 4096) != reviewed.encode()) {
      throw const FormatException('Retained backup identity changed');
    }
    return _inspect(
      File(paths.join(directory.path, 'content.bsbackup')),
      expectedManifest: reviewed.manifestSHA256,
      cancellation: cancellation,
    );
  }

  Future<String> _small(File file, int limit) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, limit + 1)) {
      bytes.add(chunk);
      if (bytes.length > limit) {
        throw const FormatException('Oversized private backup marker');
      }
    }
    return utf8.decode(bytes.takeBytes());
  }

  void _id(String value) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
      throw const FormatException('Invalid private backup identity');
    }
  }

  Future<void> _base(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() !=
            paths.normalize(directory.path)) {
      throw const FormatException('Private backup root is not canonical');
    }
  }

  Future<Directory> _folder(
    Directory parent,
    String name, {
    bool create = false,
  }) async {
    final result = Directory(paths.join(parent.path, name));
    final type = await FileSystemEntity.type(result.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      await result.create();
    } else if (type != FileSystemEntityType.directory) {
      throw const FormatException('Private backup folder is missing or linked');
    }
    return result;
  }

  Future<LocalBackupCandidate> _inspect(
    File source, {
    String? expectedManifest,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    await _base(privateSupport);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Private backup input is not a regular file');
    }
    final length = await source.length();
    if (length < 12 || length > LocalBackupCodec.maxArchiveBytes) {
      throw const FormatException('Private backup archive exceeds its limit');
    }
    if (await _space() < length + reserveBytes) {
      throw const LocalBackupSpaceUnavailable();
    }
    cancellation?.check();
    final control = await _folder(
      privateSupport,
      'local-data-v1',
      create: true,
    );
    final generations = await _folder(control, 'generations', create: true);
    final id = _identity();
    _id(id);
    final directory = Directory(paths.join(generations.path, id));
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Candidate identity already exists');
    }
    await directory.create();
    var completed = false;
    try {
      final layout = LocalDataPaths.generation(
        id: id,
        privateSupport: privateSupport,
      );
      final hash = _DigestResult();
      final digest = crypto.sha256.startChunkedConversion(hash);
      var bytes = 0, nextSpaceCheck = 8 * 1024 * 1024;
      Uint8List? metadata;
      Stream<List<int>> input() async* {
        await for (final chunk in source.openRead()) {
          cancellation?.check();
          bytes += chunk.length;
          if (bytes > length || bytes > LocalBackupCodec.maxArchiveBytes) {
            throw const FormatException(
              'Backup input grew during verification',
            );
          }
          digest.add(chunk);
          yield chunk;
        }
      }

      late LocalBackupManifest manifest;
      try {
        manifest = await LocalBackupCodec.decode(input(), (entry, body) async {
          cancellation?.check();
          final parts = entry.path.split('/');
          final folder = await _folder(directory, parts.first, create: true);
          final file = File(paths.join(folder.path, parts.last));
          if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw const FormatException(
              'Duplicate or linked candidate destination',
            );
          }
          final output = file.openWrite();
          try {
            await for (final chunk in body) {
              cancellation?.check();
              if (bytes >= nextSpaceCheck) {
                if (await _space() < reserveBytes) {
                  throw const LocalBackupSpaceUnavailable();
                }
                nextSpaceCheck = bytes + 8 * 1024 * 1024;
              }
              output.add(chunk);
              await output.flush();
            }
          } finally {
            await output.close();
          }
        }, onMetadata: (raw) => metadata = raw);
      } finally {
        digest.close();
      }
      cancellation?.check();
      if (bytes != length ||
          await source.length() != length ||
          hash.value == null ||
          metadata == null) {
        throw const FormatException('Backup input changed or did not finish');
      }
      final manifestHash = crypto.sha256.convert(metadata!).toString();
      if (expectedManifest != null && manifestHash != expectedManifest) {
        throw const FormatException('Retained backup manifest changed');
      }
      final schema =
          await LocalBackupSchemaVerifier(
            factory: factory,
            workspace: Directory(
              paths.join(privateCache.path, 'local-backup-schema-v1'),
            ),
          ).verify(
            File(layout.databasePath),
            declaredRows: manifest.tables,
            expectedSchema: manifest.databaseSchema,
          );
      final content = await LocalBackupContentVerifier(
        factory,
      ).verify(File(layout.databasePath), manifest, schema);
      cancellation?.check();
      // ZIP stores files, not empty directories. A fresh candidate must still
      // have both canonical resource roots before being published as ready.
      // Reuse nofollow folder validation: a raced symlink is never followed.
      await _folder(directory, 'attachments', create: true);
      await _folder(directory, 'drive-blobs', create: true);
      cancellation?.check();
      await File(
        paths.join(directory.path, '_manifest.json'),
      ).writeAsBytes(metadata!, flush: true);
      await File(paths.join(directory.path, '_ready.json')).writeAsString(
        jsonEncode({
          'format': 1,
          'generation': id,
          'sourceSHA256': hash.value!.toString(),
          'manifestSHA256': manifestHash,
        }),
        flush: true,
      );
      cancellation?.check();
      final candidate = LocalBackupCandidate._(
        _discard,
        id: id,
        layout: layout,
        manifest: manifest,
        manifestSHA256: manifestHash,
        sourceSHA256: hash.value!.toString(),
        sourceBytes: bytes,
        contentReport: content,
      );
      completed = true;
      return candidate;
    } finally {
      // This identity has not escaped to the activation controller until return.
      // Post-return disposal always goes through serialized native control.
      if (!completed &&
          await FileSystemEntity.type(directory.path, followLinks: false) ==
              FileSystemEntityType.directory) {
        await directory.delete(recursive: true);
      }
    }
  }
}

class _DigestResult implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest value) => this.value = value;
  @override
  void close() {}
}
