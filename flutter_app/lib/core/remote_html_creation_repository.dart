import 'dart:async';
import 'api_client.dart';
import 'html_notes_repository.dart';
import 'resource_labels.dart';
import 'html_creation_candidates.dart';

/// Failure carries the actual transport stage, never permission to replay POST.
class HtmlCreationUnresolved implements Exception {
  const HtmlCreationUnresolved({
    required this.submitted,
    this.receiptId,
    required this.cause,
  });
  final bool submitted;
  final int? receiptId;
  final Object cause;
}

/// One explicitly requested POST. There is no server idempotency guarantee.
/// Persisting the returned identity precedes every subsequent read or mutation.
class RemoteHtmlCreationRepository {
  RemoteHtmlCreationRepository(
    this.client, {
    required this.memberId,
    required this.collection,
  }) {
    if (memberId <= 0 || !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Owned HTML creation scope required');
    }
  }
  final BookstarkClient client;
  final int memberId;
  final String collection;
  final _stopped = Completer<void>();
  bool _busy = false;

  void _check(String session) {
    if (_stopped.isCompleted || client.exportSession()['token'] != session) {
      throw StateError('HTML creation owner session ended');
    }
  }

  Future<int> submit(
    HtmlNoteEdit edit, {
    required Future<void> Function(int id) persistReceipt,
  }) async {
    edit.validate();
    if (_busy || _stopped.isCompleted) {
      throw StateError('HTML creation is unavailable');
    }
    final session = client.exportSession()['token'];
    if (session == null || session.isEmpty) {
      throw StateError('HTML owner session required');
    }
    _busy = true;
    var submitted = false;
    int? receiptId;
    try {
      final owner = await client.profileSettingsJson(
        abortTrigger: _stopped.future,
      );
      _check(session);
      if (owner['member_id'] != memberId) {
        throw StateError('HTML creation owner changed');
      }
      receiptId = await client.createHtmlNote(
        memberId: memberId,
        collection: collection,
        title: edit.title,
        source: edit.source,
        labels: encodeResourceLabels(edit.labels),
        abortTrigger: _stopped.future,
        onSubmit: () {
          _check(session);
          submitted = true;
        },
      );
      // A changed owner must not resurrect a cleared journal after logout.
      // The unresolved result still retains the known ID for its active caller.
      _check(session);
      await persistReceipt(receiptId);
      _check(session);
      return receiptId;
    } catch (error) {
      throw HtmlCreationUnresolved(
        submitted: submitted,
        receiptId: receiptId,
        cause: error,
      );
    } finally {
      _busy = false;
    }
  }

  Future<HtmlCreationCandidatePage> candidates({
    int page = 1,
    String keyword = '',
  }) async {
    final session = client.exportSession()['token'];
    if (session == null || session.isEmpty) {
      throw StateError('HTML owner session required');
    }
    _check(session);
    final owner = await client.profileSettingsJson(
      abortTrigger: _stopped.future,
    );
    _check(session);
    if (owner['member_id'] != memberId) {
      throw StateError('HTML candidate owner changed');
    }
    final response = await client.htmlCreationCandidates(
      collection: collection,
      page: page,
      keyword: keyword,
      abortTrigger: _stopped.future,
    );
    _check(session);
    return HtmlCreationCandidatePage.parse(
      response,
      memberId: memberId,
      collection: collection,
      page: page,
    );
  }

  void dispose() {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}
