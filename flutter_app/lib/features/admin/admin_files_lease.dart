import 'package:flutter/services.dart';

/// Tracks native creation/destruction without retaining document content or widgets.
/// Window protection may be released only after [retire] acknowledges destruction.
class AdminFileEditorLease {
  MethodChannel? _channel;
  Future<void>? _creation, _retirement;
  bool _closed = false, _retired = false;
  bool get closed => _closed;
  bool get retired => _retired;

  Future<void> create(int id, Future<void> Function() createView) {
    if (_closed) return Future.value();
    if (_creation != null) {
      throw StateError('File view creation already started');
    }
    _channel = MethodChannel('bookstark/admin_file_editor/$id');
    return _creation = Future<void>.sync(createView);
  }

  Future<void> retire() => _retirement ??= _retire();

  Future<void> _retire() async {
    _closed = true;
    final creation = _creation;
    if (creation != null) {
      try {
        await creation;
      } catch (_) {
        // Still attempt destruction if native creation partially completed.
      }
    }
    final channel = _channel;
    if (channel != null) {
      try {
        await channel.invokeMethod<void>('retire');
      } on MissingPluginException {
        // The native view removes its handler only after synchronous destruction.
      }
    }
    _retired = true;
  }
}
