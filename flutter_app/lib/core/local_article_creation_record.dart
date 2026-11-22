import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'complex_recovery_store.dart';
import 'local_complex_notes_repository.dart';
import 'local_data_maintenance.dart';
import 'local_article_creation_legacy_metadata.dart';

/// New local article identity, never a synthetic existing-note ID.
class LocalArticleCreationRecord {
  LocalArticleCreationRecord({
    required this.scope,
    required this.key,
    required this.edit,
    required this.pending,
    this.createdId,
    this.legacyBinding,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !validComplexCreationKey(key) ||
        edit.document.kind != ComplexEditorKind.markdown ||
        createdId != null && (createdId! <= 0 || !pending)) {
      throw const FormatException('Invalid local article creation identity');
    }
    validateDraft(edit);
  }
  static void validateDraft(ComplexNoteEdit edit) {
    if (edit.document.kind != ComplexEditorKind.markdown) {
      throw const FormatException('Article creation requires Markdown');
    }
    ComplexEditorDocument.validateText(edit.title);
    for (final label in edit.labels) {
      ComplexEditorDocument.validateText(label);
    }
    // Empty/whitespace titles are valid unfinished drafts, never valid INSERTs.
    if (utf8.encode(edit.title).length > 200 ||
        edit.labels.length > 100 ||
        edit.labels.toSet().length != edit.labels.length ||
        edit.labels.any((value) => value.isEmpty) ||
        utf8.encode(jsonEncode(edit.labels)).length > 60 * 1024) {
      throw const FormatException('Invalid local article creation draft');
    }
  }

  final String scope, key;
  final ComplexNoteEdit edit;
  final bool pending;
  final int? createdId;
  final LocalArticleCreationLegacyBinding? legacyBinding;
  LocalArticleCreationRecord copy({
    ComplexNoteEdit? edit,
    bool? pending,
    int? createdId,
  }) => LocalArticleCreationRecord(
    scope: scope,
    key: key,
    edit: edit ?? this.edit,
    pending: pending ?? this.pending,
    createdId: createdId ?? this.createdId,
    legacyBinding: legacyBinding,
  );
  bool sameInput(LocalArticleCreationRecord other) =>
      scope == other.scope &&
      key == other.key &&
      edit.title == other.edit.title &&
      edit.document.same(other.edit.document) &&
      jsonEncode(edit.labels) == jsonEncode(other.edit.labels) &&
      sameLegacyBinding(other);
  bool sameLegacyBinding(LocalArticleCreationRecord other) =>
      legacyBinding?.same(other.legacyBinding) ?? other.legacyBinding == null;

  Uint8List encode() {
    final metadata = utf8.encode(
      jsonEncode({
        'format': 1,
        'type': 'local-article-create-v1',
        'scope': scope,
        'key': key,
        'collection': 'article',
        'kind': 'markdown',
        'pending': pending,
        'createdId': createdId,
        'legacyBinding': legacyBinding?.toJson(),
        'title': edit.title,
        'labels': edit.labels,
        'sourceBytes': edit.document.byteLength,
        'sourceSHA256': edit.document.digest,
      }),
    );
    if (metadata.length > 128 * 1024) {
      throw const FormatException('Article creation metadata exceeds limit');
    }
    final head = ByteData(4)..setUint32(0, metadata.length, Endian.big);
    return (BytesBuilder(copy: false)
          ..add(head.buffer.asUint8List())
          ..add(metadata)
          ..add(utf8.encode(edit.document.source)))
        .takeBytes();
  }

  static LocalArticleCreationRecord decode(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes.length > NativeComplexRecoveryStore.maxBytes) {
      throw const FormatException('Invalid article creation byte limit');
    }
    final length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
    if (length < 1 || length > 128 * 1024 || length + 4 > bytes.length) {
      throw const FormatException('Invalid article creation metadata length');
    }
    final raw = jsonDecode(
      utf8.decode(
        Uint8List.sublistView(bytes, 4, 4 + length),
        allowMalformed: false,
      ),
    );
    const fields = {
      'format',
      'type',
      'scope',
      'key',
      'collection',
      'kind',
      'pending',
      'createdId',
      'legacyBinding',
      'title',
      'labels',
      'sourceBytes',
      'sourceSHA256',
    };
    if (raw is! Map ||
        raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['type'] != 'local-article-create-v1' ||
        raw['scope'] is! String ||
        raw['key'] is! String ||
        raw['collection'] != 'article' ||
        raw['kind'] != 'markdown' ||
        raw['pending'] is! bool ||
        raw['createdId'] != null && raw['createdId'] is! int ||
        raw['title'] is! String ||
        raw['labels'] is! List ||
        (raw['labels'] as List).any((v) => v is! String) ||
        raw['sourceBytes'] is! int ||
        raw['sourceSHA256'] is! String) {
      throw const FormatException('Invalid article creation metadata');
    }
    final document = ComplexEditorDocument.fromBytes(
      ComplexEditorKind.markdown,
      Uint8List.sublistView(bytes, 4 + length),
    );
    if (raw['sourceBytes'] != document.byteLength ||
        raw['sourceSHA256'] != document.digest) {
      throw const FormatException('Article creation source checksum mismatch');
    }
    return LocalArticleCreationRecord(
      scope: raw['scope'] as String,
      key: raw['key'] as String,
      edit: ComplexNoteEdit(
        title: raw['title'] as String,
        document: document,
        labels: (raw['labels'] as List).cast<String>(),
      ),
      pending: raw['pending'] as bool,
      createdId: raw['createdId'] as int?,
      legacyBinding: raw['legacyBinding'] == null
          ? null
          : LocalArticleCreationLegacyBinding.parse(raw['legacyBinding']),
    );
  }
}

/// One stable creation slot per owned repository scope. Pending input is sealed;
/// late cleanup cannot remove a different new creation.
class LocalArticleCreationVault {
  LocalArticleCreationVault({
    required this.scope,
    required this.store,
    this.maintenance,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw const FormatException('Invalid article creation scope');
    }
  }
  final String scope;
  final ComplexRecoveryBytesStore store;
  final LocalDataMaintenance? maintenance;
  Future<void>? _tail;
  String get metadataKey => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'bookstark.local-article-create.v1',
            scope,
            'article',
            'markdown',
          ]),
        ),
      )
      .toString();

  Future<T> _ordered<T>(Future<T> Function() action) {
    Future<T> run() => maintenance?.exclusive(action) ?? Future<T>.sync(action);
    final previous = _tail;
    final next = previous == null
        ? Future<T>.sync(run)
        : previous.then((_) => run());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _active() {
    if (maintenance?.retired == true) {
      throw StateError('Article creation storage scope retired');
    }
  }

  Future<LocalArticleCreationRecord?> _read() async {
    _active();
    final bytes = await store.read(metadataKey);
    _active();
    if (bytes == null) return null;
    final record = LocalArticleCreationRecord.decode(bytes);
    if (record.scope != scope) {
      throw const FormatException('Article creation belongs to another scope');
    }
    return record;
  }

  Future<LocalArticleCreationRecord?> read() => _ordered(_read);
  Future<void> write(LocalArticleCreationRecord record) => _ordered(() async {
    if (record.scope != scope) {
      throw const FormatException('Article creation belongs to another scope');
    }
    final old = await _read();
    if (old != null &&
        (old.key != record.key ||
            !old.sameLegacyBinding(record) ||
            old.pending && (!record.pending || !old.sameInput(record)) ||
            old.createdId != null && old.createdId != record.createdId)) {
      throw StateError('Existing article creation must be resolved first');
    }
    _active();
    await store.write(metadataKey, record.encode());
    _active();
  });

  /// Re-open editing only after a fresh absent ledger check under the same
  /// exclusive maintenance lease. A committed receipt is never discarded.
  Future<LocalArticleCreationRecord> resumeAfterAbsent(
    LocalArticleCreationRecord expected, {
    required Future<bool> Function() stillAbsent,
  }) => _ordered(() async {
    final old = await _read();
    if (old == null ||
        !old.pending ||
        old.createdId != null ||
        !old.sameInput(expected) ||
        expected.createdId != null) {
      throw StateError('Article creation no longer permits an absence review');
    }
    if (!await stillAbsent()) {
      throw StateError('Creation receipt exists; review its result first');
    }
    _active();
    final fresh = await _read();
    if (fresh == null ||
        !fresh.pending ||
        fresh.createdId != null ||
        !fresh.sameInput(old)) {
      throw StateError('Article creation changed during absence review');
    }
    final editable = old.copy(pending: false);
    await store.write(metadataKey, editable.encode());
    _active();
    return editable;
  });

  Future<void> remove({required String creationKey}) => _ordered(() async {
    if (!validComplexCreationKey(creationKey)) {
      throw const FormatException('Invalid article creation cleanup identity');
    }
    final old = await _read();
    if (old == null) return;
    if (old.key != creationKey) {
      throw StateError('A different article creation must not be removed');
    }
    _active();
    await store.remove(metadataKey);
    _active();
  });
}
