import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'html_notes_repository.dart';
import 'secure_record_store.dart';
import 'html_protected_creation_record.dart';

String newHtmlCreationKey() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
bool validHtmlCreationKey(String value) =>
    RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
String htmlCreationInputDigest(HtmlNoteEdit edit) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          edit.title,
          edit.source,
          [...edit.labels]..sort(),
        ]),
      ),
    )
    .toString();

/// Ordinary HTML only: this schema has no password/protected-content fields.
class HtmlCreationRecord {
  HtmlCreationRecord({
    required this.key,
    required this.memberId,
    required this.collection,
    required this.edit,
    required this.pending,
    this.createdId,
  }) {
    if (!validHtmlCreationKey(key) ||
        memberId <= 0 ||
        !{'note', 'article'}.contains(collection) ||
        createdId != null && (createdId! <= 0 || !pending) ||
        utf8.encode(edit.title).length > 4096 ||
        utf8.encode(edit.source).length > 5 * 1024 * 1024 ||
        edit.labels.length > 100 ||
        edit.labels.toSet().length != edit.labels.length ||
        edit.labels.any((v) => v.isEmpty) ||
        utf8.encode(jsonEncode(edit.labels)).length > 128 * 1024) {
      throw const FormatException('Invalid HTML creation draft');
    }
  }
  final String key, collection;
  final int memberId;
  final HtmlNoteEdit edit;
  final bool pending;
  final int? createdId;
  Map<String, Object?> toJson() => {
    'schema': 1,
    'key': key,
    'member_id': memberId,
    'collection': collection,
    'title': edit.title,
    'source': edit.source,
    'labels': edit.labels,
    'pending': pending,
    'created_id': createdId,
  };
  HtmlCreationRecord copy({
    HtmlNoteEdit? edit,
    bool? pending,
    int? createdId,
  }) => HtmlCreationRecord(
    key: key,
    memberId: memberId,
    collection: collection,
    edit: edit ?? this.edit,
    pending: pending ?? this.pending,
    createdId: createdId ?? this.createdId,
  );
  factory HtmlCreationRecord.parse(Object? value) {
    const keys = {
      'schema',
      'key',
      'member_id',
      'collection',
      'title',
      'source',
      'labels',
      'pending',
      'created_id',
    };
    if (value is! Map ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value.keys.length != keys.length ||
        value['schema'] != 1 ||
        value['key'] is! String ||
        value['member_id'] is! int ||
        value['collection'] is! String ||
        value['title'] is! String ||
        value['source'] is! String ||
        value['labels'] is! List ||
        (value['labels'] as List).any((v) => v is! String) ||
        value['pending'] is! bool ||
        value['created_id'] != null && value['created_id'] is! int) {
      throw const FormatException('Invalid HTML creation record');
    }
    return HtmlCreationRecord(
      key: value['key'] as String,
      memberId: value['member_id'] as int,
      collection: value['collection'] as String,
      edit: HtmlNoteEdit(
        title: value['title'] as String,
        source: value['source'] as String,
        labels: (value['labels'] as List).cast<String>(),
      ),
      pending: value['pending'] as bool,
      createdId: value['created_id'] as int?,
    );
  }
}

class HtmlCreationVault extends SecureRecordStore {
  HtmlCreationVault({
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
             ? 'bookstark.local-html-create.v1'
             : 'bookstark.html-create.v1',
         namespace: jsonEncode([
           BookstarkClient.normalizeServer(server.toString()).toString(),
           memberId,
           collection,
           'html',
           'new',
         ]),
       ) {
    if (memberId <= 0 || !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Owned HTML creation scope required');
    }
  }
  final int memberId;
  final String collection;
  static final _queues = <String, Future<void>>{};
  Future<T> _scoped<T>(Future<T> Function() work) => withMaintenance(() {
    final key = '$prefix:$namespace';
    final result = (_queues[key] ?? Future<void>.value()).then((_) => work());
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
  Future<HtmlCreationRecord?> read() async {
    final record = await readRecovery();
    if (record == null || record is HtmlCreationRecord) {
      return record as HtmlCreationRecord?;
    }
    throw const FormatException('Protected creation requires server recovery');
  }

  /// Server recovery must handle the hash-only variant before any unlock.
  Future<Object?> readRecovery() async {
    final raw = await readRecord('new');
    if (raw == null) return null;
    if (utf8.encode(raw).length > 64 * 1024 * 1024) {
      throw const FormatException('Oversized HTML creation record');
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['schema'] == 2) {
      final record = HtmlProtectedCreationRecord.parse(decoded);
      _protectedScope(record);
      return record;
    }
    final record = HtmlCreationRecord.parse(decoded);
    _scope(record);
    return record;
  }

  void _scope(HtmlCreationRecord record) {
    if (record.memberId != memberId || record.collection != collection) {
      throw const FormatException('HTML creation owner mismatch');
    }
  }

  Future<void> write(HtmlCreationRecord record) {
    _scope(record);
    return writeRecord('new', jsonEncode(record.toJson()));
  }

  void _protectedScope(HtmlProtectedCreationRecord record) {
    if (prefix != 'bookstark.html-create.v1' ||
        record.memberId != memberId ||
        record.collection != collection) {
      throw const FormatException('Protected server creation owner mismatch');
    }
  }

  Future<void> writeProtected(HtmlProtectedCreationRecord record) {
    _protectedScope(record);
    return writeRecord('new', jsonEncode(record.toJson()));
  }

  Future<void> remove() => removeRecord('new');
}
