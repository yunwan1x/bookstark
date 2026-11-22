import 'dart:async';
import 'package:flutter/foundation.dart';

/// One body lifetime. Retirement is irreversible; a new body needs a new owner.
final class OwnedPreviewController extends ChangeNotifier {
  Object? _owner;
  Future<void> Function()? _close;
  Future<void>? _pending;
  bool _retired = false, _disposed = false;
  bool get retired => _retired || _disposed;

  /// Preview implementation only. Never shares a controller between two views.
  void bind(Object owner, Future<void> Function() close) {
    if (retired) return;
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError('Preview controller already has an owner');
    }
    _owner = owner;
    _close = close;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    unawaited(retire().catchError((Object _) {}));
    _owner = null;
    // Keep a failed close retryable until its old native lease is gone.
  }

  /// Observe native retirement without recursively closing its session queue.
  void ownerRetiring(Object owner, Future<void> barrier) {
    if (_disposed || !identical(_owner, owner)) return;
    if (_pending == null) _remember(barrier);
    final notify = !_retired;
    _retired = true;
    if (notify) notifyListeners();
  }

  Future<void> retire() {
    final pending = _pending;
    if (pending != null) return pending;
    final notify = !_retired;
    _retired = true;
    final close = _close;
    final work = close == null
        ? Future<void>.value()
        : Future<void>.sync(close);
    _remember(work);
    if (notify && !_disposed) notifyListeners();
    return work;
  }

  void _remember(Future<void> work) {
    _pending = work;
    unawaited(
      work.then<void>(
        (_) {
          if (_owner == null && _retired) _close = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_pending, work)) _pending = null;
        },
      ),
    );
  }

  @override
  void dispose() {
    unawaited(retire().catchError((Object _) {}));
    _disposed = true;
    _owner = null;
    _close = null;
    super.dispose();
  }
}
