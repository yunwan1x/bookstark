import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'complex_editor_document.dart';
import 'local_article_creation_record.dart';
import 'local_complex_notes_repository.dart';

enum LocalArticleCreationPhase {
  editing,
  creating,
  unknown,
  review,
  cleanup,
  finished,
}

/// Durable intent before INSERT; a lost result only permits an explicit fresh
/// read/review. The SQL receipt prevents replay even if process state is lost.
class LocalArticleCreationController extends ChangeNotifier {
  LocalArticleCreationController({
    required this.repository,
    required this.vault,
    LocalArticleCreationRecord? record,
    this.isCurrentScope,
  }) : _record =
           record ??
           LocalArticleCreationRecord(
             scope: repository.scope,
             key: newComplexCreationKey(),
             edit: ComplexNoteEdit(
               title: '',
               document: ComplexEditorDocument.parse(
                 ComplexEditorKind.markdown,
                 '',
               ),
               labels: const [],
             ),
             pending: false,
           ),
       _dirty = record != null {
    if (repository.kind != ComplexEditorKind.markdown ||
        repository.collection != 'article' ||
        vault.scope != repository.scope ||
        _record.scope != repository.scope) {
      throw const FormatException('Local article creation scope mismatch');
    }
    if (_record.pending) {
      _phase = _record.createdId == null
          ? LocalArticleCreationPhase.unknown
          : LocalArticleCreationPhase.cleanup;
    }
  }
  final ComplexNotesCreationRepository repository;
  final LocalArticleCreationVault vault;
  final bool Function()? isCurrentScope;
  LocalArticleCreationRecord _record;
  LocalArticleCreationPhase _phase = LocalArticleCreationPhase.editing;
  bool _closed = false, _busy = false, _dirty, _reviewed = false;
  bool _confirmedAbsent = false, _unavailable = false, _discarded = false;
  int? _observedId;
  ComplexNote? _observed, _created;
  Future<void>? _operation;
  Object? failure, recoveryFailure;
  LocalArticleCreationRecord get record => _record;
  ComplexNoteEdit get draft => _record.edit;
  LocalArticleCreationPhase get phase => _phase;
  bool get busy => _busy;
  bool get dirty => _dirty;
  bool get reviewed => _reviewed;
  bool get confirmedAbsent => _confirmedAbsent;
  bool get unavailable => _unavailable;
  bool get discarded => _discarded;
  ComplexNote? get observed => _observed;
  ComplexNote? get created => _created;
  bool get canEdit =>
      _active() && !_busy && _phase == LocalArticleCreationPhase.editing;
  bool _active() {
    if (_closed) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  void _require() {
    if (!_active() || _busy) throw StateError('Article creation unavailable');
  }

  void _notify() {
    if (_active()) notifyListeners();
  }

  bool _owns(ComplexNote note) =>
      note.scope == repository.scope &&
      note.id > 0 &&
      note.collection == 'article' &&
      note.document.kind == ComplexEditorKind.markdown;
  String get _inputDigest =>
      complexCreationInputDigest(repository.kind, repository.collection, draft);

  void edit(ComplexNoteEdit value) {
    if (!canEdit) throw StateError('Resolve article creation before editing');
    _record = _record.copy(edit: value);
    _dirty = true;
    failure = null;
    _notify();
  }

  Future<void> _operate(Future<void> Function() action) {
    _require();
    final done = Completer<void>();
    // Publish the barrier before synchronous listeners can request a flush.
    _operation = done.future;
    _busy = true;
    _notify();
    unawaited(
      Future<void>.sync(() async {
        try {
          await action();
        } catch (error) {
          if (_active()) {
            failure = error;
            if (_phase != LocalArticleCreationPhase.cleanup) {
              _phase = LocalArticleCreationPhase.unknown;
            }
          }
        } finally {
          _busy = false;
          _notify();
        }
      }).then<void>(
        (_) => done.complete(),
        onError: (Object error, StackTrace stack) =>
            done.completeError(error, stack),
      ),
    );
    return done.future;
  }

  Future<bool> flush() async {
    final operation = _operation;
    if (_busy && operation != null) await operation;
    if (!_active()) return false;
    if (_phase == LocalArticleCreationPhase.finished) return true;
    try {
      if (_dirty || _record.pending) await vault.write(_record);
      if (!_active()) return false;
      recoveryFailure = null;
      return true;
    } catch (error) {
      if (_active()) recoveryFailure = error;
      return false;
    }
  }

  Future<void> _finish(int id) async {
    if (!_active()) return;
    _record = _record.copy(createdId: id, pending: true);
    _phase = LocalArticleCreationPhase.cleanup;
    try {
      // If this receipt write is lost, a restart still has sealed pending plus
      // the SQL ledger. A known commit may only retry storage, never INSERT.
      await vault.write(_record);
      if (!_active()) return;
      await vault.remove(creationKey: _record.key);
      if (!_active()) return;
      recoveryFailure = null;
      failure = null;
      _phase = LocalArticleCreationPhase.finished;
    } catch (error) {
      if (_active()) recoveryFailure = error;
    }
  }

  void _showReceipt(ComplexCreationReceipt? receipt) {
    if (receipt == null) {
      _observed = null;
      _observedId = null;
      _confirmedAbsent = true;
      _unavailable = false;
    } else {
      if (receipt.inputDigest != _inputDigest ||
          receipt.noteId <= 0 ||
          _record.createdId != null && _record.createdId != receipt.noteId ||
          receipt.note != null &&
              (!_owns(receipt.note!) || receipt.note!.id != receipt.noteId)) {
        throw StateError('Creation receipt identity mismatch');
      }
      _observed = receipt.note;
      _observedId = receipt.noteId;
      _confirmedAbsent = false;
      _unavailable = receipt.note == null;
    }
    _reviewed = false;
    _phase = LocalArticleCreationPhase.review;
  }

  Future<void> _submit() async {
    _record = _record.copy(pending: true);
    _dirty = true;
    _phase = LocalArticleCreationPhase.creating;
    try {
      await vault.write(_record);
    } catch (error) {
      if (_active()) {
        recoveryFailure = error;
        _phase = LocalArticleCreationPhase.unknown;
      }
      return; // No INSERT when pending durability was not acknowledged.
    }
    if (!_active()) return;
    try {
      final result = await repository.createOnce(
        draft,
        creationKey: _record.key,
      );
      if (!_active()) return;
      if (!_owns(result.note)) {
        throw StateError('Created article identity mismatch');
      }
      if (!result.inserted) {
        _showReceipt(
          ComplexCreationReceipt(
            noteId: result.note.id,
            inputDigest: _inputDigest,
            note: result.note,
          ),
        );
        return;
      }
      if (!draft.matches(result.note)) {
        throw StateError('Created article readback mismatch');
      }
      _created = result.note;
      await _finish(result.note.id);
    } catch (error) {
      if (!_active()) return;
      failure = error;
      _phase = LocalArticleCreationPhase.unknown;
      if (error is DatabaseException && error.isUniqueConstraintError()) {
        try {
          final editable = await vault.resumeAfterAbsent(
            _record,
            stillAbsent: () async =>
                await repository.findCreation(_record.key) == null,
          );
          if (!_active()) return;
          _record = editable;
          _phase = LocalArticleCreationPhase.editing;
        } catch (storageError) {
          if (_active()) recoveryFailure = storageError;
        }
      }
    }
  }

  Future<void> save() {
    _require();
    if (_phase != LocalArticleCreationPhase.editing) {
      throw StateError('Review the prior creation before saving');
    }
    try {
      draft.validate();
    } catch (error) {
      failure = error;
      _notify();
      return Future<void>.value();
    }
    return _operate(_submit);
  }

  Future<void> inspect() {
    _require();
    if (_phase != LocalArticleCreationPhase.unknown &&
        _phase != LocalArticleCreationPhase.review) {
      throw StateError('No uncertain creation to inspect');
    }
    return _operate(() async {
      final receipt = await repository.findCreation(_record.key);
      if (!_active()) return;
      _showReceipt(receipt);
      failure = null;
    });
  }

  void setReviewed(bool value) {
    _require();
    if (_phase != LocalArticleCreationPhase.review || _unavailable) {
      throw StateError('No available creation snapshot to review');
    }
    _reviewed = value;
    _notify();
  }

  Future<void> adopt() {
    _require();
    final observed = _observed;
    if (_phase != LocalArticleCreationPhase.review ||
        !_reviewed ||
        observed == null ||
        _unavailable) {
      throw StateError('Review the created article before adoption');
    }
    return _operate(() async {
      final fresh = await repository.findCreation(_record.key);
      if (!_active()) return;
      if (fresh == null ||
          fresh.note == null ||
          fresh.noteId != observed.id ||
          fresh.inputDigest != _inputDigest ||
          !fresh.note!.same(observed)) {
        _showReceipt(fresh);
        return;
      }
      _created = fresh.note;
      await _finish(fresh.noteId);
    });
  }

  Future<void> retryCreate() {
    _require();
    if (_phase != LocalArticleCreationPhase.review ||
        !_reviewed ||
        !_confirmedAbsent) {
      throw StateError('Review the absent creation before retrying');
    }
    return _operate(() async {
      final fresh = await repository.findCreation(_record.key);
      if (!_active()) return;
      if (fresh != null) {
        _showReceipt(fresh);
        return;
      }
      await _submit();
    });
  }

  Future<void> resumeEditing() {
    _require();
    if (_phase != LocalArticleCreationPhase.review ||
        !_confirmedAbsent ||
        !_reviewed) {
      throw StateError('Review confirmed absence before editing again');
    }
    return _operate(() async {
      // A previous failed durable write may have left no slot. Seal the same
      // intent first, then prove ledger absence under the storage lease.
      await vault.write(_record.copy(pending: true));
      if (!_active()) return;
      final editable = await vault.resumeAfterAbsent(
        _record,
        stillAbsent: () async =>
            await repository.findCreation(_record.key) == null,
      );
      if (!_active()) return;
      _record = editable;
      _reviewed = false;
      _confirmedAbsent = false;
      failure = null;
      recoveryFailure = null;
      _phase = LocalArticleCreationPhase.editing;
    });
  }

  Future<void> retryCleanup() {
    _require();
    final id = _record.createdId;
    if (_phase != LocalArticleCreationPhase.cleanup || id == null) {
      throw StateError('No known creation cleanup to retry');
    }
    return _operate(() => _finish(id));
  }

  Future<void> finishUnavailable() {
    _require();
    final id = _observedId;
    if (_phase != LocalArticleCreationPhase.review ||
        !_unavailable ||
        id == null) {
      throw StateError('No unavailable created article to resolve');
    }
    return _operate(() async {
      final fresh = await repository.findCreation(_record.key);
      if (!_active()) return;
      if (fresh == null ||
          fresh.note != null ||
          fresh.noteId != id ||
          fresh.inputDigest != _inputDigest) {
        _showReceipt(fresh);
        return;
      }
      // The retained immutable receipt proves a prior commit even though the
      // target is unavailable. Clear only this draft; never recreate a target.
      await _finish(id);
    });
  }

  Future<void> discardDraft() {
    _require();
    if (_phase != LocalArticleCreationPhase.editing || _record.pending) {
      throw StateError('Uncertain creation cannot be discarded as a new draft');
    }
    return _operate(() async {
      try {
        await vault.remove(creationKey: _record.key);
        if (!_active()) return;
        _discarded = true;
        _phase = LocalArticleCreationPhase.finished;
      } catch (error) {
        if (_active()) recoveryFailure = error;
      }
    });
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
