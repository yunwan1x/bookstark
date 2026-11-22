import 'dart:async';
import 'owned_preview_controller.dart';
import 'protected_owned_complex_journal.dart';
import 'protected_complex_memory_store.dart';
import 'remote_owned_complex_store.dart';

/// Root registers this before showing a password dialog. Retirement blocks all
/// callbacks synchronously and joins only this owner's dialog/native preview.
abstract interface class ProtectedComplexOwner {
  bool get current;
  Future<void> retire();
}

abstract interface class ProtectedReviewOwner implements ProtectedComplexOwner {
  OwnedPreviewController get preview;
  Future<void> nextPreview();
}

class ProtectedComplexLifetime implements ProtectedReviewOwner {
  ProtectedComplexLifetime({
    required this.journal,
    required this.isCurrentScope,
    required this.onDrained,
  });
  final ProtectedOwnedComplexJournal journal;
  final bool Function() isCurrentScope;
  final void Function(ProtectedComplexLifetime) onDrained;
  final _abort = Completer<void>();
  Future<void> get abortTrigger => _abort.future;
  RemoteOwnedComplexStore? _repository;
  void Function()? _recoveryDispose;
  ProtectedComplexMemoryStore? _memory;
  @override
  OwnedPreviewController preview = OwnedPreviewController();
  Future<void> Function()? _retireRoute;
  Future<void>? _retiring;
  bool _closing = false, _closed = false, _reported = false;
  @override
  bool get current {
    if (_closing || _closed) return false;
    try {
      return isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  void bindRepository(RemoteOwnedComplexStore repository) {
    if (!current) {
      repository.dispose();
      throw StateError('Protected owner retired');
    }
    _repository?.dispose();
    _repository = repository;
  }

  void bindRecoveryDispose(void Function() close) {
    if (!current) {
      close();
      throw StateError('Protected owner retired');
    }
    _recoveryDispose?.call();
    _recoveryDispose = close;
  }

  void bindMemory(ProtectedComplexMemoryStore memory) {
    if (!current) {
      memory.close();
      throw StateError('Protected owner retired');
    }
    _memory?.close();
    _memory = memory;
  }

  void bindRoute(Future<void> Function()? close) {
    if (!current) throw StateError('Protected owner retired');
    _retireRoute = close;
  }

  @override
  Future<void> nextPreview() async {
    await preview.retire();
    if (!current) throw StateError('Protected owner retired');
    preview.dispose();
    preview = OwnedPreviewController();
  }

  @override
  Future<void> retire() {
    _closing = true;
    if (!_abort.isCompleted) _abort.complete();
    _repository?.dispose();
    _recoveryDispose?.call();
    journal.retire();
    final pending = _retiring;
    if (pending != null) return pending;
    final work = _close();
    _retiring = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_retiring, work)) _retiring = null;
      }),
    );
    return work;
  }

  Future<void> _close() async {
    final close = _retireRoute;
    if (close != null) await close();
    if (identical(_retireRoute, close)) _retireRoute = null;
    await preview.retire();
    await journal.drain();
    _memory?.close();
    _memory = null;
    _repository = null;
    _closed = true;
    if (!_reported) {
      _reported = true;
      onDrained(this);
    }
  }
}
