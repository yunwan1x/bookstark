import 'resource_labels.dart';
import 'dart:async';
import 'dart:convert';
import 'api_client.dart';
import 'content_password_repository.dart' show validateContentPassword;

class HtmlNoteLocked implements Exception {
  const HtmlNoteLocked(this.id);
  final int id;
}

class HtmlNoteChanged implements Exception {
  const HtmlNoteChanged();
}

class HtmlNoteMetadata {
  const HtmlNoteMetadata({
    required this.id,
    required this.memberId,
    required this.collection,
    required this.title,
    required this.version,
    required this.modifiedAt,
    required this.protected,
  });
  final int id, memberId, version, modifiedAt;
  final String collection, title;
  final bool protected;

  factory HtmlNoteMetadata.parse(
    Map<String, Object?> row, {
    required int id,
    required int memberId,
    required String collection,
  }) {
    final title = row['blog_title'];
    final version = row['version'];
    final modified = row['modify_at'];
    final protected = row['has_password'];
    if (row['blog_id'] != id ||
        row['member_id'] != memberId ||
        row['blog_type'] != collection ||
        row['editor_type'] != 'html' ||
        row['blog_content'] != '' ||
        title is! String ||
        utf8.encode(title).length > 200 ||
        version is! int ||
        version < 0 ||
        modified is! int ||
        modified < 0 ||
        protected is! bool) {
      throw const FormatException('Invalid owned HTML note metadata');
    }
    return HtmlNoteMetadata(
      id: id,
      memberId: memberId,
      collection: collection,
      title: title,
      version: version,
      modifiedAt: modified,
      protected: protected,
    );
  }

  bool same(HtmlNoteMetadata other) =>
      id == other.id &&
      memberId == other.memberId &&
      collection == other.collection &&
      title == other.title &&
      version == other.version &&
      modifiedAt == other.modifiedAt &&
      protected == other.protected;
}

class HtmlNote {
  HtmlNote({
    required this.metadata,
    required this.source,
    required List<String> labels,
    this.unlockPassword,
  }) : labels = List.unmodifiable(labels);
  final HtmlNoteMetadata metadata;
  final String source;
  final List<String> labels;
  // Ephemeral editor state only. Never serialize into ordinary drafts.
  final String? unlockPassword;
}

bool _sameLabels(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);

void _wellFormed(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid HTML Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid HTML Unicode');
    }
  }
}

class HtmlNoteEdit {
  HtmlNoteEdit({
    required String title,
    required this.source,
    required List<String> labels,
  }) : title = title.trim(),
       labels = List.unmodifiable(labels);
  final String title, source;
  final List<String> labels;
  void validate({HtmlNote? baseline, bool labelsAsCsv = true}) {
    _wellFormed(title);
    _wellFormed(source);
    for (final label in labels) {
      _wellFormed(label);
    }
    if (title.isEmpty ||
        utf8.encode(title).length > 200 ||
        utf8.encode(source).length > 5 * 1024 * 1024 ||
        labels.length > 100 ||
        labels.toSet().length != labels.length ||
        labels.any((label) => label.isEmpty) ||
        utf8
                .encode(
                  !labelsAsCsv ||
                          baseline != null &&
                              _sameLabels(labels, baseline.labels)
                      ? labels.join(',')
                      : encodeResourceLabels(labels),
                )
                .length >
            60 * 1024) {
      throw const FormatException('Invalid HTML title, source or labels');
    }
  }

  bool sameContent(HtmlNote note) =>
      title == note.metadata.title && source == note.source;
  bool matches(HtmlNote note) =>
      sameContent(note) && _sameLabels(labels, note.labels);
}

class HtmlSaveAttempt {
  const HtmlSaveAttempt({
    required this.baseline,
    required this.edit,
    this.contentReceipt = false,
    this.labelsReceipt = false,
    this.contentObserved = false,
  });
  final HtmlNote baseline;
  final HtmlNoteEdit edit;
  final bool contentReceipt, labelsReceipt, contentObserved;
  bool get requiresLabelWrite => !_sameLabels(baseline.labels, edit.labels);
  HtmlSaveAttempt acknowledged({bool content = false, bool labels = false}) =>
      HtmlSaveAttempt(
        baseline: baseline,
        edit: edit,
        contentReceipt: contentReceipt || content,
        labelsReceipt: labelsReceipt || labels,
        contentObserved: contentObserved,
      );
  HtmlSaveAttempt observedContent() => HtmlSaveAttempt(
    baseline: baseline,
    edit: edit,
    contentReceipt: contentReceipt,
    labelsReceipt: labelsReceipt,
    contentObserved: true,
  );
}

class HtmlNoteConflict implements Exception {
  const HtmlNoteConflict(this.latest);
  final HtmlNote latest;
}

class HtmlSaveIncomplete implements Exception {
  const HtmlSaveIncomplete(this.attempt, {this.observed});
  final HtmlSaveAttempt attempt;
  final HtmlNote? observed;
}

class HtmlSaveOutcome {
  const HtmlSaveOutcome(this.note, this.attempt);
  final HtmlNote note;
  final HtmlSaveAttempt attempt;
  bool get allReceiptsKnown =>
      attempt.contentReceipt &&
      (!attempt.requiresLabelWrite || attempt.labelsReceipt);
}

abstract interface class HtmlNotesRepository {
  bool get labelsUseCsv;
  Future<HtmlNote> read(int id, {String? password});
  Future<HtmlSaveOutcome> save(HtmlNote baseline, HtmlNoteEdit edit);
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt);
  void dispose();
}

/// Read metadata/raw/labels as one checked baseline, without rendering or
/// transforming HTML. The server has no atomic snapshot/CAS API: a final
/// metadata and labels recheck detects observed changes, not all possible races.
class RemoteHtmlNotesRepository implements HtmlNotesRepository {
  RemoteHtmlNotesRepository(
    this.client, {
    required this.memberId,
    this.collection = 'note',
  }) {
    if (memberId <= 0 || !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Owned HTML collection required');
    }
  }
  @override
  bool get labelsUseCsv => true;
  final BookstarkClient client;
  final int memberId;
  final String collection;
  final _stopped = Completer<void>();
  bool _writing = false;

  void _check(String session) {
    if (_stopped.isCompleted || client.exportSession()['token'] != session) {
      throw StateError('HTML owner session ended');
    }
  }

  Future<HtmlNoteMetadata> _metadata(int id, String session) async {
    _check(session);
    final row = await client.htmlNoteMetadata(
      id,
      abortTrigger: _stopped.future,
    );
    _check(session);
    return HtmlNoteMetadata.parse(
      row,
      id: id,
      memberId: memberId,
      collection: collection,
    );
  }

  Future<List<String>> _labels(int id, String session) async {
    _check(session);
    final row = await client.htmlNoteLabels(id, abortTrigger: _stopped.future);
    _check(session);
    if (row['code'] != 0 || !row.containsKey('data')) {
      throw const FormatException('Missing HTML resource-label response');
    }
    // Go's nil []string is encoded as null for an unlabelled resource.
    final labels = row['data'] ?? const <String>[];
    if (labels is! List ||
        labels.any((label) => label is! String || label.isEmpty) ||
        labels.toSet().length != labels.length) {
      throw const FormatException('Invalid HTML resource labels');
    }
    return labels.cast<String>();
  }

  @override
  Future<HtmlNote> read(int id, {String? password}) async {
    if (id <= 0) throw const FormatException('Invalid HTML note ID');
    if (password != null) validateContentPassword(password);
    final session = client.exportSession()['token'];
    if (session == null || session.isEmpty) {
      throw StateError('HTML owner session required');
    }
    _check(session);
    final profile = await client.profileSettingsJson(
      abortTrigger: _stopped.future,
    );
    _check(session);
    if (profile['member_id'] != memberId) {
      throw StateError('HTML owner changed');
    }
    final before = await _metadata(id, session);
    if (before.protected && password == null) throw HtmlNoteLocked(id);
    final source = await client.blogHtmlSource(
      id,
      password: before.protected ? password : null,
      abortTrigger: _stopped.future,
    );
    _check(session);
    final labels = await _labels(id, session);
    final after = await _metadata(id, session);
    final lastLabels = await _labels(id, session);
    if (!before.same(after) ||
        labels.length != lastLabels.length ||
        !labels.toSet().containsAll(lastLabels)) {
      throw const HtmlNoteChanged();
    }
    _check(session);
    return HtmlNote(
      metadata: after,
      source: source,
      labels: lastLabels,
      unlockPassword: before.protected ? password : null,
    );
  }

  void _writeContext(HtmlNote baseline) {
    if (_stopped.isCompleted ||
        _writing ||
        baseline.metadata.id <= 0 ||
        baseline.metadata.memberId != memberId ||
        baseline.metadata.collection != collection) {
      throw StateError('HTML write context unavailable');
    }
    if (baseline.metadata.protected) {
      if (baseline.unlockPassword == null) {
        throw HtmlNoteLocked(baseline.metadata.id);
      }
      validateContentPassword(baseline.unlockPassword!);
    }
  }

  bool _sameBaseline(HtmlNote a, HtmlNote b) =>
      a.metadata.same(b.metadata) &&
      a.source == b.source &&
      _sameLabels(a.labels, b.labels);

  Future<void> _replaceLabels(HtmlSaveAttempt attempt, String session) async {
    _check(session);
    final receipt = await client.htmlNoteLabels(
      attempt.baseline.metadata.id,
      replacement: encodeResourceLabels(attempt.edit.labels),
      abortTrigger: _stopped.future,
    );
    final values = receipt['data'];
    // The real label endpoint returns the resulting []string, not a message.
    if (receipt['code'] != 0 ||
        !receipt.containsKey('data') ||
        values != null &&
            (values is! List || values.any((v) => v is! String))) {
      throw const FormatException('Missing HTML label replacement receipt');
    }
    final actual = values == null
        ? const <String>[]
        : (values as List).cast<String>();
    if (!_sameLabels(actual, attempt.edit.labels)) {
      throw const FormatException(
        'HTML label receipt differs from requested labels',
      );
    }
  }

  Future<HtmlSaveOutcome> _readSaved(HtmlSaveAttempt attempt) async {
    final actual = await read(
      attempt.baseline.metadata.id,
      password: attempt.baseline.unlockPassword,
    );
    if (!attempt.edit.matches(actual) ||
        actual.metadata.protected != attempt.baseline.metadata.protected) {
      throw HtmlSaveIncomplete(attempt, observed: actual);
    }
    return HtmlSaveOutcome(actual, attempt.observedContent());
  }

  @override
  Future<HtmlSaveOutcome> save(HtmlNote baseline, HtmlNoteEdit edit) async {
    edit.validate(baseline: baseline);
    _writeContext(baseline);
    _writing = true;
    var attempt = HtmlSaveAttempt(baseline: baseline, edit: edit);
    try {
      final actual = await read(
        baseline.metadata.id,
        password: baseline.unlockPassword,
      );
      if (!_sameBaseline(baseline, actual)) throw HtmlNoteConflict(actual);
      final session = client.exportSession()['token']!;
      _check(session);
      try {
        await client.updateHtmlNote(
          baseline.metadata.id,
          title: edit.title,
          source: edit.source,
          password: baseline.metadata.protected
              ? baseline.unlockPassword
              : null,
          abortTrigger: _stopped.future,
        );
      } on ApiFailure catch (error) {
        if ({400, 401, 403, 404, 409, 413, 422}.contains(error.status)) rethrow;
        throw HtmlSaveIncomplete(attempt);
      } catch (_) {
        throw HtmlSaveIncomplete(attempt);
      }
      attempt = attempt.acknowledged(content: true);
      try {
        _check(session);
        final intermediate = await read(
          baseline.metadata.id,
          password: baseline.unlockPassword,
        );
        if (!edit.sameContent(intermediate) ||
            intermediate.metadata.protected != baseline.metadata.protected ||
            !_sameLabels(intermediate.labels, baseline.labels) &&
                !_sameLabels(intermediate.labels, edit.labels)) {
          throw HtmlSaveIncomplete(attempt, observed: intermediate);
        }
        _check(session);
        if (attempt.requiresLabelWrite) {
          await _replaceLabels(attempt, session);
          attempt = attempt.acknowledged(labels: true);
        }
        _check(session);
        return await _readSaved(attempt);
      } on HtmlSaveIncomplete {
        rethrow;
      } catch (_) {
        throw HtmlSaveIncomplete(attempt);
      }
    } finally {
      _writing = false;
    }
  }

  /// An explicit recovery action after a content receipt. It never resends the
  /// content update, and verifies content/protection and intervening labels.
  @override
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt) async {
    attempt.edit.validate(baseline: attempt.baseline);
    _writeContext(attempt.baseline);
    if (!attempt.requiresLabelWrite ||
        (!attempt.contentReceipt && !attempt.contentObserved) ||
        attempt.labelsReceipt) {
      throw StateError(
        'Only acknowledged or explicitly observed content can resume labels',
      );
    }
    _writing = true;
    try {
      final actual = await read(
        attempt.baseline.metadata.id,
        password: attempt.baseline.unlockPassword,
      );
      if (!attempt.edit.sameContent(actual) ||
          actual.metadata.protected != attempt.baseline.metadata.protected ||
          !_sameLabels(actual.labels, attempt.baseline.labels) &&
              !_sameLabels(actual.labels, attempt.edit.labels)) {
        throw HtmlSaveIncomplete(attempt, observed: actual);
      }
      // A lost label receipt may already have applied: observe without resend.
      if (attempt.edit.matches(actual)) {
        return HtmlSaveOutcome(actual, attempt.observedContent());
      }
      final session = client.exportSession()['token']!;
      try {
        await _replaceLabels(attempt, session);
        attempt = attempt.acknowledged(labels: true);
        _check(session);
        return await _readSaved(attempt);
      } on HtmlSaveIncomplete {
        rethrow;
      } catch (_) {
        throw HtmlSaveIncomplete(attempt);
      }
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}
