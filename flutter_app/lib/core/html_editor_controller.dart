import 'package:flutter/foundation.dart';
import 'html_notes_repository.dart';
import 'html_recovery_vault.dart';

enum HtmlEditorPhase {
  clean,
  editing,
  saving,
  conflict,
  contentUnknown,
  labelsPending,
  verificationPending,
  saved,
  observed,
}

/// Existing-note edit transaction. Unknown/partial writes can only be resolved
/// through explicit reads or label-only recovery; never by automatic resubmit.
class HtmlEditorController extends ChangeNotifier {
  HtmlEditorController(
    this.repository,
    HtmlNote initial, {
    this.recovery,
    bool observed = false,
  }) : _baseline = initial,
       _draft = HtmlNoteEdit(
         title: initial.metadata.title,
         source: initial.source,
         labels: initial.labels,
       ),
       _everProtected = initial.metadata.protected {
    if (observed) _phase = HtmlEditorPhase.observed;
  }
  factory HtmlEditorController.restore(
    HtmlNotesRepository repository,
    HtmlNote current,
    HtmlRecoveryRecord record, {
    HtmlRecoveryVault? recovery,
  }) {
    final baseline = record.baseline, draft = record.edit;
    if (baseline == null ||
        draft == null ||
        record.id != current.metadata.id ||
        record.memberId != current.metadata.memberId ||
        record.collection != current.metadata.collection) {
      throw const FormatException(
        'HTML recovery requires matching owned draft',
      );
    }
    final restored = HtmlNote(
      metadata: baseline.metadata,
      source: baseline.source,
      labels: baseline.labels,
      unlockPassword: current.unlockPassword,
    );
    final controller = HtmlEditorController(
      repository,
      restored,
      recovery: recovery,
    );
    controller._draft = draft;
    controller._everProtected |= current.metadata.protected;
    if (record.pending) {
      // Never infer acknowledgements from a previous process. Explicit verify
      // is read-only; only observed content may subsequently resume labels.
      controller._attempt = HtmlSaveAttempt(baseline: restored, edit: draft);
      controller._phase = HtmlEditorPhase.contentUnknown;
      controller._latest = current;
    } else if (!baseline.metadata.same(current.metadata) ||
        htmlNoteFingerprint(baseline) != htmlNoteFingerprint(current)) {
      controller._latest = current;
      controller._phase = HtmlEditorPhase.conflict;
    } else {
      controller._phase = draft.matches(current)
          ? HtmlEditorPhase.clean
          : HtmlEditorPhase.editing;
    }
    return controller;
  }
  final HtmlRecoveryVault? recovery;
  Object? recoveryFailure;
  int _recoveryGeneration = 0;

  Future<void> _persistPending(HtmlSaveAttempt pending) async {
    final vault = recovery;
    if (vault == null) return;
    await vault.write(
      HtmlRecoveryRecord.capture(
        pending.baseline,
        pending.edit,
        pending: true,
        everProtected: _everProtected,
      ),
    );
  }

  /// Called by page debounce, before leaving, and after state transitions. The
  /// vault orders writes across page lifetimes; callers must not bypass errors.
  Future<bool> flushRecovery() async {
    final vault = recovery;
    if (vault == null || _closed) return true;
    final generation = ++_recoveryGeneration;
    try {
      if ({
        HtmlEditorPhase.clean,
        HtmlEditorPhase.saved,
        HtmlEditorPhase.observed,
      }.contains(_phase)) {
        await vault.remove(_baseline.metadata.id);
      } else if (_phase == HtmlEditorPhase.conflict && _attempt != null) {
        await _persistPending(_attempt!);
      } else if ({
        HtmlEditorPhase.editing,
        HtmlEditorPhase.conflict,
      }.contains(_phase)) {
        if (canPersistDraft) {
          await vault.write(
            HtmlRecoveryRecord.capture(_baseline, _draft, pending: false),
          );
        } else {
          await vault.remove(_baseline.metadata.id);
        }
      } else {
        final pending = _attempt;
        if (pending != null) await _persistPending(pending);
      }
      if (generation == _recoveryGeneration) recoveryFailure = null;
      return true;
    } catch (error) {
      if (generation == _recoveryGeneration) recoveryFailure = error;
      return false;
    }
  }

  Future<bool> discardRecovery() async {
    if (_busy ||
        hasPendingOperation ||
        {
          HtmlEditorPhase.contentUnknown,
          HtmlEditorPhase.labelsPending,
          HtmlEditorPhase.verificationPending,
          HtmlEditorPhase.saving,
        }.contains(_phase)) {
      throw StateError('Resolve pending HTML operation before discard');
    }
    final vault = recovery;
    if (vault == null) return true;
    try {
      await vault.remove(_baseline.metadata.id);
      recoveryFailure = null;
      return true;
    } catch (error) {
      recoveryFailure = error;
      return false;
    }
  }

  final HtmlNotesRepository repository;
  HtmlNote _baseline;
  HtmlNoteEdit _draft;
  HtmlSaveAttempt? _attempt;
  HtmlNote? _latest;
  Object? failure;
  HtmlEditorPhase _phase = HtmlEditorPhase.clean;
  bool _closed = false, _busy = false, _everProtected;
  HtmlNote get baseline => _baseline;
  HtmlNoteEdit get draft => _draft;
  HtmlSaveAttempt? get attempt => _attempt;
  HtmlNote? get latest => _latest;
  HtmlEditorPhase get phase => _phase;
  bool get busy => _busy;
  bool get canEdit =>
      !_closed &&
      !_busy &&
      {
        HtmlEditorPhase.clean,
        HtmlEditorPhase.editing,
        HtmlEditorPhase.saved,
        HtmlEditorPhase.observed,
      }.contains(_phase);
  bool get canSave => canEdit && _phase == HtmlEditorPhase.editing;
  bool get canPersistDraft => !_everProtected;
  bool get hasPendingOperation =>
      _phase == HtmlEditorPhase.saving ||
      _phase == HtmlEditorPhase.contentUnknown ||
      _phase == HtmlEditorPhase.labelsPending ||
      _phase == HtmlEditorPhase.verificationPending ||
      (_phase == HtmlEditorPhase.conflict && _attempt != null);

  void edit(HtmlNoteEdit value) {
    if (!canEdit) throw StateError('Resolve the existing HTML operation first');
    _draft = value;
    _attempt = null;
    _latest = null;
    failure = null;
    _phase = value.matches(_baseline)
        ? HtmlEditorPhase.clean
        : HtmlEditorPhase.editing;
    notifyListeners();
  }

  void _completed(HtmlSaveOutcome outcome) {
    _baseline = outcome.note;
    _attempt = outcome.attempt;
    _latest = null;
    _everProtected |= outcome.note.metadata.protected;
    _phase = outcome.allReceiptsKnown
        ? HtmlEditorPhase.saved
        : HtmlEditorPhase.observed;
    failure = null;
  }

  void _incomplete(HtmlSaveIncomplete value) {
    _attempt = value.attempt;
    _latest = value.observed;
    failure = value;
    if (value.observed != null) {
      _everProtected |= value.observed!.metadata.protected;
      _phase = HtmlEditorPhase.conflict;
    } else if (!value.attempt.contentReceipt &&
        !value.attempt.contentObserved) {
      _phase = HtmlEditorPhase.contentUnknown;
    } else if (value.attempt.requiresLabelWrite &&
        !value.attempt.labelsReceipt) {
      _phase = HtmlEditorPhase.labelsPending;
    } else {
      _phase = HtmlEditorPhase.verificationPending;
    }
  }

  /// Compatibility API for existing UI callers that only need completion.
  ///
  /// Callers that own an editor snapshot can use [saveWithOutcome] to receive
  /// the repository's actual response receipt.
  Future<void> save() async {
    await saveWithOutcome();
  }

  /// Saves the current draft and returns the exact repository outcome when the
  /// repository returned one. Recovery cleanup runs in finally and cannot
  /// erase a real commit receipt from this return value.
  Future<HtmlSaveOutcome?> saveWithOutcome() async {
    if (!canSave) throw StateError('HTML save is not available');
    try {
      _draft.validate(
        baseline: _baseline,
        labelsAsCsv: repository.labelsUseCsv,
      );
    } catch (error) {
      failure = error;
      notifyListeners();
      return null;
    }
    _busy = true;
    _phase = HtmlEditorPhase.saving;
    failure = null;
    notifyListeners();
    try {
      await _persistPending(HtmlSaveAttempt(baseline: _baseline, edit: _draft));
      if (_closed) return null;
      final outcome = await repository.save(_baseline, _draft);
      if (!_closed) _completed(outcome);
      // Preserve the actual repository receipt if disposal raced with the
      // completed request; do not mutate closed controller state.
      return outcome;
    } on HtmlNoteConflict catch (error) {
      if (_closed) return null;
      _latest = error.latest;
      _everProtected |= error.latest.metadata.protected;
      _phase = HtmlEditorPhase.conflict;
      failure = error;
      return null;
    } on HtmlSaveIncomplete catch (error) {
      if (_closed) return null;
      _incomplete(error);
      return null;
    } catch (error) {
      if (_closed) return null;
      failure = error;
      _phase = HtmlEditorPhase.editing;
      return null;
    } finally {
      if (!_closed) await flushRecovery();
      _busy = false;
      if (!_closed) notifyListeners();
    }
  }

  /// Reads only. A matching current value is an observation, never a fabricated
  /// receipt for a request whose response was lost.
  Future<void> verify() async {
    final pending = _attempt;
    if (_closed ||
        _busy ||
        pending == null ||
        !{
          HtmlEditorPhase.contentUnknown,
          HtmlEditorPhase.labelsPending,
          HtmlEditorPhase.verificationPending,
        }.contains(_phase)) {
      throw StateError('No unresolved HTML attempt to verify');
    }
    _busy = true;
    failure = null;
    notifyListeners();
    try {
      final actual = await repository.read(
        pending.baseline.metadata.id,
        password: pending.baseline.unlockPassword,
      );
      if (_closed) return;
      _everProtected |= actual.metadata.protected;
      final sameProtection =
          actual.metadata.protected == pending.baseline.metadata.protected;
      if (sameProtection && pending.edit.matches(actual)) {
        _completed(HtmlSaveOutcome(actual, pending.observedContent()));
      } else if (sameProtection &&
          pending.edit.sameContent(actual) &&
          !pending.labelsReceipt &&
          actual.labels.length == pending.baseline.labels.length &&
          actual.labels.toSet().containsAll(pending.baseline.labels)) {
        _attempt = pending.observedContent();
        _latest = actual;
        _phase = HtmlEditorPhase.labelsPending;
      } else {
        _latest = actual;
        _phase = HtmlEditorPhase.conflict;
      }
    } catch (error) {
      if (!_closed) failure = error;
    } finally {
      if (!_closed) await flushRecovery();
      _busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> continueLabels() async {
    final pending = _attempt;
    if (_closed ||
        _busy ||
        _phase != HtmlEditorPhase.labelsPending ||
        pending == null ||
        (!pending.contentReceipt && !pending.contentObserved)) {
      throw StateError('HTML label recovery is not available');
    }
    _busy = true;
    _phase = HtmlEditorPhase.saving;
    failure = null;
    notifyListeners();
    try {
      await _persistPending(pending);
      if (_closed) return;
      final outcome = await repository.finishLabels(pending);
      if (!_closed) _completed(outcome);
    } on HtmlSaveIncomplete catch (error) {
      if (!_closed) _incomplete(error);
    } catch (error) {
      if (!_closed) {
        failure = error;
        _phase = HtmlEditorPhase.labelsPending;
      }
    } finally {
      if (!_closed) await flushRecovery();
      _busy = false;
      if (!_closed) notifyListeners();
    }
  }

  /// Called only after the user has viewed and accepted the latest server
  /// baseline. Preserve their unsaved source and require another explicit save.
  void acceptLatestForEditing() {
    final actual = _latest;
    if (_closed ||
        _busy ||
        _phase != HtmlEditorPhase.conflict ||
        actual == null) {
      throw StateError('No reviewed HTML conflict baseline');
    }
    if (actual.metadata.id != _baseline.metadata.id ||
        actual.metadata.memberId != _baseline.metadata.memberId ||
        actual.metadata.collection != _baseline.metadata.collection) {
      throw StateError('HTML conflict belongs to another resource');
    }
    _baseline = actual;
    _everProtected |= actual.metadata.protected;
    _attempt = null;
    _latest = null;
    failure = null;
    _phase = _draft.matches(actual)
        ? HtmlEditorPhase.clean
        : HtmlEditorPhase.editing;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    repository.dispose();
    super.dispose();
  }
}
