import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'complex_editor_document.dart';
import 'package:flutter/services.dart';
import 'attachments.dart';

typedef LocalArticleAttachmentPickerInvoke =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

class PickedLocalArticleAttachment {
  PickedLocalArticleAttachment._(
    this._owner,
    this.id,
    this.bytes,
    this.sha256,
    this.name,
  );
  final NativeLocalArticleAttachmentPicker _owner;
  final String name;
  bool _released = false;
  final String id, sha256;
  final int bytes;
}

/// Only opaque inbox identities cross this port; never content URIs or paths.
class NativeLocalArticleAttachmentPicker {
  NativeLocalArticleAttachmentPicker({
    LocalArticleAttachmentPickerInvoke? invoke,
    String Function()? identity,
    Future<Directory> Function()? cacheDirectory,
    this.timeout = const Duration(minutes: 10),
    this.imagesOnly = false,
  }) : _invoke =
           invoke ??
           ((method, arguments) =>
               channel.invokeMethod<Object?>(method, arguments)),
       _identity = identity ?? attachmentId,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Positive timeout required');
    }
  }
  static const channel = MethodChannel(
    'bookstark/local_article_attachment_picker',
  );
  static const maxBytes = 64 * 1024 * 1024;
  final LocalArticleAttachmentPickerInvoke _invoke;
  final Future<Directory> Function() _cacheDirectory;
  final String Function() _identity;
  final Duration timeout;
  final bool imagesOnly;
  String? _active;
  bool _disposed = false;
  Completer<void>? _abortWait;
  Future<void>? _cancelFuture, _disposeFuture;

  PickedLocalArticleAttachment? _receipt(Object? raw, String id) {
    if (raw is! Map ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['cancelled'] is! bool) {
      throw const FormatException('Invalid attachment picker receipt');
    }
    if (raw['cancelled'] == true) {
      if (raw.length != 2) {
        throw const FormatException('Invalid cancellation receipt');
      }
      return null;
    }
    final bytes = raw['bytes'], hash = raw['sha256'], name = raw['name'];
    if (raw.length != 6 ||
        raw['id'] != id ||
        bytes is! int ||
        bytes < 0 ||
        bytes > (imagesOnly ? 5 * 1024 * 1024 : maxBytes) ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        name is! String ||
        name.isEmpty ||
        name != attachmentName(name)) {
      throw const FormatException('Unbound attachment inbox receipt');
    }
    ComplexEditorDocument.validateText(name);
    return PickedLocalArticleAttachment._(this, id, bytes, hash, name);
  }

  Future<PickedLocalArticleAttachment?> pick() async {
    if (_disposed) throw StateError('Attachment picker owner was disposed');
    if (_active != null) {
      throw StateError('Attachment selection already active');
    }
    final id = _identity();
    _checkId(id);
    _active = id;
    _cancelFuture = null;
    final abort = Completer<void>();
    _abortWait = abort;
    var abandoned = false;
    try {
      final native = _invoke('pick', {
        'id': id,
        if (imagesOnly) 'imagesOnly': true,
      });
      unawaited(
        native.then<void>((raw) async {
          if (!_disposed && !abandoned) return;
          try {
            // Only a bound completed receipt authorizes cleanup of this owner's
            // generated inbox identity. Native refuses any still-active copy.
            if (_receipt(raw, id) != null) await _releaseOwned(id);
          } catch (_) {
            // An unconfirmed private copy stays retained; never delete another ID.
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final raw =
          await Future.any<Object?>([
            native,
            abort.future.then<Object?>(
              (_) => throw const AttachmentCancelled(),
            ),
          ]).timeout(
            timeout,
            onTimeout: () {
              abandoned = true;
              throw TimeoutException(
                'Attachment document selection deadline',
                timeout,
              );
            },
          );
      if (_disposed) throw const AttachmentCancelled();
      return _receipt(raw, id);
    } on TimeoutException {
      try {
        await cancel();
      } catch (_) {
        // Native also cancels on activity destruction and its copy deadline.
      }
      rethrow;
    } finally {
      _active = null;
      if (identical(_abortWait, abort)) _abortWait = null;
    }
  }

  Future<void> cancel() {
    final pending = _cancelFuture;
    if (pending != null) return pending;
    final id = _active;
    if (id == null) return Future<void>.value();
    return _cancelFuture ??= _cancel(id);
  }

  Future<void> _cancel(String id) async {
    final raw = await _invoke('cancel', {
      'id': id,
    }).timeout(const Duration(seconds: 5));
    if (raw is! Map ||
        raw.length != 2 ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['cancelled'] != true) {
      throw const FormatException('Invalid picker cancellation');
    }
  }

  /// Retires this owner's wait immediately, even if Android's document activity
  /// has not returned. A late bound copy is cleaned through the native owner.
  Future<void> dispose() {
    final previous = _disposeFuture;
    if (previous != null) return previous;
    _disposed = true;
    final cancellation = cancel();
    final abort = _abortWait;
    if (abort != null && !abort.isCompleted) abort.complete();
    return _disposeFuture = cancellation;
  }

  void _owned(PickedLocalArticleAttachment picked) {
    if (!identical(picked._owner, this) || picked._released) {
      throw StateError('Attachment inbox belongs to another operation');
    }
  }

  Future<XFile> open(PickedLocalArticleAttachment picked) async {
    _owned(picked);
    if (_disposed) throw const AttachmentCancelled();
    final cache = await _cacheDirectory();
    final canonical = await cache.resolveSymbolicLinks();
    final inbox = Directory(
      paths.join(canonical, 'local-article-attachment-inbox-v1'),
    );
    if (await FileSystemEntity.type(inbox.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Private attachment inbox unavailable');
    }
    final file = File(paths.join(inbox.path, '${picked.id}.attachment'));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != file.absolute.path ||
        await file.length() != picked.bytes) {
      throw const FormatException('Unbound attachment inbox file');
    }
    _owned(picked);
    if (_disposed) throw const AttachmentCancelled();
    return _InboxAttachmentFile(file.path, picked);
  }

  Future<void> release(PickedLocalArticleAttachment picked) async {
    if (!identical(picked._owner, this)) {
      throw StateError('Attachment inbox belongs to another operation');
    }
    _checkId(picked.id);
    if (_active == picked.id) {
      throw StateError('Attachment selection is active');
    }
    picked._released = true;
    await _releaseOwned(picked.id);
  }

  Future<void> _releaseOwned(String id) async {
    final raw = await _invoke('release', {
      'id': id,
    }).timeout(const Duration(seconds: 10));
    if (raw is! Map ||
        raw.length != 2 ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['released'] != id) {
      throw const FormatException('Unbound inbox release receipt');
    }
  }

  void _checkId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid attachment inbox identity');
    }
  }
}

class _InboxAttachmentFile extends XFile {
  _InboxAttachmentFile(super.path, this.picked);
  final PickedLocalArticleAttachment picked;
  @override
  String get name => picked.name;
  void _check() {
    if (picked._released || picked._owner._disposed) {
      throw const AttachmentCancelled();
    }
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    _check();
    if (start != null || end != null) {
      throw StateError('Whole attachment integrity check required');
    }
    final sink = _DigestReceipt();
    final digest = crypto.sha256.startChunkedConversion(sink);
    var length = 0;
    await for (final chunk in File(path).openRead()) {
      _check();
      length += chunk.length;
      if (length > NativeLocalArticleAttachmentPicker.maxBytes ||
          length > picked.bytes) {
        throw const FormatException('Attachment stream exceeds receipt');
      }
      digest.add(chunk);
      yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    }
    digest.close();
    _check();
    if (length != picked.bytes || sink.value?.toString() != picked.sha256) {
      throw const FormatException('Attachment inbox integrity mismatch');
    }
  }
}

class _DigestReceipt implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest value) {
    this.value = value;
  }

  @override
  void close() {}
}
