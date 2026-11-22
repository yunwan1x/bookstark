import 'dart:convert';
import 'api_client.dart';
import 'package:flutter/foundation.dart';
import 'html_creation_vault.dart';
import 'html_creation_candidates.dart';
import 'html_protected_creation_record.dart';
import 'html_notes_repository.dart';
import 'remote_html_creation_repository.dart';

enum RemoteHtmlCreationPhase {
  editing,
  creating,
  unknown,
  review,
  cleanup,
  finished,
}

/// An uncertain POST can only be resolved by observation and explicit adoption.
class RemoteHtmlCreationController extends ChangeNotifier {
  RemoteHtmlCreationController(this.repository, this.vault, {Object? record})
    : _session = repository.client.exportSession()['token'],
      _record =
          record ??
          HtmlCreationRecord(
            key: newHtmlCreationKey(),
            memberId: repository.memberId,
            collection: repository.collection,
            edit: HtmlNoteEdit(
              title: '',
              source:
                  '<!doctype html>\n<html lang="zh-CN">\n<body>\n</body>\n</html>\n',
              labels: [],
            ),
            pending: false,
          ) {
    final expectedNamespace = jsonEncode([
      BookstarkClient.normalizeServer(
        repository.client.baseUri.toString(),
      ).toString(),
      repository.memberId,
      repository.collection,
      'html',
      'new',
    ]);
    if (vault.namespace != expectedNamespace ||
        vault.prefix != 'bookstark.html-create.v1' ||
        vault.memberId != repository.memberId ||
        vault.collection != repository.collection) {
      throw const FormatException('Remote HTML creation scope mismatch');
    }
    final value = _record;
    if (value is HtmlCreationRecord) {
      if (value.memberId != repository.memberId ||
          value.collection != repository.collection) {
        throw const FormatException('Remote HTML creation owner mismatch');
      }
      if (value.pending) _phase = RemoteHtmlCreationPhase.unknown;
    } else if (value is HtmlProtectedCreationRecord) {
      if (value.memberId != repository.memberId ||
          value.collection != repository.collection) {
        throw const FormatException('Protected creation owner mismatch');
      }
      _phase = RemoteHtmlCreationPhase.unknown;
    } else {
      throw const FormatException('Unsupported creation recovery');
    }
    notes = RemoteHtmlNotesRepository(
      repository.client,
      memberId: repository.memberId,
      collection: repository.collection,
    );
  }
  final RemoteHtmlCreationRepository repository;
  final HtmlCreationVault vault;
  final String? _session;
  void _checkOwner() {
    if (_closed ||
        _session == null ||
        _session.isEmpty ||
        repository.client.exportSession()['token'] != _session) {
      throw StateError('HTML creation owner session ended');
    }
  }

  late final RemoteHtmlNotesRepository notes;
  Object _record;
  Object get record => _record;
  HtmlNoteEdit? get draft => _record is HtmlCreationRecord
      ? (_record as HtmlCreationRecord).edit
      : null;
  int? get receiptId => switch (_record) {
    HtmlCreationRecord r => r.createdId,
    HtmlProtectedCreationRecord r => r.createdId,
    _ => null,
  };
  RemoteHtmlCreationPhase _phase = RemoteHtmlCreationPhase.editing;
  RemoteHtmlCreationPhase get phase => _phase;
  bool _busy = false, _closed = false, _reviewed = false;
  bool receiptKnown = false;
  bool get busy => _busy;
  bool get canEdit =>
      !_closed && !_busy && _phase == RemoteHtmlCreationPhase.editing;
  bool get reviewed => _reviewed;
  HtmlNote? observed, created;
  Object? failure, recoveryFailure;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _persist() {
    _checkOwner();
    return switch (_record) {
      HtmlCreationRecord r => vault.write(r),
      HtmlProtectedCreationRecord r => vault.writeProtected(r),
      _ => throw StateError('Invalid creation state'),
    };
  }

  void edit(HtmlNoteEdit value) {
    _checkOwner();
    if (!canEdit) throw StateError('Resolve creation before editing');
    _record = (_record as HtmlCreationRecord).copy(edit: value);
    failure = null;
    _notify();
  }

  Future<bool> flush() async {
    if (_closed) return false;
    try {
      await _persist();
      recoveryFailure = null;
      return true;
    } catch (error) {
      recoveryFailure = error;
      return false;
    }
  }

  Future<void> _finish(HtmlNote note) async {
    created = note;
    try {
      _checkOwner();
      await vault.remove();
      if (_closed) return;
      recoveryFailure = null;
      _phase = RemoteHtmlCreationPhase.finished;
    } catch (error) {
      if (_closed) return;
      recoveryFailure = error;
      _phase = RemoteHtmlCreationPhase.cleanup;
    }
  }

  Future<void> save() async {
    if (!canEdit) throw StateError('Creation is unavailable');
    final ordinary = _record as HtmlCreationRecord;
    try {
      ordinary.edit.validate();
    } catch (error) {
      failure = error;
      _notify();
      return;
    }
    _busy = true;
    failure = null;
    _phase = RemoteHtmlCreationPhase.creating;
    _notify();
    _record = ordinary.copy(pending: true);
    try {
      if (!await flush()) {
        _record = ordinary;
        _phase = RemoteHtmlCreationPhase.editing;
        return;
      }
      if (_closed) return;
      final id = await repository.submit(
        ordinary.edit,
        persistReceipt: (id) async {
          if (_closed) throw StateError('Creation editor closed');
          _record = (_record as HtmlCreationRecord).copy(createdId: id);
          await _persist();
        },
      );
      if (_closed) return;
      receiptKnown = true;
      _phase = RemoteHtmlCreationPhase.unknown;
      await _inspect(id);
      if (!_closed && observed != null && draft?.matches(observed!) == true) {
        await _finish(observed!);
      }
    } on HtmlCreationUnresolved catch (error) {
      if (!_closed) {
        failure = error;
        // Only a failure before transport submission is known not to create.
        if (!error.submitted) {
          _record = ordinary;
          _phase = RemoteHtmlCreationPhase.editing;
          await flush();
        } else {
          _phase = RemoteHtmlCreationPhase.unknown;
          if (error.receiptId != null) {
            receiptKnown = true;
            _record = (_record as HtmlCreationRecord).copy(
              createdId: error.receiptId,
            );
            recoveryFailure = error.cause;
          }
        }
      }
    } catch (error) {
      if (!_closed) {
        failure = error;
        _phase = RemoteHtmlCreationPhase.unknown;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _inspect(int id, {String? password}) async {
    if (id <= 0 || receiptId != null && receiptId != id) {
      throw const FormatException('Candidate does not match acknowledged ID');
    }
    _checkOwner();
    final row = await repository.client.htmlNoteMetadata(id);
    _checkOwner();
    if (_closed) return;
    final metadata = HtmlNoteMetadata.parse(
      row,
      id: id,
      memberId: repository.memberId,
      collection: repository.collection,
    );
    final ordinary = _record;
    if (metadata.protected && ordinary is HtmlCreationRecord) {
      // Replace the ordinary journal before any protected raw request.
      _record = HtmlProtectedCreationRecord.seal(
        key: ordinary.key,
        memberId: ordinary.memberId,
        collection: ordinary.collection,
        edit: ordinary.edit,
        createdId: ordinary.createdId,
        candidateId: id,
      );
    }
    // Also retry a prior failed sealing/known-ID barrier before any raw read.
    await _persist();
    if (_closed) return;
    _checkOwner();
    final note = await notes.read(id, password: password);
    if (_closed) return;
    observed = note;
    _reviewed = false;
    recoveryFailure = null;
    _phase = RemoteHtmlCreationPhase.review;
  }

  Future<HtmlCreationCandidatePage> candidates({
    int page = 1,
    String keyword = '',
  }) async {
    _checkOwner();
    if (_busy ||
        !{
          RemoteHtmlCreationPhase.unknown,
          RemoteHtmlCreationPhase.review,
        }.contains(_phase)) {
      throw StateError('No uncertain creation to search');
    }
    final result = await repository.candidates(page: page, keyword: keyword);
    _checkOwner();
    return result;
  }

  Future<void> inspect(int id, {String? password}) async {
    if (_closed ||
        _busy ||
        !{
          RemoteHtmlCreationPhase.unknown,
          RemoteHtmlCreationPhase.review,
        }.contains(_phase)) {
      throw StateError('No creation candidate to inspect');
    }
    _busy = true;
    failure = null;
    observed = null;
    _reviewed = false;
    _notify();
    try {
      await _inspect(id, password: password);
    } catch (error) {
      if (!_closed) {
        failure = error;
        _phase = RemoteHtmlCreationPhase.unknown;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  bool _same(HtmlNote a, HtmlNote b) =>
      a.metadata.same(b.metadata) &&
      a.source == b.source &&
      a.labels.length == b.labels.length &&
      a.labels.toSet().containsAll(b.labels);
  void markReviewed(HtmlNote snapshot) {
    if (_busy || _closed || observed == null || !_same(snapshot, observed!)) {
      throw StateError('Review the complete current candidate');
    }
    _reviewed = true;
    _notify();
  }

  Future<void> adopt() async {
    if (_closed || _busy || !_reviewed || observed == null) {
      throw StateError('Full review required');
    }
    _busy = true;
    failure = null;
    _notify();
    try {
      final old = observed!;
      _checkOwner();
      final fresh = await notes.read(
        old.metadata.id,
        password: old.unlockPassword,
      );
      if (_closed) return;
      if (!_same(old, fresh)) {
        observed = fresh;
        _reviewed = false;
        return;
      }
      await _finish(fresh);
    } catch (error) {
      if (!_closed) failure = error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  bool get canFinishLabels =>
      !_closed &&
      !_busy &&
      _reviewed &&
      _phase == RemoteHtmlCreationPhase.review &&
      draft != null &&
      observed != null &&
      receiptId == observed!.metadata.id &&
      !observed!.metadata.protected &&
      draft!.sameContent(observed!) &&
      !draft!.matches(observed!);

  /// Only an acknowledged POST identity can finish its requested label bind.
  Future<void> finishLabels() async {
    if (!canFinishLabels) {
      throw StateError('Review acknowledged creation before finishing labels');
    }
    _checkOwner();
    _busy = true;
    failure = null;
    _notify();
    try {
      await _persist();
      _checkOwner();
      final outcome = await notes.finishLabels(
        HtmlSaveAttempt(
          baseline: observed!,
          edit: draft!,
          contentReceipt: true,
        ),
      );
      _checkOwner();
      observed = outcome.note;
      await _finish(outcome.note);
    } catch (error) {
      if (!_closed) {
        failure = error;
        _reviewed = false;
        _phase = RemoteHtmlCreationPhase.unknown;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> retryCleanup() async {
    if (_closed ||
        _busy ||
        _phase != RemoteHtmlCreationPhase.cleanup ||
        created == null) {
      throw StateError('No completed creation cleanup');
    }
    _busy = true;
    try {
      await _finish(created!);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> discardDraft() async {
    if (!canEdit) throw StateError('Pending creation cannot be discarded');
    try {
      _checkOwner();
      await vault.remove();
      return true;
    } catch (error) {
      recoveryFailure = error;
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    observed = null;
    created = null;
    notes.dispose();
    repository.dispose();
    super.dispose();
  }
}
