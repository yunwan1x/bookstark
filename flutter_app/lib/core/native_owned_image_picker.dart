import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'attachments.dart';
import 'complex_editor_document.dart';

typedef OwnedImagePickerInvoke =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

/// Owns only random private inbox handles. Never exports provider URIs or paths.
class NativeOwnedImagePicker {
  NativeOwnedImagePicker({
    OwnedImagePickerInvoke? invoke,
    Future<Directory> Function()? cacheDirectory,
    String Function()? identity,
    required this.isCurrent,
  }) : _invoke =
           invoke ??
           ((method, args) => channel.invokeMethod<Object?>(method, args)),
       _cache = cacheDirectory ?? getTemporaryDirectory,
       _identity = identity ?? attachmentId {
    owner = _identity();
    _id(owner);
  }
  static const channel = MethodChannel('bookstark/owned_image_picker');
  static const maxBytes = 64 * 1024 * 1024, maxBatchBytes = 256 * 1024 * 1024;
  final OwnedImagePickerInvoke _invoke;
  final Future<Directory> Function() _cache;
  final String Function() _identity;
  final bool Function() isCurrent;
  late final String owner;
  bool _retired = false;
  Future<void>? _registration, _retirement;
  final _abort = Completer<void>();
  void _check() {
    if (_retired || !isCurrent()) throw const AttachmentCancelled();
  }

  void _id(String value) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
      throw const FormatException('Invalid image inbox identity');
    }
  }

  Future<void> _register() async {
    _check();
    final raw = await _invoke('registerOwner', {
      'owner': owner,
    }).timeout(const Duration(seconds: 5));
    if (raw is! Map ||
        raw.length != 3 ||
        raw['format'] != 1 ||
        raw['owner'] != owner ||
        raw['registered'] != true) {
      throw const FormatException('Unbound image owner');
    }
    _check();
  }

  bool owns(XFile file) =>
      file is _OwnedImageFile && identical(file.picker, this);
  bool _choosing = false;
  Future<List<XFile>> pick() async {
    _check();
    if (_choosing) throw StateError('Image selection active');
    _choosing = true;
    final operation = _identity();
    _id(operation);
    try {
      await (_registration ??= _register());
      _check();
      final native = _invoke('pick', {'owner': owner, 'id': operation});
      // Native retirement drains late files, so abandoned results cannot be
      // adopted by a different page, account or scope.
      final raw = await Future.any<Object?>([
        native,
        _abort.future.then<Object?>((_) => throw const AttachmentCancelled()),
      ]);
      _check();
      if (raw is! Map || raw['format'] != 1 || raw['cancelled'] is! bool) {
        throw const FormatException('Invalid image selection');
      }
      if (raw['cancelled'] == true) {
        if (raw.length != 2) {
          throw const FormatException('Invalid cancellation');
        }
        return [];
      }
      if (raw.length != 5 ||
          raw['owner'] != owner ||
          raw['id'] != operation ||
          raw['files'] is! List) {
        throw const FormatException('Unbound image selection');
      }
      final rows = raw['files'] as List;
      if (rows.isEmpty || rows.length > 20) {
        throw const FormatException('Invalid image count');
      }
      final root = await _cache();
      _check();
      final inbox = Directory(
        '${await root.resolveSymbolicLinks()}/owned-image-inbox-v1',
      );
      if (await FileSystemEntity.type(inbox.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Image inbox unavailable');
      }
      final result = <XFile>[];
      final seen = <String>{};
      var total = 0;
      for (final row in rows) {
        _check();
        if (row is! Map || row.length != 5) {
          throw const FormatException('Invalid image receipt');
        }
        final id = row['id'],
            name = row['name'],
            mime = row['mime'],
            bytes = row['bytes'],
            hash = row['sha256'];
        if (id is! String ||
            name is! String ||
            mime is! String ||
            bytes is! int ||
            hash is! String) {
          throw const FormatException('Invalid image metadata');
        }
        _id(id);
        if (!seen.add(id) ||
            name != attachmentName(name) ||
            !{
              'image/png',
              'image/jpeg',
              'image/gif',
              'image/webp',
              'image/svg+xml',
            }.contains(mime) ||
            bytes <= 0 ||
            bytes > maxBytes ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('Invalid image bounds');
        }
        ComplexEditorDocument.validateText(name);
        total += bytes;
        if (total > maxBatchBytes) {
          throw const FormatException('Image batch exceeds bound');
        }
        final file = File('${inbox.path}/$id.image');
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await file.resolveSymbolicLinks() != file.absolute.path ||
            await file.length() != bytes) {
          throw const FormatException('Unbound image file');
        }
        _check();
        result.add(
          _OwnedImageFile(file.path, this, id, name, mime, bytes, hash),
        );
      }
      return result;
    } finally {
      _choosing = false;
    }
  }

  /// Called by ImageLibraryOwner retirement barrier, not only widget dispose.
  Future<void> retire() {
    _retired = true;
    if (!_abort.isCompleted) _abort.complete();
    final previous = _retirement;
    if (previous != null) return previous;
    final completion = Completer<void>();
    _retirement = completion.future;
    unawaited(
      Future<void>.sync(_retire).then(
        completion.complete,
        onError: (Object error, StackTrace stack) {
          // Revocation/abort is permanent. Only failed cleanup acknowledgement retries.
          _retirement = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _retire() async {
    // Even a register in flight must finish before native retirement; otherwise
    // a late register could recreate capability after a supposedly drained owner.
    try {
      await _registration;
    } catch (_) {}
    final raw = await _invoke('retireOwner', {
      'owner': owner,
    }).timeout(const Duration(seconds: 130));
    if (raw is! Map ||
        raw.length != 3 ||
        raw['format'] != 1 ||
        raw['owner'] != owner ||
        raw['retired'] != true) {
      throw const FormatException('Image owner retirement unconfirmed');
    }
  }

  Future<void> release(XFile file) async {
    if (file is! _OwnedImageFile || !identical(file.picker, this)) {
      throw StateError('Unowned image');
    }
    if (file.released) return;
    if (_retired) {
      await retire();
      file.released = true;
      return;
    }
    final raw = await _invoke('release', {
      'owner': owner,
      'id': file.id,
    }).timeout(const Duration(seconds: 10));
    if (raw is! Map ||
        raw.length != 2 ||
        raw['format'] != 1 ||
        raw['released'] != file.id) {
      throw const FormatException('Image release unconfirmed');
    }
    file.released = true;
  }
}

class _OwnedImageFile extends XFile {
  _OwnedImageFile(
    super.path,
    this.picker,
    this.id,
    this.displayName,
    this.mime,
    this.size,
    this.hash,
  );
  final NativeOwnedImagePicker picker;
  final String id, displayName, mime, hash;
  final int size;
  bool released = false;
  @override
  String get name => displayName;
  @override
  String? get mimeType => mime;
  void _check() {
    picker._check();
    if (released) throw const AttachmentCancelled();
  }

  @override
  Future<int> length() async {
    _check();
    return size;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    _check();
    if (start != null || end != null) {
      throw StateError('Whole original image integrity required');
    }
    final sink = _Digest();
    final digest = crypto.sha256.startChunkedConversion(sink);
    var read = 0;
    await for (final bytes in File(path).openRead()) {
      _check();
      read += bytes.length;
      if (read > size || read > NativeOwnedImagePicker.maxBytes) {
        throw const FormatException('Image source exceeds receipt');
      }
      digest.add(bytes);
      yield Uint8List.fromList(bytes);
    }
    digest.close();
    _check();
    if (read != size || sink.value?.toString() != hash) {
      throw const FormatException('Image original bytes changed');
    }
  }
}

class _Digest implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest v) {
    value = v;
  }

  @override
  void close() {}
}
