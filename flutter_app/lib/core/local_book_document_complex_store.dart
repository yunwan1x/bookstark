import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_document_snapshot_reader.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;

class _BookDocumentSnapshot {
  _BookDocumentSnapshot(Map<String, Object?> metadata, this.source)
    : metadata = Map.unmodifiable(metadata);
  final Map<String, Object?> metadata;
  final String source;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'book-document-baseline-v1',
            metadata,
            sha256.convert(utf8.encode(source)).toString(),
          ]),
        ),
      )
      .toString();
}

/// Existing book document only. Never creates or accesses a notes row.
class LocalBookDocumentComplexStore implements ComplexNotesRepository {
  LocalBookDocumentComplexStore(
    this.store, {
    required this.bookId,
    required this.kind,
    required this.isCurrent,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 'local-book-document-complex-v1',
                 store.path,
                 bookId,
                 kind.name,
               ]),
             ),
           )
           .toString() {
    if (bookId <= 0 || kind == ComplexEditorKind.markdown) {
      throw ArgumentError('Existing complex book document required');
    }
  }
  final LocalStore store;
  final int bookId;
  @override
  final ComplexEditorKind kind;
  @override
  final String scope;
  @override
  String get collection => 'book-document';
  final bool Function() isCurrent;
  final DateTime Function() now;
  bool _closed = false;
  final _snapshots = Expando<_BookDocumentSnapshot>();
  void _check() {
    if (_closed || store.maintenance.retired || !isCurrent()) {
      throw StateError('Book document owner retired');
    }
  }

  Future<ComplexNote> _read(DatabaseExecutor tx, int id) async {
    _check();
    if (id <= 0) throw ArgumentError('Positive document ID required');
    final books = await tx.query(
      'books',
      columns: ['book_id'],
      where: 'book_id=? AND deleted=0',
      whereArgs: [bookId],
    );
    _check();
    if (books.length != 1) throw StateError('Book no longer active');
    final row = await LocalDocumentSnapshotReader.oneMetadata(tx, id);
    _check();
    if (row['book_id'] != bookId ||
        row['doc_type'] != kind.name ||
        row['deleted'] != 0) {
      throw StateError('Document identity/type changed');
    }
    final body = await LocalDocumentSnapshotReader.body(tx, row);
    _check();
    final document = ComplexEditorDocument.parse(kind, body.$1);
    final snapshot = _BookDocumentSnapshot(row, body.$1);
    final value = ComplexNote(
      scope: scope,
      id: id,
      collection: collection,
      title: row['document_name'] as String,
      document: document,
      version: 0,
      labels: const [],
      resourceFingerprint: snapshot.fingerprint,
    );
    _snapshots[value] = snapshot;
    return value;
  }

  @override
  Future<ComplexNote> read(int id) => store.maintenance.use(() async {
    _check();
    final db = await store.database;
    _check();
    final result = await db.transaction((tx) => _read(tx, id));
    _check();
    return result;
  });
  @override
  Future<ComplexNote> save(
    ComplexNote baseline,
    ComplexNoteEdit edit,
  ) => store.maintenance.use(() async {
    _check();
    final expected = _snapshots[baseline];
    if (expected == null ||
        baseline.scope != scope ||
        baseline.collection != collection ||
        baseline.document.kind != kind ||
        baseline.resourceFingerprint != expected.fingerprint ||
        edit.document.kind != kind ||
        edit.title != baseline.title ||
        edit.labels.isNotEmpty) {
      throw StateError('Body-only book-document baseline required');
    }
    // Existing document names may be legacy >200 bytes; no metadata edit or
    // note-specific title validation is applied to the preserved book title.
    final document = ComplexEditorDocument.parse(kind, edit.document.source);
    if (isLocalProtectedEnvelopePrefix(document.source)) {
      throw NoteLocked(baseline.id);
    }
    final db = await store.database;
    _check();
    final result = await db.transaction((tx) async {
      final actual = await _read(tx, baseline.id);
      _check();
      final observed = _snapshots[actual]!;
      if (jsonEncode(expected.metadata) != jsonEncode(observed.metadata) ||
          expected.source != observed.source ||
          !baseline.same(actual)) {
        throw ComplexNoteConflict(actual);
      }
      if (document.same(actual.document)) return actual;
      var modified = now().toUtc();
      if (modified.toIso8601String() == observed.metadata['modify_time']) {
        modified = modified.add(const Duration(microseconds: 1));
      }
      final count = await tx.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT),modify_time=? '
        'WHERE document_id=? AND book_id=? AND doc_type=? AND deleted=0',
        [
          Uint8List.fromList(utf8.encode(document.source)),
          modified.toIso8601String(),
          baseline.id,
          bookId,
          kind.name,
        ],
      );
      _check();
      if (count != 1) throw StateError('Document update receipt mismatch');
      final saved = await _read(tx, baseline.id);
      _check();
      if (saved.document.source != document.source) {
        throw StateError('Document save verification failed');
      }
      return saved;
    });
    _check();
    return result;
  });
  @override
  void dispose() {
    _closed = true;
  }
}
