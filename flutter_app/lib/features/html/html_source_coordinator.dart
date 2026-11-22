import 'dart:async';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';

/// Page-level coordinator for replacing HtmlNotePage's source editor
/// body with ComplexEditorBrowser.
///
/// Integration prerequisite: add nullable `ComplexEditorTransport.generation`
/// backed by the loaded ready receipt. ComplexEditorBrowser.onReady runs after
/// transport.load and before browser _ready becomes true; this coordinator's
/// bind call therefore receives that immutable load generation explicitly.
///
/// The Flutter page must cancel its stale draft timer synchronously before
/// calling save(), suppress its old c.flushRecovery timer while source mode is
/// mounted, and use [seed] unchanged as ComplexEditorBrowser.document for the
/// lifetime of this generation.
class HtmlSourceCoordinator {
  HtmlSourceCoordinator(this.controller, {required this.freezeEdit});

  final HtmlEditorController controller;

  /// Reads the current title and labels synchronously at the post-capture
  /// freeze boundary, and returns an edit whose source is [capturedSource].
  final HtmlNoteEdit Function(String capturedSource) freezeEdit;

  ComplexEditorTransport? _transport;
  ComplexEditorDocument? _seed;
  int? _generation;
  int _epoch = 0;
  Future<void> _tail = Future<void>.value();
  Future<HtmlSaveOutcome?>? _saveFuture;
  bool _accepting = false;
  bool _saveBarrier = false;
  bool _retiring = false;
  bool _closed = false;
  bool _locked = true;
  int? _lastCheckpointRevision;
  Object? failure;
  Object? retirementFailure;
  ComplexEditorState? state;

  ComplexEditorDocument? get seed => _seed;
  int? get generation => _generation;
  bool get ready =>
      !_closed &&
      _accepting &&
      _transport != null &&
      _generation != null &&
      _transport!.generation == _generation;
  bool get busy => _saveBarrier || _retiring;
  bool get inputLocked => _locked;
  int? get lastCheckpointRevision => _lastCheckpointRevision;

  /// Call before constructing a keyed ComplexEditorBrowser. The returned
  /// document is immutable for this mounted generation; c.edit/checkpoint/save
  /// never replace it. Explicit reload calls this again from the reviewed
  /// controller draft and mounts a new key.
  ComplexEditorDocument beginGeneration() {
    if (_closed) throw StateError('Coordinator is disposed');
    if (_transport != null) {
      throw StateError('Retire the current source generation first');
    }
    _epoch++;
    _accepting = true;
    _saveBarrier = false;
    _retiring = false;
    state = null;
    _generation = null;
    _lastCheckpointRevision = null;
    _locked = true;
    failure = null;
    retirementFailure = null;
    _seed = ComplexEditorDocument.parse(
      ComplexEditorKind.html,
      controller.draft.source,
    );
    return _seed!;
  }

  /// Called from ComplexEditorBrowser.onReady after the validated host load
  /// receipt. The page supplies transport.generation, never guesses it from a
  /// state event (which may race the browser ready flag).
  Future<void> bind(
    ComplexEditorTransport transport, {
    required int generation,
  }) async {
    if (!_accepting ||
        _closed ||
        _seed == null ||
        generation < 1 ||
        transport.generation != generation) {
      throw StateError('HTML source generation receipt is unavailable');
    }
    if (_transport != null && !identical(_transport, transport)) {
      throw StateError('Another source transport is already bound');
    }
    _transport = transport;
    _generation = generation;
    final shouldLock = !controller.canEdit || controller.hasPendingOperation;
    if (shouldLock) {
      await transport.setInputLocked(true);
    }
    _locked = shouldLock;
    // Browser onReady is invoked before its _ready flag becomes true, and the
    // final load state may have been ignored. Initialize from the validated
    // transport load/lock receipts rather than waiting for the first dirty
    // event to enable save.
    state = ComplexEditorState(
      generation: generation,
      revision: 0,
      ready: true,
      dirty: false,
      inputLocked: shouldLock,
    );
  }

  /// Rejects state from stale platform-view identities or a previous load.
  /// onState can arrive before page code has otherwise scheduled a checkpoint.
  bool onState(ComplexEditorTransport transport, ComplexEditorState value) {
    if (!_matches(transport, _epoch, _generation) ||
        value.generation != _generation ||
        !value.ready) {
      return false;
    }
    state = value;
    _locked = value.inputLocked;
    return true;
  }

  bool _matches(
    ComplexEditorTransport transport,
    int epoch,
    int? generation, {
    bool allowRetiring = false,
  }) =>
      !_closed &&
      epoch == _epoch &&
      generation != null &&
      identical(_transport, transport) &&
      _generation == generation &&
      (_accepting || (allowRetiring && _retiring));

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then<T>((_) => work());
    // Keep the queue usable, while preserving the original error for the
    // caller waiting on [result]. Never turn a failed page operation into
    // success or silently bypass its durability gate.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Serial metadata edits share the capture/save queue. The caller should
  /// disable title/label controls while [busy] is true. A later capture
  /// replaces the provisional stale source in controller.draft before flush.
  Future<void> updateMetadata({
    required String title,
    required List<String> labels,
  }) {
    final transport = _transport;
    final epoch = _epoch;
    final generation = _generation;
    if (transport == null ||
        !_accepting ||
        _saveBarrier ||
        _retiring ||
        generation == null ||
        !controller.canEdit ||
        controller.hasPendingOperation) {
      throw StateError('HTML metadata editing is unavailable');
    }
    final frozenLabels = List<String>.unmodifiable(labels);
    return _enqueue(() async {
      if (!_matches(transport, epoch, generation) ||
          controller.hasPendingOperation ||
          !controller.canEdit) {
        throw StateError('HTML metadata edit belongs to a stale source');
      }
      controller.edit(
        HtmlNoteEdit(
          title: title,
          source: controller.draft.source,
          labels: frozenLabels,
        ),
      );
    });
  }

  /// Ordinary checkpoint is a transition durability gate. A false result
  /// means stay on this page and retain the lease; caller may retry or call
  /// unlock() to let the user continue editing. keepLocked leaves the source
  /// frozen for a confirmation sheet/transition until explicit unlock.
  Future<bool> checkpoint({bool keepLocked = false}) {
    final transport = _transport;
    final epoch = _epoch;
    final generation = _generation;
    if (transport == null ||
        !_accepting ||
        _saveBarrier ||
        _retiring ||
        generation == null) {
      return Future<bool>.value(false);
    }
    return _enqueue(() async {
      if (_saveBarrier || !_matches(transport, epoch, generation)) {
        return false;
      }
      if (controller.hasPendingOperation || !controller.canEdit) {
        final stored = await controller.flushRecovery();
        if (!stored) {
          failure =
              controller.recoveryFailure ??
              StateError('Pending journal flush failed');
        }
        _locked = true;
        return stored;
      }
      return _captureAndCheckpoint(
        transport,
        epoch,
        generation,
        keepLocked: keepLocked,
      );
    });
  }

  Future<bool> _captureAndCheckpoint(
    ComplexEditorTransport transport,
    int epoch,
    int generation, {
    required bool keepLocked,
    bool forced = false,
  }) async {
    ComplexEditorSnapshot? snapshot;
    var stored = false;
    try {
      await transport.setInputLocked(true);
      _locked = true;
      if (!_matches(transport, epoch, generation, allowRetiring: forced) ||
          (!forced && _saveBarrier) ||
          !controller.canEdit ||
          controller.hasPendingOperation) {
        return false;
      }
      snapshot = await transport.capture();
      if (!_matches(transport, epoch, generation, allowRetiring: forced) ||
          snapshot.generation != generation ||
          (!forced && _saveBarrier) ||
          !controller.canEdit ||
          controller.hasPendingOperation) {
        return false;
      }
      final frozen = freezeEdit(snapshot.document.source);
      controller.edit(frozen);
      stored = await controller.flushRecovery();
      if (!stored) {
        failure =
            controller.recoveryFailure ?? StateError('Recovery flush failed');
        return false;
      }
      if (!_matches(transport, epoch, generation, allowRetiring: forced) ||
          snapshot.generation != generation) {
        return false;
      }
      _lastCheckpointRevision = snapshot.revision;
      failure = null;
      return true;
    } catch (error) {
      failure = error;
      return false;
    } finally {
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (error) {
          failure ??= error;
        }
      }
      final shouldUnlock =
          !keepLocked &&
          !forced &&
          !_saveBarrier &&
          !_retiring &&
          _matches(transport, epoch, generation) &&
          controller.canEdit &&
          !controller.hasPendingOperation;
      if (shouldUnlock) {
        try {
          await transport.setInputLocked(false);
          _locked = false;
        } catch (error) {
          failure ??= error;
        }
      }
    }
  }

  Future<void> unlock() => _enqueue(() async {
    final transport = _transport;
    final generation = _generation;
    final epoch = _epoch;
    if (transport == null ||
        generation == null ||
        !_matches(transport, epoch, generation) ||
        _saveBarrier ||
        _retiring ||
        !controller.canEdit ||
        controller.hasPendingOperation) {
      throw StateError('HTML source cannot be unlocked');
    }
    await transport.setInputLocked(false);
    _locked = false;
  });

  /// The page owner must cancel its source checkpoint timer synchronously
  /// before calling save(). This method raises its barrier immediately before
  /// waiting on prior queued work, preventing an older queued body checkpoint
  /// from landing after the controller's durable pending record.
  /// The browser page should expose one shared future to toolbar and host
  /// onSaveRequested so they coalesce into this method.
  Future<HtmlSaveOutcome?> save() {
    final active = _saveFuture;
    if (active != null) return active;
    final transport = _transport;
    final epoch = _epoch;
    final generation = _generation;
    if (transport == null ||
        generation == null ||
        !_accepting ||
        _retiring ||
        !controller.canEdit ||
        controller.hasPendingOperation) {
      return Future<HtmlSaveOutcome?>.value(null);
    }
    _saveBarrier = true;
    final work = _enqueue(() => _saveSerial(transport, epoch, generation));
    late final Future<HtmlSaveOutcome?> shared;
    shared = work.whenComplete(() {
      if (identical(_saveFuture, shared)) _saveFuture = null;
      _saveBarrier = false;
    });
    _saveFuture = shared;
    return shared;
  }

  Future<HtmlSaveOutcome?> _saveSerial(
    ComplexEditorTransport transport,
    int epoch,
    int generation,
  ) async {
    ComplexEditorSnapshot? snapshot;
    var acknowledged = false;
    var allowUnlock = false;
    HtmlSaveOutcome? repositoryOutcome;
    try {
      if (!_matches(transport, epoch, generation) ||
          !controller.canEdit ||
          controller.hasPendingOperation) {
        return null;
      }
      await transport.setInputLocked(true);
      _locked = true;
      snapshot = await transport.capture();
      if (!_matches(transport, epoch, generation) ||
          snapshot.generation != generation ||
          !controller.canEdit ||
          controller.hasPendingOperation) {
        return null;
      }
      final frozen = freezeEdit(snapshot.document.source);
      controller.edit(frozen);
      if (!controller.canSave) {
        // A no-op snapshot is not a commit receipt and must never be acked.
        // It may, however, have returned the controller to baseline after an
        // earlier checkpoint wrote an ordinary draft; flush that removal.
        final flushed = await controller.flushRecovery();
        if (!flushed) {
          failure =
              controller.recoveryFailure ??
              StateError('No-op recovery cleanup failed');
        } else {
          failure = null;
        }
        allowUnlock = controller.canEdit && !controller.hasPendingOperation;
        return null;
      }
      final outcome = await controller.saveWithOutcome();
      repositoryOutcome = outcome;
      if (outcome == null) {
        // Validation or pre-mutation durability may fail without creating an
        // unresolved transaction. Persist the now-frozen editable draft if
        // possible, surface storage failure, and unlock only this safe case.
        if (controller.canEdit && !controller.hasPendingOperation) {
          final stored = await controller.flushRecovery();
          failure = stored
              ? controller.failure
              : controller.recoveryFailure ??
                    controller.failure ??
                    StateError('Editable draft flush failed');
          allowUnlock = true;
        }
        return null;
      }
      if (!_matches(transport, epoch, generation) ||
          snapshot.generation != generation ||
          !outcome.allReceiptsKnown ||
          !frozen.matches(outcome.note)) {
        return outcome;
      }
      final committed = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        outcome.note.source,
      );
      if (!snapshot.document.same(committed)) return outcome;
      await transport.acknowledgeSaved(snapshot, committed: committed);
      acknowledged = true;
      allowUnlock = controller.canEdit && !controller.hasPendingOperation;
      _lastCheckpointRevision = snapshot.revision;
      failure = controller.recoveryFailure;
      return outcome;
    } catch (error) {
      failure = error;
      // A real repository receipt survives a later acknowledgement or cleanup
      // failure. The caller must surface reload/ack-retry state, never resave.
      return repositoryOutcome;
    } finally {
      if (snapshot != null && !acknowledged) {
        try {
          await transport.release(snapshot);
        } catch (error) {
          failure ??= error;
        }
      }
      if (allowUnlock &&
          !_retiring &&
          _matches(transport, epoch, generation) &&
          controller.canEdit &&
          !controller.hasPendingOperation) {
        try {
          await transport.setInputLocked(false);
          _locked = false;
        } catch (error) {
          failure ??= error;
        }
      }
    }
  }

  /// Forced lease retirement is intentionally non-vetoable. It waits behind
  /// current page work, best-effort captures when the controller is editable,
  /// skips source capture for unresolved/unknown saves, records failures, and
  /// returns normally so ComplexEditorBrowser can always retire the transport.
  Future<void> beforeRetire(ComplexEditorTransport transport) async {
    if (!identical(_transport, transport)) return;
    final epoch = _epoch;
    final generation = _generation;
    _accepting = false;
    _retiring = true;
    _saveBarrier = true;
    try {
      await _enqueue(() async {
        if (generation == null ||
            !_matches(transport, epoch, generation, allowRetiring: true)) {
          return;
        }
        if (controller.hasPendingOperation || !controller.canEdit) {
          if (!await controller.flushRecovery()) {
            retirementFailure =
                controller.recoveryFailure ??
                StateError('Pending journal flush failed');
          }
          return;
        }
        final captured = await _captureAndCheckpoint(
          transport,
          epoch,
          generation,
          keepLocked: true,
          forced: true,
        );
        if (!captured) {
          retirementFailure = failure ?? StateError('Forced checkpoint failed');
        }
      });
    } catch (error) {
      retirementFailure = error;
      try {
        await controller.flushRecovery();
      } catch (_) {
        // Forced retirement remains non-vetoable.
      }
    } finally {
      _transport = null;
      _generation = null;
      state = null;
      _epoch++;
      _retiring = false;
      _saveBarrier = false;
      _locked = true;
    }
  }

  /// Abandon owner callbacks immediately on dispose/reload. The browser remains
  /// responsible for invoking beforeRetire before it retires the platform
  /// lease. Never use this to authorize a stale capture into recovery.
  void invalidate() {
    _accepting = false;
    _epoch++;
    _transport = null;
    _generation = null;
    state = null;
    _locked = true;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _accepting = false;
    _epoch++;
    _transport = null;
    _generation = null;
    state = null;
    // The route/widget owns HtmlEditorController lifecycle in this draft.
    // Wait for queued work to settle before its caller disposes the controller.
    try {
      await _tail;
    } catch (_) {
      /* The actual operation future already reported its failure. */
    }
  }
}
