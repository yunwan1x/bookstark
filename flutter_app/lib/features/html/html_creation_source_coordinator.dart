import 'dart:async';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';

/// Draft creation-page coordinator: capture ordering only; controllers own the
/// durable create transaction. [create] must never call an existing-ID save.
class HtmlCreationSourceCoordinator {
  HtmlCreationSourceCoordinator({
    required this.freezeEdit,
    required this.applyCapturedEdit,
    required this.flushCreationJournal,
    required this.create,
    required this.creationStillEditable,
    required this.pendingOrUnknown,
  });
  final HtmlNoteEdit Function(String source) freezeEdit;
  final void Function(HtmlNoteEdit edit) applyCapturedEdit;
  final Future<bool> Function() flushCreationJournal;
  final Future<void> Function() create;
  final bool Function() creationStillEditable, pendingOrUnknown;

  ComplexEditorTransport? _transport;
  ComplexEditorDocument? _seed;
  int? _generation;
  int _epoch = 0;
  Future<void> _tail = Future<void>.value();
  bool _accepting = false, _barrier = false, _retiring = false, _closed = false;
  ComplexEditorState? state;
  int? lastCheckpointRevision;
  Object? failure;

  bool get ready =>
      !_closed &&
      !_retiring &&
      _accepting &&
      _transport != null &&
      _generation != null &&
      _transport!.generation == _generation;
  bool get busy => _barrier || _retiring;
  ComplexEditorDocument? get seed => _seed;
  int? get generation => _generation;
  int get epoch => _epoch;
  bool isCurrentEpoch(int epoch) =>
      !_closed && _accepting && !_retiring && epoch == _epoch;
  ComplexEditorTransport? get transport => _transport;

  ComplexEditorDocument beginGeneration(String source) {
    if (_closed || _transport != null) {
      throw StateError('Retire current source first');
    }
    _epoch++;
    _accepting = true;
    _retiring = false;
    _generation = null;
    state = null;
    lastCheckpointRevision = null;
    failure = null;
    _seed = ComplexEditorDocument.parse(ComplexEditorKind.html, source);
    return _seed!;
  }

  Future<void> bind(
    ComplexEditorTransport transport, {
    required int generation,
  }) async {
    if (_closed ||
        !_accepting ||
        _seed == null ||
        generation < 1 ||
        transport.generation != generation ||
        (_transport != null && !identical(_transport, transport))) {
      throw StateError('HTML creation source generation mismatch');
    }
    _transport = transport;
    _generation = generation;
    if (pendingOrUnknown() || !creationStillEditable()) {
      await transport.setInputLocked(true);
    }
    state = ComplexEditorState(
      generation: generation,
      revision: 0,
      ready: true,
      dirty: false,
      inputLocked: pendingOrUnknown() || !creationStillEditable(),
    );
  }

  bool onState(ComplexEditorTransport transport, ComplexEditorState value) {
    if (!ready ||
        !identical(transport, _transport) ||
        value.generation != _generation ||
        !value.ready) {
      return false;
    }
    state = value;
    return true;
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then<T>((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _matches(
    ComplexEditorTransport transport,
    int epoch,
    int generation, {
    bool allowRetiring = false,
  }) =>
      !_closed &&
      (_accepting || (allowRetiring && _retiring)) &&
      (!_retiring || allowRetiring) &&
      epoch == _epoch &&
      identical(_transport, transport) &&
      _generation == generation &&
      transport.generation == generation;

  Future<bool> _captureAndPersist({
    required bool keepLocked,
    bool barrierOwned = false,
  }) {
    final transport = _transport, generation = _generation, epoch = _epoch;
    if (transport == null ||
        generation == null ||
        !ready ||
        !creationStillEditable() ||
        pendingOrUnknown()) {
      return Future.value(false);
    }
    final frozenMetadata = freezeEdit('');
    if (!barrierOwned) _barrier = true;
    final result = _enqueue(() async {
      ComplexEditorSnapshot? snapshot;
      var success = false;
      try {
        if (!_matches(transport, epoch, generation)) {
          failure = StateError('HTML source generation retired');
        } else {
          await transport.setInputLocked(true);
          snapshot = await transport.capture();
          if (!_matches(transport, epoch, generation) ||
              snapshot.generation != generation) {
            failure = StateError('HTML source generation changed');
          } else {
            final capturedRevision = snapshot.revision;
            applyCapturedEdit(
              HtmlNoteEdit(
                title: frozenMetadata.title,
                source: snapshot.document.source,
                labels: List<String>.unmodifiable(frozenMetadata.labels),
              ),
            );
            await transport.release(snapshot);
            snapshot = null;
            if (!_matches(transport, epoch, generation)) {
              failure = StateError('HTML source generation retired');
            } else if (!await flushCreationJournal()) {
              failure = StateError('Creation draft durability failed');
            } else {
              lastCheckpointRevision = capturedRevision;
              failure = null;
              success = true;
            }
          }
        }
      } catch (error) {
        failure = error;
      } finally {
        if (snapshot != null) {
          try {
            await transport.release(snapshot);
          } catch (error) {
            failure ??= error;
            success = false;
          }
        }
        if (_matches(transport, epoch, generation) &&
            creationStillEditable() &&
            !pendingOrUnknown()) {
          try {
            // Failed checkpoints must leave the source editable for correction
            // and retry. Only a successful submit/leave capture keeps it locked.
            await transport.setInputLocked(success && keepLocked);
          } catch (error) {
            failure ??= error;
            success = false;
          }
        }
      }
      return success;
    });
    return barrierOwned ? result : result.whenComplete(() => _barrier = false);
  }

  Future<bool> checkpoint() =>
      _barrier ? Future.value(false) : _captureAndPersist(keepLocked: false);

  /// Durably flush pending intent before invoking the page's create controller.
  Future<bool> submit() async {
    if (_barrier || !ready || !creationStillEditable() || pendingOrUnknown()) {
      return false;
    }
    _barrier = true;
    var completed = false;
    try {
      final durable = await _captureAndPersist(
        keepLocked: true,
        barrierOwned: true,
      );
      if (!durable || !ready || pendingOrUnknown()) return false;
      await create();
      completed = true;
    } catch (error) {
      failure = error;
    } finally {
      _barrier = false;
      if (ready && creationStillEditable() && !pendingOrUnknown()) {
        final transport = _transport!;
        try {
          await transport.setInputLocked(false);
        } catch (error) {
          failure = error;
          completed = false;
        }
      }
    }
    return completed;
  }

  Future<bool> prepareLeave() => _captureAndPersist(keepLocked: true);

  Future<void> unlock() async {
    final transport = _transport, generation = _generation, epoch = _epoch;
    if (transport == null ||
        generation == null ||
        !_matches(transport, epoch, generation) ||
        !creationStillEditable() ||
        pendingOrUnknown()) {
      return;
    }
    await transport.setInputLocked(false);
  }

  /// Forced lifecycle close must not wait on durability and veto lease retirement.
  void invalidate() {
    _accepting = false;
    _retiring = false;
    _barrier = false;
    _epoch++;
    _generation = null;
    _transport = null;
  }

  Future<void> beforeForcedRetire(ComplexEditorTransport transport) async {
    if (!identical(_transport, transport) || _closed || _retiring) return;
    final generation = _generation, epoch = _epoch;
    if (generation == null) return;
    final frozenMetadata = freezeEdit('');
    _accepting = false;
    _retiring = true;
    _barrier = true;
    try {
      await _enqueue(() async {
        if (!_matches(transport, epoch, generation, allowRetiring: true)) {
          return;
        }
        if (pendingOrUnknown()) {
          unawaited(_flushRetirementDraft(epoch, transport, generation));
          return;
        }
        if (!creationStillEditable()) return;
        ComplexEditorSnapshot? snapshot;
        try {
          await transport.setInputLocked(true);
          snapshot = await transport.capture();
          if (!_matches(transport, epoch, generation, allowRetiring: true) ||
              snapshot.generation != generation ||
              pendingOrUnknown() ||
              !creationStillEditable()) {
            failure = StateError('HTML creation changed during retirement');
            return;
          }
          final capturedRevision = snapshot.revision;
          applyCapturedEdit(
            HtmlNoteEdit(
              title: frozenMetadata.title,
              source: snapshot.document.source,
              labels: List<String>.unmodifiable(frozenMetadata.labels),
            ),
          );
          await transport.release(snapshot);
          snapshot = null;
          lastCheckpointRevision = capturedRevision;
          unawaited(_flushRetirementDraft(epoch, transport, generation));
        } catch (error) {
          failure = error;
          unawaited(_flushRetirementDraft(epoch, transport, generation));
        } finally {
          if (snapshot != null) {
            try {
              await transport.release(snapshot);
            } catch (error) {
              failure ??= error;
            }
          }
        }
      });
    } catch (error) {
      failure = error;
      unawaited(_flushRetirementDraft(epoch, transport, generation));
    } finally {
      if (identical(_transport, transport) && _epoch == epoch) invalidate();
    }
  }

  Future<void> _flushRetirementDraft(
    int epoch,
    ComplexEditorTransport transport,
    int generation,
  ) async {
    if (!_matches(transport, epoch, generation, allowRetiring: true)) return;
    try {
      final flushed = await flushCreationJournal();
      if (_matches(transport, epoch, generation, allowRetiring: true) &&
          !flushed) {
        failure = StateError('Creation draft durability failed');
      }
    } catch (error) {
      if (_matches(transport, epoch, generation, allowRetiring: true)) {
        failure = error;
      }
    }
  }

  Future<void> drain() async {
    try {
      await _tail;
    } catch (_) {}
  }

  Future<void> dispose() async {
    _closed = true;
    _accepting = false;
    _epoch++;
    _seed = null;
    await drain();
  }
}
