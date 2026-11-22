import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'attachments.dart';
import 'image_content.dart';
import 'images_repository.dart';

enum ImageUploadState {
  pending,
  preparing,
  checking,
  uploading,
  confirmed,
  reused,
  failed,
  uncertain,
}

class ImageUploadEntry {
  ImageUploadEntry._(this.id, this.file, this._category);
  final int id;
  final XFile file;
  ImageCategory _category;
  ImageUploadState _state = ImageUploadState.pending;
  UploadedImageReference? _result;
  String? _hash, _error;
  int? _sourceSize;
  int _sent = 0;
  bool _attempted = false, _verifiedMissing = false, _verifying = false;
  ImageCategory get category => _category;
  ImageUploadState get state => _state;
  UploadedImageReference? get result => _result;
  String? get hash => _hash;
  String? get error => _error;
  int? get sourceSize => _sourceSize;
  int get sent => _sent;
  bool get verifiedMissing => _verifiedMissing;
  bool get verifying => _verifying;
  bool get completed =>
      state == ImageUploadState.confirmed || state == ImageUploadState.reused;
}

/// One bounded byte snapshot at a time; completed/failed rows do not retain it.
/// Explicit retries are separate from hash verification of uncertain writes.
class ImageUploadController extends ChangeNotifier {
  ImageUploadController(this.repository);
  final ImagesRepository repository;
  final _entries = <ImageUploadEntry>[];
  bool _running = false, _stopping = false, _closed = false;
  int _next = 1;
  ImageCategory _category = ImageCategory.editor;
  ImageUploadEntry? _active;
  AttachmentCancellation? _cancellation;
  List<ImageUploadEntry> get entries => List.unmodifiable(_entries);
  bool get running => _running;
  bool get stopping => _stopping;
  ImageUploadEntry? get active => _active;
  ImageCategory get category => _category;
  int get pendingCount =>
      _entries.where((entry) => entry.state == ImageUploadState.pending).length;
  int get confirmedCount => _entries.where((entry) => entry.completed).length;
  int get uncertainCount => _entries
      .where((entry) => entry.state == ImageUploadState.uncertain)
      .length;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  bool _owns(ImageUploadEntry entry) => _entries.contains(entry);
  void setCategory(ImageCategory value) {
    if (_running || _closed) return;
    _category = value;
    for (final entry in _entries) {
      if (!entry._attempted && entry.state == ImageUploadState.pending) {
        entry._category = value;
      }
    }
    _notify();
  }

  Future<void> addFiles(List<XFile> files) async {
    if (_running || _closed) return;
    for (final file in files) {
      final entry = ImageUploadEntry._(_next++, file, _category);
      try {
        attachmentName(file.name);
        entry._sourceSize = await file.length();
      } catch (error) {
        entry._state = ImageUploadState.failed;
        entry._error = error.toString();
      }
      if (_closed) return;
      _entries.add(entry);
    }
    _notify();
  }

  void remove(ImageUploadEntry entry, {bool abandonUncertain = false}) {
    if (_running ||
        _closed ||
        (!_owns(entry)) ||
        (entry.state == ImageUploadState.uncertain && !abandonUncertain)) {
      return;
    }
    _entries.remove(entry);
    _notify();
  }

  void retryRejected(ImageUploadEntry entry) {
    if (_running ||
        _closed ||
        !_owns(entry) ||
        entry.state != ImageUploadState.failed) {
      return;
    }
    entry._state = ImageUploadState.pending;
    entry._error = null;
    _notify();
  }

  void allowExplicitRetransmission(ImageUploadEntry entry) {
    if (_running ||
        _closed ||
        !_owns(entry) ||
        entry.state != ImageUploadState.uncertain ||
        !entry._verifiedMissing) {
      return;
    }
    entry._state = ImageUploadState.pending;
    entry._verifiedMissing = false;
    entry._error = null;
    _notify();
  }

  void stop() {
    if (!_running) return;
    _stopping = true;
    _cancellation?.cancel();
    _notify();
  }

  Future<void> start() async {
    if (_running || _closed || pendingCount == 0) return;
    _running = true;
    _stopping = false;
    _notify();
    try {
      for (final entry in List<ImageUploadEntry>.of(_entries)) {
        if (_stopping || _closed) break;
        if (entry.state == ImageUploadState.pending) await _process(entry);
      }
    } finally {
      _running = false;
      _active = null;
      _cancellation = null;
      _notify();
    }
  }

  Future<void> _process(ImageUploadEntry entry) async {
    final cancellation = AttachmentCancellation();
    _cancellation = cancellation;
    _active = entry;
    entry._attempted = true;
    entry._error = null;
    entry._sent = 0;
    entry._verifiedMissing = false;
    entry._state = ImageUploadState.preparing;
    _notify();
    var posted = false;
    try {
      final payload = await ImageUploadPayload.readFile(
        entry.file,
        entry.category,
        cancellation: cancellation,
      );
      if (imageContentMime(payload.bytes) == null) {
        throw const FormatException(
          '请选择JPEG、PNG、GIF、WebP或SVG图片 / Choose a JPEG, PNG, GIF, WebP or SVG image',
        );
      }
      if (entry._hash != null && entry._hash != payload.hash) {
        throw const FormatException(
          '源文件内容已变化，请移除后重新选择 / Source changed; remove and select it again',
        );
      }
      entry._hash = payload.hash;
      entry._sourceSize = payload.bytes.length;
      entry._state = ImageUploadState.checking;
      _notify();
      final existing = await repository.byHash(payload.hash);
      if (_closed) return;
      if (existing != null) {
        entry._result = existing;
        entry._state = ImageUploadState.reused;
        _notify();
        return;
      }
      cancellation.check();
      entry._state = ImageUploadState.uploading;
      posted = true;
      _notify();
      final reply = await repository.upload(
        payload,
        cancellation: cancellation,
        onSent: (sent, total) {
          if (_closed) return;
          entry._sent = sent;
          _notify();
        },
      );
      if (_closed) return;
      entry._result = reply;
      entry._state = ImageUploadState.confirmed;
      entry._error = null;
    } catch (error) {
      if (_closed) return;
      if (!posted && cancellation.cancelled) {
        entry._state = ImageUploadState.pending;
        entry._error = '已停止，尚未发送上传请求 / Stopped before upload submission';
      } else if (posted &&
          !(error is ApiFailure &&
              {
                400,
                401,
                403,
                404,
                405,
                413,
                415,
                422,
              }.contains(error.status))) {
        entry._state = ImageUploadState.uncertain;
        entry._error =
            '上传结果尚未确认，请先按哈希核对 / Upload is unconfirmed; verify by hash first\n$error';
      } else {
        entry._state = ImageUploadState.failed;
        entry._error = error.toString();
      }
    } finally {
      _notify();
    }
  }

  Future<void> verify(ImageUploadEntry entry) async {
    if (_running ||
        _closed ||
        !_owns(entry) ||
        entry.state != ImageUploadState.uncertain ||
        entry.hash == null) {
      return;
    }
    _running = true;
    _active = entry;
    _stopping = false;
    entry._verifying = true;
    _notify();
    try {
      final found = await repository.byHash(entry.hash!);
      if (_closed) return;
      if (found != null) {
        entry._result = found;
        entry._state = ImageUploadState.confirmed;
        entry._error = null;
        entry._verifiedMissing = false;
      } else {
        entry._verifiedMissing = true;
        entry._error =
            '尚未查到记录，前次请求可能仍在处理，可稍后再核对 / Not found yet; the previous request may still be processing';
      }
    } catch (error) {
      if (!_closed) {
        entry._verifiedMissing = false;
        entry._error = error.toString();
      }
    } finally {
      entry._verifying = false;
      _running = false;
      _active = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _stopping = true;
    _cancellation?.cancel();
    super.dispose();
  }
}
