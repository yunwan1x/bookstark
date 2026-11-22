import 'local_protected_content.dart';
import 'notes_repository.dart' show NoteLocked;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'complex_editor_document.dart';
import 'local_store.dart';
import 'bounded_note_text_reader.dart';

class ComplexNote {
  ComplexNote({
    required this.scope,
    required this.id,
    required this.collection,
    required this.title,
    required this.document,
    required this.version,
    required List<String> labels,
    this.resourceFingerprint,
  }) : labels = List.unmodifiable(labels) {
    if (resourceFingerprint != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceFingerprint!)) {
      throw const FormatException('Invalid resource fingerprint');
    }
  }
  final int id, version;
  final String scope, collection, title;
  final String? resourceFingerprint;
  final ComplexEditorDocument document;
  final List<String> labels;
  bool same(ComplexNote other) =>
      scope == other.scope &&
      id == other.id &&
      collection == other.collection &&
      title == other.title &&
      version == other.version &&
      resourceFingerprint == other.resourceFingerprint &&
      document.same(other.document) &&
      jsonEncode(labels) == jsonEncode(other.labels);
}

class ComplexNoteEdit {
  ComplexNoteEdit({
    required this.title,
    required this.document,
    required List<String> labels,
  }) : labels = List.unmodifiable(labels);
  final String title;
  final ComplexEditorDocument document;
  final List<String> labels;
  void validate({
    bool bookDocumentBodyOnly = false,
    bool ownedRemoteBodyOnly = false,
  }) {
    ComplexEditorDocument.validateText(title);
    for (final label in labels) {
      ComplexEditorDocument.validateText(label);
    }
    if (ownedRemoteBodyOnly) {
      if (utf8.encode(title).length > 65536 ||
          labels.length > 100 ||
          utf8.encode(jsonEncode(labels)).length > 60 * 1024) {
        throw const FormatException('Invalid preserved owned-remote metadata');
      }
      return;
    }
    if (bookDocumentBodyOnly) {
      if (utf8.encode(title).length > 65536 || labels.isNotEmpty) {
        throw const FormatException('Invalid body-only book document metadata');
      }
      return;
    }
    if (title.trim().isEmpty ||
        utf8.encode(title).length > 200 ||
        labels.length > 100 ||
        labels.toSet().length != labels.length ||
        labels.any((l) => l.isEmpty) ||
        utf8.encode(jsonEncode(labels)).length > 60 * 1024) {
      throw const FormatException('Invalid complex document metadata');
    }
  }

  bool matches(ComplexNote note) =>
      title == note.title &&
      document.same(note.document) &&
      jsonEncode(labels) == jsonEncode(note.labels);
}

class ComplexNoteConflict implements Exception {
  const ComplexNoteConflict(this.actual);
  final ComplexNote actual;
}

bool validComplexCreationKey(String value) =>
    RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

String newComplexCreationKey() => List.generate(
  16,
  (_) => math.Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// Separate from the legacy HTML digest, including ordered labels and type.
String complexCreationInputDigest(
  ComplexEditorKind kind,
  String collection,
  ComplexNoteEdit edit,
) {
  edit.validate();
  if (edit.document.kind != kind ||
      !{'note', 'article'}.contains(collection) ||
      kind == ComplexEditorKind.markdown && collection != 'article') {
    throw const FormatException('Invalid complex creation input');
  }
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'local-complex-create-v1',
            kind.name,
            collection,
            edit.title,
            edit.labels,
            edit.document.byteLength,
            edit.document.digest,
          ]),
        ),
      )
      .toString();
}

class ComplexCreationOutcome {
  const ComplexCreationOutcome(this.note, {required this.inserted});
  final ComplexNote note;
  final bool inserted;
}

class ComplexCreationReceipt {
  const ComplexCreationReceipt({
    required this.noteId,
    required this.inputDigest,
    required this.note,
  });
  final int noteId;
  final String inputDigest;

  /// Null means the immutable receipt remains but its target is unavailable.
  final ComplexNote? note;
}

class ComplexCreationTargetUnavailable implements Exception {
  const ComplexCreationTargetUnavailable(this.id);
  final int id;
}

abstract interface class ComplexNotesCreationRepository {
  String get scope;
  String get collection;
  ComplexEditorKind get kind;
  Future<ComplexCreationOutcome> createOnce(
    ComplexNoteEdit edit, {
    required String creationKey,
  });
  Future<ComplexCreationReceipt?> findCreation(String key);
}

abstract interface class ComplexNotesRepository {
  String get scope;
  String get collection;
  ComplexEditorKind get kind;
  Future<ComplexNote> read(int id);
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit);
  void dispose();
}

/// Existing schema-v14 records. Type/source/title/labels share one transaction;
/// another format's Markdown/HTML update API is never used for structured data.
class LocalComplexNotesRepository
    implements ComplexNotesRepository, ComplexNotesCreationRepository {
  LocalComplexNotesRepository(
    this.store, {
    required this.kind,
    this.collection = 'note',
  }) : scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 'local-complex-v1',
                 store.path,
                 collection,
                 kind.name,
               ]),
             ),
           )
           .toString() {
    if (kind == ComplexEditorKind.markdown && collection != 'article') {
      throw ArgumentError('Markdown WebView repository is for articles only');
    }
    if (!{'note', 'article'}.contains(collection)) {
      throw ArgumentError.value(collection);
    }
  }
  final LocalStore store;
  @override
  final ComplexEditorKind kind;
  @override
  final String collection, scope;
  bool _closed = false;
  @override
  void dispose() {
    _closed = true;
  }

  void _check() {
    if (_closed) throw StateError('Complex document repository closed');
  }

  Future<ComplexNote> _read(
    DatabaseExecutor db,
    int id,
  ) => store.maintenance.use(() async {
    _check();
    // Raw byte chunks preserve BOM and stay below Android CursorWindow's
    // per-row allocation limit, including a full 20 MiB presentation.
    final rows = await db.rawQuery(
      'SELECT id,collection,editor_type,CAST(title AS BLOB) AS title_bytes,labels,updated_at, '
      'length(CAST(content AS BLOB)) AS source_bytes,'
      'hex(substr(CAST(content AS BLOB),1,7)) AS protected_prefix FROM notes '
      'WHERE id = ? AND collection = ? AND editor_type = ? AND deleted = 0',
      [id, collection, kind.name],
    );
    _check();
    if (rows.length != 1) throw StateError('Complex document no longer exists');
    final row = rows.single;
    if (isLocalProtectedEnvelopeHexPrefix(row['protected_prefix'])) {
      throw NoteLocked(id);
    }
    final length = row['source_bytes'];
    if (length is! int || length < 0 || length > kind.maxBytes) {
      throw const FormatException('Complex document exceeds byte limit');
    }
    final body = BytesBuilder(copy: false);
    for (var offset = 0; offset < length;) {
      _check();
      final count = math.min(262144, length - offset);
      final chunks = await db.rawQuery(
        'SELECT substr(CAST(content AS BLOB), ?, ?) AS source_chunk FROM notes '
        'WHERE id = ? AND collection = ? AND editor_type = ? AND deleted = 0',
        [offset + 1, count, id, collection, kind.name],
      );
      if (chunks.length != 1 ||
          chunks.single['source_chunk'] is! Uint8List ||
          (chunks.single['source_chunk'] as Uint8List).length != count) {
        throw StateError('Complex document byte read incomplete');
      }
      body.add(chunks.single['source_chunk'] as Uint8List);
      offset += count;
    }
    _check();
    final labels = jsonDecode(row['labels'] as String);
    if (labels is! List ||
        labels.any((l) => l is! String || l.isEmpty) ||
        labels.toSet().length != labels.length) {
      throw const FormatException('Invalid document labels');
    }
    return ComplexNote(
      scope: scope,
      id: id,
      collection: collection,
      title: BoundedNoteTextReader.decodeUtf8PreservingBom(
        row['title_bytes'] as Uint8List,
      ),
      document: ComplexEditorDocument.fromBytes(kind, body.takeBytes()),
      version: row['updated_at'] as int,
      labels: labels.cast<String>(),
    );
  });

  @override
  Future<ComplexNote> read(int id) => store.maintenance.use(() async {
    _check();
    if (id <= 0) throw ArgumentError.value(id);
    return (await store.database).transaction((tx) => _read(tx, id));
  });

  Future<ComplexCreationReceipt?> _creation(
    DatabaseExecutor tx,
    String key,
  ) async {
    _check();
    final rows = await tx.query(
      'html_creation_receipts',
      columns: ['note_id', 'collection', 'input_hash'],
      where: 'creation_key = ?',
      whereArgs: [key],
    );
    _check();
    if (rows.isEmpty) return null;
    if (rows.length != 1 || rows.single['collection'] != collection) {
      throw StateError('Creation receipt belongs to another collection');
    }
    final id = rows.single['note_id'];
    final digest = rows.single['input_hash'];
    if (id is! int ||
        id <= 0 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid complex creation receipt');
    }
    ComplexNote? note;
    try {
      note = await _read(tx, id);
    } on StateError {
      // A retained receipt must never turn a deleted/type-changed target into
      // permission to create again. Closed/retired repositories still fail.
      _check();
    }
    _check();
    return ComplexCreationReceipt(noteId: id, inputDigest: digest, note: note);
  }

  @override
  Future<ComplexCreationReceipt?> findCreation(String key) =>
      store.maintenance.use(() async {
        _check();
        if (!validComplexCreationKey(key)) {
          throw const FormatException('Invalid complex creation key');
        }
        return (await store.database).transaction((tx) => _creation(tx, key));
      });

  @override
  Future<ComplexCreationOutcome> createOnce(
    ComplexNoteEdit edit, {
    required String creationKey,
  }) => store.maintenance.use(() async {
    _check();
    if (!validComplexCreationKey(creationKey)) {
      throw const FormatException('Invalid complex creation key');
    }
    if (isLocalProtectedEnvelopePrefix(edit.document.source)) {
      throw const FormatException(
        'ENC: is reserved for protected local content',
      );
    }
    final inputDigest = complexCreationInputDigest(kind, collection, edit);
    return (await store.database).transaction((tx) async {
      final receipt = await _creation(tx, creationKey);
      if (receipt != null) {
        if (receipt.inputDigest != inputDigest) {
          throw StateError('Creation key is bound to different input');
        }
        final actual = receipt.note;
        if (actual == null) {
          throw ComplexCreationTargetUnavailable(receipt.noteId);
        }
        if (!edit.matches(actual)) throw ComplexNoteConflict(actual);
        return ComplexCreationOutcome(actual, inserted: false);
      }
      _check();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final id = await tx.rawInsert(
        'INSERT INTO notes '
        '(collection, editor_type, title, content, labels, updated_at) '
        'VALUES (?, ?, CAST(? AS TEXT), CAST(? AS TEXT), ?, ?)',
        [
          collection,
          kind.name,
          Uint8List.fromList(utf8.encode(edit.title)),
          Uint8List.fromList(utf8.encode(edit.document.source)),
          jsonEncode(edit.labels),
          stamp,
        ],
      );
      await tx.insert('html_creation_receipts', {
        'creation_key': creationKey,
        'note_id': id,
        'collection': collection,
        'input_hash': inputDigest,
        'created_at': stamp,
      });
      final actual = await _read(tx, id);
      _check();
      if (!edit.matches(actual)) {
        throw StateError('Complex creation transaction readback mismatch');
      }
      return ComplexCreationOutcome(actual, inserted: true);
    });
  });

  @override
  Future<ComplexNote> save(
    ComplexNote baseline,
    ComplexNoteEdit edit,
  ) => store.maintenance.use(() async {
    _check();
    edit.validate();
    if (isLocalProtectedEnvelopePrefix(edit.document.source)) {
      throw const FormatException(
        'ENC: is reserved for protected local content',
      );
    }
    if (baseline.scope != scope ||
        baseline.id <= 0 ||
        baseline.collection != collection ||
        baseline.document.kind != kind ||
        edit.document.kind != kind) {
      throw StateError('Complex document identity mismatch');
    }
    return (await store.database).transaction((tx) async {
      final actual = await _read(tx, baseline.id);
      if (!baseline.same(actual)) throw ComplexNoteConflict(actual);
      if (edit.matches(actual)) return actual;
      _check();
      final changed = await tx.rawUpdate(
        'UPDATE notes SET title=CAST(? AS TEXT),content=CAST(? AS TEXT),'
        'labels=?,updated_at=? '
        'WHERE id = ? AND collection = ? AND editor_type = ? AND deleted = 0 AND updated_at = ?',
        [
          Uint8List.fromList(utf8.encode(edit.title)),
          Uint8List.fromList(utf8.encode(edit.document.source)),
          jsonEncode(edit.labels),
          math.max(DateTime.now().millisecondsSinceEpoch, actual.version + 1),
          baseline.id,
          collection,
          kind.name,
          actual.version,
        ],
      );
      if (changed != 1) {
        throw StateError('Complex document transaction baseline changed');
      }
      final saved = await _read(tx, baseline.id);
      if (!edit.matches(saved)) {
        throw StateError('Complex document commit readback mismatch');
      }
      return saved;
    });
  });
}
