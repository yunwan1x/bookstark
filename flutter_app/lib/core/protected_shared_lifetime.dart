import 'dart:async';
import 'anonymous_shared_capability.dart';
import 'owned_preview_controller.dart';
import 'protected_complex_lifetime.dart';
import 'protected_shared_journal.dart';
import 'protected_shared_memory_store.dart';

/// Root joins this through the same ProtectedComplexOwner retirement barrier.
class ProtectedSharedLifetime implements ProtectedComplexOwner {
  ProtectedSharedLifetime({
    required this.transport,
    required this.isCurrentScope,
    required this.onDrained,
  });
  final AnonymousSharedCapability transport;
  ProtectedSharedJournal? _journal;
  void bindJournal(ProtectedSharedJournal journal) {
    if (!current || _journal != null) {
      unawaited(journal.retire());
      throw StateError('Protected shared journal owner changed');
    }
    _journal = journal;
  }

  final bool Function() isCurrentScope;
  final void Function(ProtectedComplexOwner) onDrained;
  OwnedPreviewController preview = OwnedPreviewController();
  final _childPreviews = <OwnedPreviewController>{};
  void registerPreview(OwnedPreviewController value) {
    if (!current) {
      value.dispose();
      throw StateError('Protected shared retired');
    }
    _childPreviews.add(value);
  }

  void unregisterPreview(OwnedPreviewController value) =>
      _childPreviews.remove(value);
  ProtectedSharedMemoryStore? _memory;
  Future<void> Function()? _closeRoute;
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

  bool get retired => _closing || _closed;
  void bindMemory(ProtectedSharedMemoryStore memory) {
    if (!current || !identical(memory.journal, _journal)) {
      memory.close();
      throw StateError('Protected shared retired');
    }
    _memory?.close();
    _memory = memory;
  }

  Future<void> Function()? get routeCloser => _closeRoute;
  void bindRoute(Future<void> Function()? close) {
    if (!current) throw StateError('Protected shared retired');
    _closeRoute = close;
  }

  Future<void> nextPreview() async {
    await preview.retire();
    if (!current) throw StateError('Protected shared retired');
    preview.dispose();
    preview = OwnedPreviewController();
  }

  @override
  Future<void> retire() {
    _closing = true;
    transport.close(); // Revoke synchronously, before any await.
    final storage = _journal?.retire() ?? Future<void>.value();
    final previous = _retiring;
    if (previous != null) return previous;
    final work = _close(storage);
    _retiring = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_retiring, work)) _retiring = null;
      }),
    );
    return work;
  }

  Future<void> _close(Future<void> storage) async {
    final route = _closeRoute;
    if (route != null) await route();
    if (identical(_closeRoute, route)) _closeRoute = null;
    await preview.retire();
    for (final value in _childPreviews.toList()) {
      await value.retire();
    }
    _memory?.close();
    _memory = null;
    await storage;
    _closed = true;
    if (!_reported) {
      _reported = true;
      onDrained(this);
    }
  }
}
