import 'dart:async';
import 'package:flutter/foundation.dart';

/// Per-library lifecycle. Retiring prevents new operations immediately; draining
/// waits only existing repository work, never an entire human-driven route.
class ImageLibraryOwner extends ChangeNotifier {
  ImageLibraryOwner({bool Function()? isCurrentScope, this._onDrained})
    : _scope = isCurrentScope;
  final bool Function()? _scope;
  final void Function()? _onDrained;
  bool _reportedDrained = false;
  bool _scopeCurrent() {
    try {
      return _scope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  bool _retired = false;
  Future<void>? _retirement;
  final _retirementBarriers = <Future<void> Function()>{};

  /// Actual native capability revocation is part of Root's existing drain.
  VoidCallback addRetirementBarrier(Future<void> Function() barrier) {
    if (!isCurrent) throw StateError('Image library retired');
    _retirementBarriers.add(barrier);
    return () => _retirementBarriers.remove(barrier);
  }

  final _pending = <Future<void>>{};
  bool get isCurrent => !_retired && _scopeCurrent();
  Future<T> run<T>(Future<T> Function() action) {
    if (!isCurrent) return Future<T>.error(StateError('Image library retired'));
    final future = Future<T>.sync(action);
    final tracked = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending.add(tracked);
    unawaited(
      tracked.then((_) {
        _pending.remove(tracked);
      }),
    );
    return future.then((value) {
      if (!isCurrent) throw StateError('Image library retired');
      return value;
    });
  }

  Future<void> retireAndDrain() {
    final previous = _retirement;
    if (previous != null) return previous;
    final completion = Completer<void>();
    _retirement = completion.future;
    if (!_retired) {
      _retired = true;
      notifyListeners();
    }
    unawaited(
      Future<void>.sync(_drain).then(
        completion.complete,
        onError: (Object error, StackTrace stack) {
          // Keep the retired identity and barriers. A later explicit drain retries
          // only cleanup; it never authorizes another repository operation.
          _retirement = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _drain() async {
    await Future.wait([
      for (final barrier in _retirementBarriers.toList())
        Future<void>.sync(barrier),
      ..._pending,
    ]);
    await Future.wait(
      _pending.toList().map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
    if (!_reportedDrained) {
      _reportedDrained = true;
      _onDrained?.call();
    }
  }
}
