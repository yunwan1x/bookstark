import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'complex_recovery_vault.dart';
import 'local_complex_notes_repository.dart';

enum ComplexSavePhase {
  ready,
  drafting,
  draftFailed,
  saving,
  unknown,
  conflict,
  committedCleanupFailed,
  reviewing,
  discarding,
  closed,
}

/// Native/web engines provide validated snapshots; only this typed controller
/// decides when a real database receipt permits a saved indication.
class LocalComplexEditorController extends ChangeNotifier {
  LocalComplexEditorController({
    required this.repository,
    required this.vault,
    this.ephemeralDrafts = false,
    this.beforeAdoptReviewed,
    required ComplexNote baseline,
    ComplexRecoveryRecord? recovery,
  }) : _baseline = baseline,
       _edit = ComplexNoteEdit(
         title: baseline.title,
         document: baseline.document,
         labels: baseline.labels,
       ) {
    if (baseline.scope != repository.scope ||
        baseline.collection != repository.collection ||
        baseline.document.kind != repository.kind ||
        vault.scope != repository.scope ||
        vault.collection != repository.collection ||
        vault.kind != repository.kind) {
      throw StateError('Complex editor identity mismatch');
    }
    if (recovery != null) {
      if (!recovery.owns(baseline)) {
        throw StateError('Recovery identity mismatch');
      }
      _edit = recovery.edit;
      _durable = true;
      if (recovery.pending || !recovery.baselineMatches(baseline)) {
        _phase = ComplexSavePhase.unknown;
      }
    }
  }
  final ComplexNotesRepository repository;
  final ComplexRecoveryVault vault;
  final bool ephemeralDrafts;
  final Future<void> Function(ComplexNote actual)? beforeAdoptReviewed;
  ComplexNote _baseline;
  ComplexNoteEdit _edit;
  ComplexNote? _observed;
  ComplexSavePhase _phase = ComplexSavePhase.ready;
  bool _busy = false, _closed = false, _durable = false;
  ComplexNote get baseline => _baseline;
  ComplexNoteEdit get edit => _edit;
  ComplexNote? get observed => _observed;
  ComplexSavePhase get phase => _closed ? ComplexSavePhase.closed : _phase;
  bool get busy => _busy;
  bool get dirty => !_edit.matches(_baseline);
  bool get draftDurable => _durable && !ephemeralDrafts;
  bool get requiresReview =>
      _phase == ComplexSavePhase.unknown || _phase == ComplexSavePhase.conflict;
  bool get editable =>
      !_closed &&
      !requiresReview &&
      _phase != ComplexSavePhase.committedCleanupFailed;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _available() {
    if (_closed || _busy) throw StateError('Complex editor is unavailable');
  }

  void _readyForEdit() {
    _available();
    if (!editable) throw StateError('Resolve the previous operation first');
  }

  void _valid(ComplexNoteEdit edit) {
    final remoteNotePreserved =
        repository.collection == 'remote-note' &&
        edit.title == _baseline.title &&
        jsonEncode(edit.labels) == jsonEncode(_baseline.labels);
    edit.validate(
      bookDocumentBodyOnly: repository.collection == 'book-document',
      ownedRemoteBodyOnly:
          const {
            'remote-book-document',
            'shared-complex',
          }.contains(repository.collection) ||
          remoteNotePreserved,
    );
    if (repository.collection == 'book-document' &&
        (edit.title != _baseline.title ||
            edit.labels.isNotEmpty ||
            _baseline.resourceFingerprint == null)) {
      throw StateError('Book document editing is body-only');
    }
    if (const {
          'remote-book-document',
          'shared-complex',
        }.contains(repository.collection) &&
        (edit.title != _baseline.title ||
            jsonEncode(edit.labels) != jsonEncode(_baseline.labels) ||
            _baseline.resourceFingerprint == null)) {
      throw StateError('Owned book-document source editing is body-only');
    }
    if (repository.collection == 'remote-note' &&
        _baseline.resourceFingerprint == null) {
      throw StateError('Owned note baseline required');
    }
    if (edit.document.kind != repository.kind) {
      throw StateError('Document type changed');
    }
  }

  /// The caller coalesces input snapshots. A concurrent save/review never gets
  /// queued behind a stale draft operation and cannot replace its pending log.
  Future<void> checkpoint(ComplexNoteEdit edit) async {
    _readyForEdit();
    _valid(edit);
    _busy = true;
    _edit = edit;
    _durable = false;
    _phase = ComplexSavePhase.drafting;
    _notify();
    try {
      if (edit.matches(_baseline)) {
        await vault.remove(_baseline.id);
      } else {
        await vault.write(
          ComplexRecoveryRecord.capture(_baseline, edit, pending: false),
        );
      }
      if (_closed) return;
      _durable = dirty;
      _phase = ComplexSavePhase.ready;
    } catch (_) {
      if (!_closed) _phase = ComplexSavePhase.draftFailed;
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Input is frozen by the surface before invoking this. Pending durability
  /// always precedes SQL. Every unknown result requires read-only verification.
  Future<ComplexNote?> save(ComplexNoteEdit edit) async {
    _readyForEdit();
    _valid(edit);
    _busy = true;
    _edit = edit;
    _durable = false;
    _phase = ComplexSavePhase.saving;
    _notify();
    var enteredRepository = false;
    try {
      await vault.write(
        ComplexRecoveryRecord.capture(_baseline, edit, pending: true),
      );
      _durable = true;
      if (_closed) return null;
      enteredRepository = true;
      final actual = await repository.save(_baseline, edit);
      if (_closed) {
        return null; // Keep pending for cold, read-only reconciliation.
      }
      if (actual.scope != _baseline.scope ||
          actual.id != _baseline.id ||
          actual.collection != _baseline.collection ||
          !edit.matches(actual)) {
        _phase = ComplexSavePhase.unknown;
        return null;
      }
      _baseline = actual;
      _edit = ComplexNoteEdit(
        title: actual.title,
        document: actual.document,
        labels: actual.labels,
      );
      try {
        await vault.remove(actual.id);
        if (!_closed) {
          _phase = ComplexSavePhase.ready;
          _durable = false;
        }
      } catch (_) {
        if (!_closed) _phase = ComplexSavePhase.committedCleanupFailed;
      }
      return actual;
    } on ComplexNoteConflict catch (conflict) {
      if (!_closed) {
        _observed = conflict.actual;
        _phase = ComplexSavePhase.conflict;
      }
      return null;
    } catch (_) {
      if (!_closed) {
        _phase = enteredRepository
            ? ComplexSavePhase.unknown
            : ComplexSavePhase.draftFailed;
      }
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> retryCleanup() async {
    _available();
    if (_phase != ComplexSavePhase.committedCleanupFailed) {
      throw StateError('No confirmed-save cleanup is pending');
    }
    _busy = true;
    _notify();
    try {
      await vault.remove(_baseline.id);
      if (!_closed) {
        _phase = ComplexSavePhase.ready;
        _durable = false;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<ComplexNote> observe() async {
    _available();
    if (!requiresReview) throw StateError('No unresolved operation');
    _busy = true;
    _notify();
    try {
      final actual = await repository.read(_baseline.id);
      if (_closed) throw StateError('Editor closed during verification');
      if (actual.scope != _baseline.scope ||
          actual.collection != _baseline.collection ||
          actual.id != _baseline.id ||
          actual.document.kind != repository.kind) {
        throw StateError('Observed document identity changed');
      }
      _observed = actual;
      return actual;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// UI must show the full read-only draft/current versions before this call.
  /// This fresh read prevents a reviewed, stale state from becoming a baseline.
  /// Keeping a draft enables a new explicit save; it never replays an old one.
  Future<void> adoptReviewed(
    ComplexNote reviewed, {
    required bool keepDraft,
  }) async {
    _available();
    if (!requiresReview || _observed == null || !_observed!.same(reviewed)) {
      throw StateError('Review the current document first');
    }
    _busy = true;
    _notify();
    try {
      final actual = await repository.read(_baseline.id);
      if (_closed) throw StateError('Editor closed during verification');
      if (!actual.same(reviewed)) {
        _observed = actual;
        _phase = ComplexSavePhase.conflict;
        throw ComplexNoteConflict(actual);
      }
      await beforeAdoptReviewed?.call(actual);
      if (_closed) throw StateError('Editor closed during review');
      final retainedEdit =
          keepDraft &&
              const {
                'book-document',
                'remote-book-document',
                'shared-complex',
              }.contains(repository.collection)
          ? ComplexNoteEdit(
              title: actual.title,
              document: _edit.document,
              labels: actual.labels,
            )
          : _edit;
      if (keepDraft) {
        await vault.write(
          ComplexRecoveryRecord.capture(actual, retainedEdit, pending: false),
        );
      } else {
        await vault.remove(actual.id);
      }
      if (_closed) return;
      _baseline = actual;
      if (keepDraft &&
          const {
            'book-document',
            'remote-book-document',
            'shared-complex',
          }.contains(repository.collection)) {
        _edit = retainedEdit;
      }
      if (!keepDraft) {
        _edit = ComplexNoteEdit(
          title: actual.title,
          document: actual.document,
          labels: actual.labels,
        );
      }
      _durable = keepDraft && dirty;
      _observed = null;
      _phase = ComplexSavePhase.ready;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> discard() async {
    _readyForEdit();
    _busy = true;
    _phase = ComplexSavePhase.discarding;
    _notify();
    try {
      await vault.remove(_baseline.id);
      if (_closed) return;
      _edit = ComplexNoteEdit(
        title: _baseline.title,
        document: _baseline.document,
        labels: _baseline.labels,
      );
      _durable = false;
      _phase = ComplexSavePhase.ready;
    } catch (_) {
      if (!_closed) _phase = ComplexSavePhase.draftFailed;
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    repository.dispose();
    super.dispose();
  }
}
