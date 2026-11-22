import 'dart:async';
import 'native_complex_source_io.dart';
import 'owned_preview_controller.dart';

/// One ordinary-local HTML scope, with serial irreversible preview bodies.
/// Native close + actual resource IO finish before a replacement can open.
class LocalHtmlPreviewOwner {
  LocalHtmlPreviewOwner({
    required this.isCurrentScope, this.sourceOwner,
  }) {
    _scopeDrain = retireAndDrain;
    sourceOwner?.addRetirementDrain(_scopeDrain);
  }
  final bool Function() isCurrentScope;
  final ComplexSourceIoScope? sourceOwner;
  late final Future<void> Function() _scopeDrain;
  OwnedPreviewController? _active;
  Future<void> _tail = Future<void>.value();
  final Set<Future<void>> _pending = {};
  final _disposedBodies = Expando<bool>();
  bool _retired = false;
  bool get current {
    try {
      sourceOwner?.guard();
      return !_retired && isCurrentScope();
    } catch (_) { return false; }
  }
  void guard() {
    if (!current) throw StateError('Local HTML preview owner retired');
  }
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
  Future<T> use<T>(Future<T> Function() operation) {
    guard();
    final result = Future<T>.sync(operation);
    late final Future<void> tracked;
    tracked = result.then<void>((_) {}, onError: (Object _, StackTrace _) {})
      .whenComplete(() { _pending.remove(tracked); });
    _pending.add(tracked);
    return result;
  }
  Future<void> _joinIO() async {
    while (_pending.isNotEmpty) {
      await Future.wait<void>(List.of(_pending));
    }
  }
  Future<void> _close(OwnedPreviewController? body) async {
    if (body == null) return;
    await body.retire();
    if (_disposedBodies[body] != true) {
      _disposedBodies[body] = true;
      body.dispose();
    }
    if (identical(_active, body)) _active = null;
  }
  Future<OwnedPreviewController> nextPreview() => _serial(() async {
    guard();
    await _close(_active);
    await _joinIO();
    guard();
    final body = OwnedPreviewController();
    _active = body;
    return body;
  });
  Future<void> release(OwnedPreviewController body) =>
      _serial(() => _close(body));

  Future<void> retireAndDrain() {
    _retired = true;
    return _serial(() async {
      await _close(_active);
      await _joinIO();
      sourceOwner?.removeRetirementDrain(_scopeDrain);
    });
  }
}
