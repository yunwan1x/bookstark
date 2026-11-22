import 'dart:async';

import 'package:flutter/foundation.dart';

import 'complex_editor_transport.dart';
import 'public_edit_controller.dart';
import 'public_edit_snapshot.dart';

final class SharedMarkdownInsertion {
  SharedMarkdownInsertion._(this._transport, this._snapshot);
  final ComplexEditorTransport _transport;
  final ComplexEditorSnapshot _snapshot;
}

/// RAM-only working copy for a single capability-checked shared editor.
/// The renderer receives source, never the editing capability or password.
class SharedMarkdownSession extends ChangeNotifier {
  SharedMarkdownSession(this.controller)
    : body = controller.snapshot?.content ?? '';
  final PublicEditController controller;
  String body;
  bool paused = false, captureFailed = false, busy = false;
  bool _disposed = false;
  bool _discardConfirmed = false;
  ComplexEditorTransport? _failedRetirement;
  ComplexEditorTransport? _transport;
  SharedMarkdownInsertion? _insertion;
  Future<void> _tail = Future<void>.value();

  bool get canEdit =>
      !_disposed &&
      _transport != null &&
      !paused &&
      !captureFailed &&
      _insertion == null &&
      {
        PublicEditPhase.ready,
        PublicEditPhase.acknowledged,
      }.contains(controller.phase);
  bool get canRecapture => _transport != null && !paused && _insertion == null;
  bool get dirty => body != controller.snapshot?.content;

  Future<T> _serial<T>(
    Future<T> Function() operation, {
    Future<T> Function()? whenDisposed,
  }) {
    final result = _tail.then((_) async {
      if (_disposed) {
        if (whenDisposed != null) return await whenDisposed();
        throw StateError('Shared editor session ended');
      }
      busy = true;
      notifyListeners();
      try {
        return await operation();
      } finally {
        busy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _checkOwner() {
    if (_disposed) throw StateError('Shared editor session ended');
  }

  Future<void> attach(ComplexEditorTransport transport) => _serial(() async {
    if (paused || _transport != null) {
      throw StateError('Shared editor must be revalidated before attachment');
    }
    _transport = transport;
    await transport.setInputLocked(!canEdit);
  });

  Future<void> _capture(ComplexEditorTransport transport) async {
    final snapshot = await transport.capture();
    try {
      // A disposed RAM owner must never be revived by a late snapshot.
      if (_disposed) return;
      body = snapshot.document.source;
      captureFailed = false;
    } finally {
      await transport.release(snapshot);
    }
  }

  Future<void> capture() => _serial(() async {
    final transport = _transport;
    if (transport == null) {
      if (captureFailed) throw StateError('Latest working copy unavailable');
      return;
    }
    await transport.setInputLocked(true);
    try {
      await _capture(transport);
    } catch (_) {
      captureFailed = true;
      rethrow;
    } finally {
      if (canEdit) await transport.setInputLocked(false);
    }
  });

  Future<void> save({PublicEditSnapshot? observed}) => _serial(() async {
    final transport = _transport;
    if (transport == null || paused || captureFailed || _insertion != null) {
      throw StateError('No active shared editor');
    }
    await transport.setInputLocked(true);
    ComplexEditorSnapshot? frozen;
    var released = false;
    try {
      frozen = await transport.capture();
      _checkOwner();
      body = frozen.document.source;
      await controller.save(body, overwriteObserved: observed);
      _checkOwner();
      if (controller.phase == PublicEditPhase.acknowledged &&
          controller.snapshot?.content == body) {
        await transport.acknowledgeSaved(frozen, committed: frozen.document);
        released = true;
      }
    } catch (_) {
      if (frozen == null) captureFailed = true;
      rethrow;
    } finally {
      if (frozen != null && !released) await transport.release(frozen);
      if (canEdit) await transport.setInputLocked(false);
    }
  });

  Future<SharedMarkdownInsertion> beginInsertion() => _serial(() async {
    final transport = _transport;
    if (transport == null || !canEdit) {
      throw StateError('Attachment requires an active editable source');
    }
    await transport.setInputLocked(true);
    try {
      final snapshot = await transport.capture();
      if (_disposed) {
        await transport.release(snapshot);
        _checkOwner();
      }
      body = snapshot.document.source;
      return _insertion = SharedMarkdownInsertion._(transport, snapshot);
    } catch (_) {
      captureFailed = true;
      rethrow;
    }
  });

  /// The picker/upload happens outside this queue: background retirement must
  /// not wait for an Android picker to return. A late result remains copyable
  /// in the Flutter owner and cannot enter another runtime.
  Future<void> finishInsertion(
    SharedMarkdownInsertion insertion,
    String? markdown,
  ) => _serial(() async {
    if (!identical(_insertion, insertion)) {
      throw StateError('Attachment source has changed');
    }
    final transport = insertion._transport;
    var consumed = false, attempted = false;
    final active = identical(_transport, transport) && !paused;
    try {
      if (markdown == null) return;
      if (!active ||
          captureFailed ||
          !{
            PublicEditPhase.ready,
            PublicEditPhase.acknowledged,
          }.contains(controller.phase)) {
        throw StateError('Attachment source is no longer active');
      }
      await controller.revalidateForResume(body);
      _checkOwner();
      if (controller.phase == PublicEditPhase.conflict) {
        throw StateError('Remote content changed during attachment selection');
      }
      attempted = true;
      await transport.insertMarkdown(insertion._snapshot, text: markdown);
      consumed = true;
      await _capture(transport);
    } catch (_) {
      if (attempted) captureFailed = true;
      rethrow;
    } finally {
      _insertion = null;
      if (active && !consumed) await transport.release(insertion._snapshot);
      if (active && canEdit) await transport.setInputLocked(false);
    }
  });

  Future<void> verify() => _serial(() async {
    await controller.verify();
    _checkOwner();
    final transport = _transport;
    if (transport == null) return;
    await transport.setInputLocked(true);
    ComplexEditorSnapshot? frozen;
    var consumed = false;
    try {
      frozen = await transport.capture();
      _checkOwner();
      body = frozen.document.source;
      captureFailed = false;
      // A GET confirms the attempted body, not necessarily late input still
      // present in the renderer. Acknowledge only an exact fresh snapshot.
      if (controller.phase == PublicEditPhase.acknowledged &&
          controller.snapshot?.content == body) {
        await transport.acknowledgeSaved(frozen, committed: frozen.document);
        consumed = true;
      }
    } catch (_) {
      captureFailed = true;
      rethrow;
    } finally {
      if (frozen != null && !consumed) await transport.release(frozen);
      if (canEdit) await transport.setInputLocked(false);
    }
  });

  /// Called by the browser before its transport is retired. It joins any
  /// running save first, then captures the newest readable source.
  Future<void> beforeRetire(ComplexEditorTransport transport) =>
      _serial(() async {
        if (_discardConfirmed) {
          paused = true;
          _transport = null;
          _insertion = null;
          return;
        }
        if (identical(_failedRetirement, transport)) {
          throw StateError('Final capture failed; explicit discard required');
        }
        if (!identical(_transport, transport)) return;
        paused = true;
        try {
          await transport.setInputLocked(true);
          await _capture(transport);
        } catch (_) {
          captureFailed = true;
          _failedRetirement = transport;
          rethrow;
        } finally {
          _transport = null;
        }
      }, whenDisposed: () async {});

  /// Only the existing explicit leave/lost-capture confirmation calls this.
  /// It permits retirement, never another capture, edit or server write.
  void acknowledgeDiscardForExit() {
    if (_disposed || busy || !captureFailed) {
      throw StateError('No captured failure awaiting explicit discard');
    }
    _discardConfirmed = true;
    paused = true;
  }

  Future<void> adoptRemoteWhilePaused() => _serial(() async {
    if (!paused ||
        _transport != null ||
        controller.phase != PublicEditPhase.conflict) {
      throw StateError('Retire the old source before adopting remote content');
    }
    controller.acceptRemote();
    body = controller.snapshot!.content;
    captureFailed = false;
  });

  Future<void> overwriteRetained(PublicEditSnapshot observed) =>
      _serial(() async {
        if (!paused ||
            _transport != null ||
            captureFailed ||
            controller.phase != PublicEditPhase.conflict) {
          throw StateError('No retained conflict source to overwrite');
        }
        await controller.save(body, overwriteObserved: observed);
      });

  Future<void> resume() => _serial(() async {
    if (!paused || _transport != null || captureFailed) {
      throw StateError('Shared editor cannot resume');
    }
    await controller.revalidateForResume(body);
    if (controller.phase == PublicEditPhase.ready ||
        controller.phase == PublicEditPhase.acknowledged) {
      paused = false;
    }
  });

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _transport = null;
    _insertion = null;
    body = '';
    super.dispose();
  }
}
