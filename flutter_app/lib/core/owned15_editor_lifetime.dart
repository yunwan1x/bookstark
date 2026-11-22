import 'dart:async';
import 'attachments.dart';
import 'owned_preview_controller.dart';
import 'owned15_save_journal.dart';
import 'protected_complex_lifetime.dart';
import 'protected_complex_memory_store.dart';

/// Local15 plaintext lifetime; neither account transport nor a database owner.
/// Root registers it BEFORE password dialogs and joins real work, not Navigator.
final class Owned15EditorLifetime implements ProtectedReviewOwner {
  Owned15EditorLifetime({
    required this.journal,
    required this.isCurrentScope,
    required this.drainCrypto,
    required this.onDrained,
    this.afterDrained,
  });
  final Owned15SaveJournal journal;
  final bool Function() isCurrentScope;
  final Future<void> Function() drainCrypto;
  final void Function(Owned15EditorLifetime) onDrained;
  final Future<void> Function()? afterDrained;
  final _requests = <AttachmentCancellation>{};
  final _work = <Future<void>>{};
  final _abort = Completer<void>();
  Future<void> get abortTrigger => _abort.future;
  @override
  OwnedPreviewController preview = OwnedPreviewController();
  void Function()? _closeRepository;
  Future<void> Function()? _drainRepository;
  Future<void> Function()? _closeRoute;
  ProtectedComplexMemoryStore? _memory;
  Future<void>? _closing;
  bool _retiring = false, _closed = false, _reported = false;
  @override
  bool get current {
    if (_retiring || _closed) return false;
    try {
      return isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  void _check() {
    if (!current) throw StateError('Owned15 editor retired');
  }

  Future<T> run<T>(
    Future<T> Function(AttachmentCancellation) action, {
    required void Function(T result) onLateResult,
  }) async {
    _check();
    final request = AttachmentCancellation();
    final done = Completer<void>();
    _requests.add(request);
    _work.add(done.future);
    try {
      final result = await action(request);
      if (!current) {
        onLateResult(result);
        throw StateError('Owned15 opening retired');
      }
      return result;
    } finally {
      _requests.remove(request);
      _work.remove(done.future);
      done.complete();
    }
  }

  void bindRepository({
    required void Function() close,
    required Future<void> Function() drain,
  }) {
    if (!current || _closeRepository != null) {
      close();
      throw StateError('Owned15 repository lifetime mismatch');
    }
    _closeRepository = close;
    _drainRepository = drain;
  }

  void bindRoute(Future<void> Function()? close) {
    _check();
    _closeRoute = close;
  }

  void bindMemory(ProtectedComplexMemoryStore memory) {
    if (!current) {
      memory.close();
      throw StateError('Owned15 memory retired');
    }
    _memory?.close();
    _memory = memory;
  }

  @override
  Future<void> nextPreview() async {
    await preview.retire();
    _check();
    preview.dispose();
    preview = OwnedPreviewController();
  }

  @override
  Future<void> retire() {
    _retiring = true;
    if (!_abort.isCompleted) _abort.complete();
    for (final request in _requests) {
      request.cancel();
    }
    _closeRepository?.call();
    journal.retire();
    final existing = _closing;
    if (existing != null) return existing;
    final done = Completer<void>();
    final work = done.future;
    _closing = work;
    // Publish the retirement future BEFORE removing a route can synchronously
    // dispose its guard and re-enter retire().
    unawaited(
      Future<void>.sync(_close).then<void>(
        (_) {
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_closing, work)) _closing = null;
          done.completeError(error, stack);
        },
      ),
    );
    return work;
  }

  Future<void> _close() async {
    final route = _closeRoute;
    if (route != null) await route();
    if (identical(_closeRoute, route)) _closeRoute = null;
    await preview.retire();
    while (_work.isNotEmpty) {
      await Future.wait(_work.toList());
    }
    await _drainRepository?.call();
    await drainCrypto();
    await journal.drain();
    _memory?.close();
    _memory = null;
    await afterDrained?.call();
    _closeRepository = null;
    _drainRepository = null;
    _closed = true;
    if (!_reported) {
      _reported = true;
      onDrained(this);
    }
  }
}
