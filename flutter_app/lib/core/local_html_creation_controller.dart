import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'html_creation_vault.dart';
import 'html_notes_repository.dart';
import 'local_html_notes_repository.dart';

class HtmlCreationNameConflict implements Exception {
  const HtmlCreationNameConflict();
}

enum HtmlCreationPhase { editing, creating, unknown, review, cleanup, finished }

/// A durable new-note intent. A lost result never triggers automatic INSERT.
class LocalHtmlCreationController extends ChangeNotifier {
  LocalHtmlCreationController(
    this.repository,
    this.vault, {
    HtmlCreationRecord? record,
  }) : _record =
           record ??
           HtmlCreationRecord(
             key: newHtmlCreationKey(),
             memberId: 1,
             collection: repository.collection,
             edit: HtmlNoteEdit(
               title: '',
               source:
                   '<!doctype html>\n<html lang="zh-CN">\n<body>\n<h1>我的网页</h1>\n</body>\n</html>\n',
               labels: [],
             ),
             pending: false,
           ),
       _dirty = record != null {
    if (_record.memberId != 1 ||
        _record.collection != repository.collection ||
        vault.memberId != 1 ||
        vault.collection != repository.collection ||
        vault.prefix != 'bookstark.local-html-create.v1') {
      throw const FormatException('Local HTML creation scope mismatch');
    }
    if (_record.pending) _phase = HtmlCreationPhase.unknown;
  }
  final LocalHtmlNotesRepository repository;
  final HtmlCreationVault vault;
  HtmlCreationRecord _record;
  HtmlCreationPhase _phase = HtmlCreationPhase.editing;
  bool _closed = false, _busy = false, _dirty, _reviewed = false;
  bool confirmedAbsent = false, receiptKnown = false;
  bool _endingUnavailable = false;
  HtmlNote? _observed, _created;
  Object? failure, recoveryFailure;
  HtmlCreationRecord get record => _record;
  HtmlNoteEdit get draft => _record.edit;
  HtmlCreationPhase get phase => _phase;
  bool get busy => _busy;
  bool get dirty => _dirty;
  bool get canEdit => !_closed && !_busy && _phase == HtmlCreationPhase.editing;
  bool get reviewed => _reviewed;
  HtmlNote? get observed => _observed;
  HtmlNote? get created => _created;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void edit(HtmlNoteEdit value) {
    if (!canEdit) throw StateError('Resolve HTML creation before editing');
    _record = _record.copy(edit: value);
    _dirty = true;
    failure = null;
    _notify();
  }

  Future<bool> flush() async {
    if (_closed) return true;
    try {
      if (_phase == HtmlCreationPhase.finished) {
        await vault.remove();
      } else if (_dirty || _record.pending) {
        await vault.write(_record);
      }
      recoveryFailure = null;
      return true;
    } catch (error) {
      recoveryFailure = error;
      return false;
    }
  }

  Future<void> _finish() async {
    try {
      await vault.remove();
      if (_closed) return;
      recoveryFailure = null;
      failure = null;
      _phase = HtmlCreationPhase.finished;
    } catch (error) {
      if (_closed) return;
      recoveryFailure = error;
      _phase = HtmlCreationPhase.cleanup;
    }
  }

  Future<void> save() async {
    if (!canEdit) throw StateError('HTML creation is not available');
    try {
      draft.validate(labelsAsCsv: false);
    } catch (error) {
      failure = error;
      _notify();
      return;
    }
    _busy = true;
    _dirty = true;
    failure = null;
    _phase = HtmlCreationPhase.creating;
    _notify();
    _record = _record.copy(pending: true);
    try {
      try {
        await vault.write(_record);
      } catch (error) {
        if (_closed) return;
        recoveryFailure = error;
        failure = error;
        _record = _record.copy(pending: false);
        _phase = HtmlCreationPhase.editing;
        return;
      }
      if (_closed) return;
      final result = await repository.createOnce(
        draft,
        creationKey: _record.key,
      );
      if (_closed) return;
      _record = _record.copy(createdId: result.note.metadata.id);
      if (!result.inserted) {
        _observed = result.note;
        _reviewed = false;
        _phase = HtmlCreationPhase.review;
        await flush();
        return;
      }
      _created = result.note;
      receiptKnown = true;
      try {
        await vault.write(_record);
      } catch (error) {
        if (!_closed) {
          recoveryFailure = error;
          _phase = HtmlCreationPhase.cleanup;
        }
        return;
      }
      if (!_closed) await _finish();
    } catch (error) {
      if (!_closed) {
        if (repository.collection == 'article' &&
            error is DatabaseException &&
            error.isUniqueConstraintError()) {
          // SQLite has rolled the whole transaction back before returning a
          // constraint failure. This is a definite rejection, not a lost result.
          failure = const HtmlCreationNameConflict();
          _record = _record.copy(pending: false);
          _phase = HtmlCreationPhase.editing;
          await flush();
        } else {
          failure = error;
          _phase = HtmlCreationPhase.unknown;
          confirmedAbsent = false;
        }
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> verify() async {
    if (_closed ||
        _busy ||
        !{
          HtmlCreationPhase.unknown,
          HtmlCreationPhase.review,
        }.contains(_phase)) {
      throw StateError('No pending HTML creation to verify');
    }
    _busy = true;
    failure = null;
    confirmedAbsent = false;
    _reviewed = false;
    _notify();
    try {
      final actual = await repository.findCreation(_record.key);
      if (_closed) return;
      if (actual == null) {
        if (_record.createdId != null) {
          throw HtmlCreationTargetUnavailable(_record.createdId!);
        }
        _observed = null;
        confirmedAbsent = true;
        _phase = HtmlCreationPhase.unknown;
      } else {
        if (_record.createdId != null &&
            _record.createdId != actual.metadata.id) {
          throw StateError('Creation ID changed');
        }
        _observed = actual;
        _phase = HtmlCreationPhase.review;
      }
    } catch (error) {
      if (!_closed) {
        failure = error;
        _phase = HtmlCreationPhase.unknown;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> allowRetryAfterAbsent() async {
    if (_closed ||
        _busy ||
        _phase != HtmlCreationPhase.unknown ||
        !confirmedAbsent) {
      throw StateError('Read the local creation ledger before retry');
    }
    _record = _record.copy(pending: false);
    _phase = HtmlCreationPhase.editing;
    confirmedAbsent = false;
    failure = null;
    await flush();
    _notify();
  }

  bool _same(HtmlNote a, HtmlNote b) =>
      a.metadata.same(b.metadata) &&
      a.source == b.source &&
      a.labels.length == b.labels.length &&
      a.labels.toSet().containsAll(b.labels);
  void markReviewed(HtmlNote snapshot) {
    if (_closed ||
        _busy ||
        _phase != HtmlCreationPhase.review ||
        _observed == null ||
        !_same(_observed!, snapshot)) {
      throw StateError('Read the current full HTML snapshot first');
    }
    _reviewed = true;
    _notify();
  }

  Future<void> adoptObserved() async {
    final snapshot = _observed;
    if (_closed ||
        _busy ||
        _phase != HtmlCreationPhase.review ||
        !_reviewed ||
        snapshot == null) {
      throw StateError('Review the complete current HTML before adopting');
    }
    _busy = true;
    failure = null;
    _notify();
    try {
      final latest = await repository.findCreation(_record.key);
      if (_closed) return;
      if (latest == null) throw const HtmlNoteChanged();
      if (!_same(snapshot, latest)) {
        _observed = latest;
        _reviewed = false;
        failure = const HtmlNoteChanged();
        return;
      }
      _created = latest;
      receiptKnown = false;
      await _finish();
    } catch (error) {
      if (!_closed) {
        failure = error;
        _phase = HtmlCreationPhase.unknown;
        _reviewed = false;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> retryCleanup() async {
    if (_closed ||
        _busy ||
        _phase != HtmlCreationPhase.cleanup ||
        (_created == null && !_endingUnavailable)) {
      throw StateError('No known HTML result to finish');
    }
    _busy = true;
    _notify();
    try {
      await _finish();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> endUnavailable() async {
    if (_closed ||
        _busy ||
        _phase != HtmlCreationPhase.unknown ||
        failure is! HtmlCreationTargetUnavailable) {
      throw StateError('Only a verified unavailable creation may be dismissed');
    }
    _endingUnavailable = true;
    _busy = true;
    _notify();
    try {
      await _finish();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> discardDraft() async {
    if (!canEdit) {
      throw StateError('Keep unresolved creation intent until reviewed');
    }
    try {
      await vault.remove();
      recoveryFailure = null;
      return true;
    } catch (error) {
      recoveryFailure = error;
      _notify();
      return false;
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
