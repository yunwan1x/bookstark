import 'local_protected_content.dart';
import 'notes_repository.dart' show NoteLocked;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'bounded_note_text_reader.dart';
import 'html_notes_repository.dart';
import 'html_creation_vault.dart';
import 'local_store.dart';

/// Local HTML and labels commit together; remote CSV conventions never apply.
class LocalHtmlNotesRepository implements HtmlNotesRepository {
  LocalHtmlNotesRepository(
    this.store, {
    this.collection = 'note',
    this.isCurrentScope,
  }) {
    if (!{'note', 'article'}.contains(collection)) {
      throw ArgumentError.value(collection);
    }
  }
  final LocalStore store;
  final String collection;
  final bool Function()? isCurrentScope;
  bool _closed = false;
  @override
  bool get labelsUseCsv => false;
  void _check() {
    if (_closed) throw StateError('Local HTML editor is closed');
    try {
      if (isCurrentScope != null && !isCurrentScope!()) {
        throw StateError('Local HTML scope retired');
      }
    } catch (_) {
      throw StateError('Local HTML scope retired');
    }
  }

  Future<HtmlNote> _read(
    DatabaseExecutor db,
    int id,
  ) => store.maintenance.use(() async {
    _check();
    final rows = await db.rawQuery(
      'SELECT id,collection,editor_type,deleted,title,labels,updated_at,'
      'hex(substr(CAST(content AS BLOB),1,7)) AS protected_prefix '
      "FROM notes WHERE id = ? AND collection = ? AND editor_type = 'html' AND deleted = 0",
      [id, collection],
    );
    _check();
    if (rows.length != 1) throw StateError('Local HTML note no longer exists');
    final row = rows.single;
    if (isLocalProtectedEnvelopeHexPrefix(row['protected_prefix'])) {
      throw NoteLocked(id);
    }
    if (row['id'] != id ||
        row['collection'] != collection ||
        row['editor_type'] != 'html' ||
        row['deleted'] != 0 ||
        row['title'] is! String ||
        row['labels'] is! String ||
        row['updated_at'] is! int) {
      throw const FormatException('Invalid local HTML metadata');
    }
    final labels = jsonDecode(row['labels'] as String);
    if (labels is! List ||
        labels.any((v) => v is! String || v.isEmpty) ||
        labels.toSet().length != labels.length) {
      throw const FormatException('Invalid local HTML labels');
    }
    final stamp = row['updated_at'] as int;
    final source = await BoundedNoteTextReader.readNoteContent(
      db,
      id: id,
      collection: collection,
      editorType: 'html',
      // HtmlNoteEdit.validate currently defines the existing limit inline as
      // 5 * 1024 * 1024 bytes; keep the bounded read aligned with that limit.
      maxRecordBytes: 5 * 1024 * 1024,
    );
    _check();
    return HtmlNote(
      metadata: HtmlNoteMetadata(
        id: id,
        memberId: 1,
        collection: collection,
        title: row['title'] as String,
        version: stamp,
        modifiedAt: stamp,
        protected: false,
      ),
      source: source,
      labels: labels.cast<String>(),
    );
  });

  @override
  Future<HtmlNote> read(int id, {String? password}) =>
      store.maintenance.use(() async {
        _check();
        if (id <= 0 || password != null) {
          throw ArgumentError('Local HTML identity required');
        }
        final db = await store.database;
        return db.transaction((tx) => _read(tx, id));
      });

  Future<HtmlNote> create(HtmlNoteEdit edit) => store.maintenance.use(
    () async =>
        (await createOnce(edit, creationKey: newHtmlCreationKey())).note,
  );

  Future<HtmlNote?> _findCreation(DatabaseExecutor tx, String key) =>
      store.maintenance.use(() async {
        _check();
        final rows = await tx.query(
          'html_creation_receipts',
          where: 'creation_key = ?',
          whereArgs: [key],
        );
        if (rows.isEmpty) return null;
        if (rows.single['collection'] != collection) {
          throw StateError('Creation belongs to a different collection');
        }
        final id = rows.single['note_id'] as int;
        try {
          return await _read(tx, id);
        } on StateError {
          throw HtmlCreationTargetUnavailable(id);
        }
      });

  Future<HtmlNote?> findCreation(String key) => store.maintenance.use(() async {
    _check();
    if (!validHtmlCreationKey(key)) {
      throw const FormatException('Invalid HTML creation key');
    }
    return (await store.database).transaction((tx) => _findCreation(tx, key));
  });

  Future<LocalHtmlCreationOutcome> createOnce(
    HtmlNoteEdit edit, {
    required String creationKey,
  }) => store.maintenance.use(() async {
    _check();
    edit.validate(labelsAsCsv: false);
    if (isLocalProtectedEnvelopePrefix(edit.source)) {
      throw const FormatException(
        'ENC: is reserved for protected local content',
      );
    }
    if (!validHtmlCreationKey(creationKey)) {
      throw const FormatException('Invalid HTML creation key');
    }
    final digest = htmlCreationInputDigest(edit);
    return (await store.database).transaction((tx) async {
      _check();
      final ledger = await tx.query(
        'html_creation_receipts',
        where: 'creation_key = ?',
        whereArgs: [creationKey],
      );
      if (ledger.isNotEmpty) {
        if (ledger.single['collection'] != collection ||
            ledger.single['input_hash'] != digest) {
          throw StateError('Creation key is bound to different input');
        }
        final actual = (await _findCreation(tx, creationKey))!;
        if (!edit.matches(actual)) throw HtmlNoteConflict(actual);
        return LocalHtmlCreationOutcome(actual, inserted: false);
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      // Android SQLite binds String as UTF-16, consuming a leading BOM.
      // Bind exact UTF-8 bytes and cast inside SQLite to retain TEXT affinity
      // without losing source bytes. Reads use the bounded BLOB reader.
      _check();
      final id = await tx.rawInsert(
        'INSERT INTO notes '
        '(collection, editor_type, title, content, labels, updated_at) '
        "VALUES (?, 'html', CAST(? AS TEXT), CAST(? AS TEXT), ?, ?)",
        [
          collection,
          Uint8List.fromList(utf8.encode(edit.title)),
          Uint8List.fromList(utf8.encode(edit.source)),
          jsonEncode(edit.labels),
          stamp,
        ],
      );
      _check();
      await tx.insert('html_creation_receipts', {
        'creation_key': creationKey,
        'note_id': id,
        'collection': collection,
        'input_hash': digest,
        'created_at': stamp,
      });
      return LocalHtmlCreationOutcome(await _read(tx, id), inserted: true);
    });
  });

  @override
  Future<HtmlSaveOutcome> save(
    HtmlNote baseline,
    HtmlNoteEdit edit,
  ) => store.maintenance.use(() async {
    _check();
    edit.validate(labelsAsCsv: false);
    if (isLocalProtectedEnvelopePrefix(edit.source)) {
      throw const FormatException(
        'ENC: is reserved for protected local content',
      );
    }
    if (baseline.metadata.memberId != 1 ||
        baseline.metadata.collection != collection ||
        baseline.metadata.protected) {
      throw StateError('Local HTML baseline required');
    }
    final db = await store.database;
    return db.transaction((tx) async {
      final current = await _read(tx, baseline.metadata.id);
      if (!baseline.metadata.same(current.metadata) ||
          baseline.source != current.source ||
          baseline.labels.length != current.labels.length ||
          !baseline.labels.toSet().containsAll(current.labels)) {
        throw HtmlNoteConflict(current);
      }
      final stamp = math.max(
        DateTime.now().millisecondsSinceEpoch,
        current.metadata.version + 1,
      );
      // Keep the same exact-byte binding used by creation on Android.
      _check();
      final count = await tx.rawUpdate(
        'UPDATE notes SET title = CAST(? AS TEXT), content = CAST(? AS TEXT), '
        'labels = ?, updated_at = ? '
        "WHERE id = ? AND collection = ? AND editor_type = 'html' "
        'AND deleted = 0 AND updated_at = ?',
        [
          Uint8List.fromList(utf8.encode(edit.title)),
          Uint8List.fromList(utf8.encode(edit.source)),
          jsonEncode(edit.labels),
          stamp,
          baseline.metadata.id,
          collection,
          current.metadata.version,
        ],
      );
      if (count != 1) {
        throw StateError('Local HTML transaction baseline changed');
      }
      final actual = await _read(tx, baseline.metadata.id);
      final attempt = HtmlSaveAttempt(baseline: baseline, edit: edit);
      return HtmlSaveOutcome(
        actual,
        attempt.acknowledged(content: true, labels: attempt.requiresLabelWrite),
      );
    });
  });

  @override
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt) =>
      store.maintenance.use(
        () async => throw StateError(
          'Local HTML content and labels are atomic; verify the current note',
        ),
      );
  @override
  void dispose() => _closed = true;
}

class LocalHtmlCreationOutcome {
  const LocalHtmlCreationOutcome(this.note, {required this.inserted});
  final HtmlNote note;
  final bool inserted;
}

class HtmlCreationTargetUnavailable implements Exception {
  const HtmlCreationTargetUnavailable(this.id);
  final int id;
}
