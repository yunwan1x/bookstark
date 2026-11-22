import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'html_notes_repository.dart';
import 'secure_record_store.dart';

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
List<String> _orderedLabels(List<String> labels) => [...labels]..sort();
String htmlContentFingerprint(HtmlNoteEdit edit, {required bool protected}) =>
    _digest([edit.title, edit.source, protected]);
String htmlLabelsFingerprint(List<String> labels) =>
    _digest(_orderedLabels(labels));
String htmlNoteFingerprint(HtmlNote note) => _digest([
  htmlContentFingerprint(
    HtmlNoteEdit(
      title: note.metadata.title,
      source: note.source,
      labels: note.labels,
    ),
    protected: note.metadata.protected,
  ),
  htmlLabelsFingerprint(note.labels),
]);

/// A protected note contributes only IDs and digests, never its title, HTML,
/// labels or unlock password. Pending operations restore as unknown receipts.
class HtmlRecoveryRecord {
  HtmlRecoveryRecord._({
    required this.id,
    required this.memberId,
    required this.collection,
    required this.protected,
    required this.pending,
    required this.baselineFingerprint,
    required this.contentFingerprint,
    required this.labelsFingerprint,
    this.baseline,
    this.edit,
  });
  factory HtmlRecoveryRecord.capture(
    HtmlNote baseline,
    HtmlNoteEdit edit, {
    required bool pending,
    bool everProtected = false,
  }) {
    final hidden =
        everProtected ||
        baseline.metadata.protected ||
        baseline.unlockPassword != null;
    if (hidden && !pending) {
      throw StateError('Protected drafts cannot be persisted');
    }
    return HtmlRecoveryRecord._(
      id: baseline.metadata.id,
      memberId: baseline.metadata.memberId,
      collection: baseline.metadata.collection,
      protected: hidden,
      pending: pending,
      baselineFingerprint: htmlNoteFingerprint(baseline),
      contentFingerprint: htmlContentFingerprint(
        edit,
        protected: baseline.metadata.protected,
      ),
      labelsFingerprint: htmlLabelsFingerprint(edit.labels),
      baseline: hidden ? null : baseline,
      edit: hidden ? null : edit,
    );
  }
  final int id, memberId;
  final String collection,
      baselineFingerprint,
      contentFingerprint,
      labelsFingerprint;
  final bool protected, pending;
  final HtmlNote? baseline;
  final HtmlNoteEdit? edit;
  bool matchesCurrent(HtmlNote actual) =>
      actual.metadata.id == id &&
      actual.metadata.memberId == memberId &&
      actual.metadata.collection == collection &&
      htmlContentFingerprint(
            HtmlNoteEdit(
              title: actual.metadata.title,
              source: actual.source,
              labels: actual.labels,
            ),
            protected: actual.metadata.protected,
          ) ==
          contentFingerprint &&
      htmlLabelsFingerprint(actual.labels) == labelsFingerprint;

  Map<String, Object?> _json() => {
    'version': 1,
    'id': id,
    'member_id': memberId,
    'collection': collection,
    'protected': protected,
    'pending': pending,
    'baseline_fingerprint': baselineFingerprint,
    'content_fingerprint': contentFingerprint,
    'labels_fingerprint': labelsFingerprint,
    if (!protected)
      'baseline': {
        'title': baseline!.metadata.title,
        'source': baseline!.source,
        'labels': baseline!.labels,
        'version': baseline!.metadata.version,
        'modified_at': baseline!.metadata.modifiedAt,
      },
    if (!protected)
      'edit': {
        'title': edit!.title,
        'source': edit!.source,
        'labels': edit!.labels,
      },
  };
}

class HtmlRecoveryVault extends SecureRecordStore {
  HtmlRecoveryVault({
    required Uri server,
    required this.memberId,
    required this.collection,
    bool localDatabase = false,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
    super.maintenance,
  }) : super(
         prefix: localDatabase
             ? 'bookstark.local-html-recovery.v1'
             : 'bookstark.html-recovery.v1',
         namespace: jsonEncode([
           BookstarkClient.normalizeServer(server.toString()).toString(),
           memberId,
           collection,
           'html',
         ]),
       ) {
    if (memberId <= 0 || !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Owned HTML recovery scope required');
    }
  }
  // Serialize across page/vault lifetimes to prevent late draft resurrection.
  static final Map<String, Future<void>> _queues = {};
  Future<T> _scoped<T>(Future<T> Function() work) => withMaintenance(() {
    final key = '$prefix:$namespace';
    final previous = _queues[key] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = tail;
    tail.then((_) {
      if (identical(_queues[key], tail)) _queues.remove(key);
    });
    return result;
  });

  @override
  Future<String?> readRecord(Object? id) => _scoped(() => super.readRecord(id));
  @override
  Future<void> writeRecord(Object? id, String value) =>
      _scoped(() => super.writeRecord(id, value));
  @override
  Future<void> removeRecord(Object? id) =>
      _scoped(() => super.removeRecord(id));
  final int memberId;
  final String collection;
  static const maxRecordBytes = 64 * 1024 * 1024;
  void _scope(HtmlRecoveryRecord record) {
    if (record.id <= 0 ||
        record.memberId != memberId ||
        record.collection != collection) {
      throw const FormatException('HTML recovery identity mismatch');
    }
  }

  Future<void> write(HtmlRecoveryRecord record) {
    _scope(record);
    if (!record.protected) {
      _boundedEdit(record.edit!);
      _boundedEdit(
        HtmlNoteEdit(
          title: record.baseline!.metadata.title,
          source: record.baseline!.source,
          labels: record.baseline!.labels,
        ),
      );
    }
    final value = jsonEncode(record._json());
    if (utf8.encode(value).length > maxRecordBytes) {
      throw const FormatException('HTML recovery exceeds record bound');
    }
    return writeRecord(record.id, value);
  }

  Future<HtmlRecoveryRecord?> read(int id) async {
    if (id <= 0) throw const FormatException('HTML recovery ID required');
    final raw = await readRecord(id);
    if (raw == null) return null;
    if (utf8.encode(raw).length > maxRecordBytes) {
      throw const FormatException('HTML recovery exceeds record bound');
    }
    final row = jsonDecode(raw);
    if (row is! Map ||
        row['version'] != 1 ||
        row['id'] is! int ||
        row['member_id'] is! int ||
        row['id'] != id ||
        row['member_id'] != memberId ||
        row['collection'] != collection ||
        row['protected'] is! bool ||
        row['pending'] is! bool ||
        [
          'baseline_fingerprint',
          'content_fingerprint',
          'labels_fingerprint',
        ].any(
          (key) =>
              row[key] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(row[key] as String),
        )) {
      throw const FormatException('Invalid HTML recovery record');
    }
    const keys = {
      'version',
      'id',
      'member_id',
      'collection',
      'protected',
      'pending',
      'baseline_fingerprint',
      'content_fingerprint',
      'labels_fingerprint',
      'baseline',
      'edit',
    };
    if (row.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unexpected HTML recovery fields');
    }
    final hidden = row['protected'] as bool;
    if (hidden &&
        (row['pending'] != true ||
            row.containsKey('baseline') ||
            row.containsKey('edit'))) {
      throw const FormatException('Protected recovery cannot contain drafts');
    }
    HtmlNote? baseline;
    HtmlNoteEdit? edit;
    if (!hidden) {
      final saved = row['baseline'];
      if (saved is! Map ||
          saved['version'] is! int ||
          saved['version'] < 0 ||
          saved['modified_at'] is! int ||
          saved['modified_at'] < 0) {
        throw const FormatException('Invalid HTML recovery baseline');
      }
      final baseEdit = _parseEdit(saved);
      edit = _parseEdit(row['edit']);
      baseline = HtmlNote(
        metadata: HtmlNoteMetadata(
          id: id,
          memberId: memberId,
          collection: collection,
          title: saved['title'] as String,
          version: saved['version'] as int,
          modifiedAt: saved['modified_at'] as int,
          protected: false,
        ),
        source: baseEdit.source,
        labels: baseEdit.labels,
      );
      if (htmlNoteFingerprint(baseline) != row['baseline_fingerprint'] ||
          htmlContentFingerprint(edit, protected: false) !=
              row['content_fingerprint'] ||
          htmlLabelsFingerprint(edit.labels) != row['labels_fingerprint']) {
        throw const FormatException('HTML recovery fingerprint mismatch');
      }
    }
    final record = HtmlRecoveryRecord._(
      id: id,
      memberId: memberId,
      collection: collection,
      protected: hidden,
      pending: row['pending'] as bool,
      baselineFingerprint: row['baseline_fingerprint'] as String,
      contentFingerprint: row['content_fingerprint'] as String,
      labelsFingerprint: row['labels_fingerprint'] as String,
      baseline: baseline,
      edit: edit,
    );
    _scope(record);
    return record;
  }

  Future<void> remove(int id) => removeRecord(id);
}

HtmlNoteEdit _parseEdit(Object? value) {
  if (value is! Map ||
      value['title'] is! String ||
      value['source'] is! String ||
      value['labels'] is! List ||
      (value['labels'] as List).any((v) => v is! String)) {
    throw const FormatException('Invalid HTML recovery draft');
  }
  final edit = HtmlNoteEdit(
    title: value['title'] as String,
    source: value['source'] as String,
    labels: (value['labels'] as List).cast<String>(),
  );
  _boundedEdit(edit);
  return edit;
}

void _boundedEdit(HtmlNoteEdit edit) {
  // Drafts may contain a temporarily empty/invalid title or label; normal save
  // validation still applies; source bytes remain unchanged.
  if (utf8.encode(edit.title).length > 4096 ||
      utf8.encode(edit.source).length > 5 * 1024 * 1024 ||
      edit.labels.length > 100 ||
      utf8.encode(jsonEncode(edit.labels)).length > 128 * 1024) {
    throw const FormatException('HTML recovery draft exceeds limits');
  }
}
