// Shared synthetic acceptance scenario; never imported by production routes.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';

const _body1 = '\ufeff# 原始🙂\r\nA\u0000B\r尾\n';
const _body2 = '\ufeff\ufeff# 修改🧩\r\nC\u0000D\r尾\n';
const _html1 = '\ufeff<!doctype html>\r\n<p>原始🙂</p>\n';
const _html2 = '\ufeff\ufeff<!doctype html>\r\n<p>修改🧩</p>\n';

void _require(bool value) {
  if (!value) throw StateError('Synthetic exact-text scenario mismatch');
}

Future<void> _bytes(
  DatabaseExecutor db,
  String table,
  String key,
  int id,
  String column,
  String expected,
) async {
  final row = (await db.rawQuery(
    'SELECT typeof("$column") AS t,CAST("$column" AS BLOB) AS b FROM "$table" WHERE "$key"=?',
    [id],
  )).single;
  final actual = row['b'];
  _require(
    row['t'] == 'text' &&
        actual is Uint8List &&
        sha256.convert(actual).toString() ==
            sha256.convert(utf8.encode(expected)).toString(),
  );
}

Future<Map<String, Object?>> localTextBytesScenario(
  LocalStore store, {
  required bool build,
}) async {
  final db = await store.database;
  final complex = LocalComplexNotesRepository(
    store,
    kind: ComplexEditorKind.html,
  );
  final html = LocalHtmlNotesRepository(store);
  final docs = LocalDocumentsRepository(store);
  try {
    if (build) {
      _require(
        (await db.query('notes')).isEmpty && (await db.query('books')).isEmpty,
      );
      final note = await store.createNote(
        '\ufeff标题🙂',
        _body1,
        labels: ['标签,🙂'],
      );
      _require(note == 1);
      _require((await store.readNote(note))['content'] == _body1);
      await _bytes(db, 'notes', 'id', note, 'content', _body1);
      await _bytes(db, 'notes', 'id', note, 'title', '\ufeff标题🙂');
      await store.updateNote(
        note,
        '\ufeff\ufeff修改🧩',
        _body2,
        labels: ['新,标签'],
      );
      final cid = await store.createNote('\ufeff复杂🙂', _html1);
      _require(cid == 2);
      await db.update(
        'notes',
        {'editor_type': 'html'},
        where: 'id=?',
        whereArgs: [cid],
      );
      final baseline = await complex.read(cid);
      _require(baseline.document.source == _html1);
      final saved = await complex.save(
        baseline,
        ComplexNoteEdit(
          title: '\ufeff\ufeff复杂🧩',
          document: ComplexEditorDocument.parse(ComplexEditorKind.html, _html2),
          labels: ['保留,字段'],
        ),
      );
      _require(saved.document.source == _html2);
      try {
        await complex.save(
          baseline,
          ComplexNoteEdit(
            title: 'stale',
            document: ComplexEditorDocument.parse(
              ComplexEditorKind.html,
              '<p>stale</p>',
            ),
            labels: const [],
          ),
        );
        throw StateError('Stale baseline accepted');
      } on ComplexNoteConflict {
        /* Required. */
      }
      final created = await html.createOnce(
        HtmlNoteEdit(title: 'HTML🙂', source: _html1, labels: const []),
        creationKey: newHtmlCreationKey(),
      );
      _require(created.note.metadata.id == 3 && created.note.source == _html1);
      await html.save(
        created.note,
        HtmlNoteEdit(title: 'HTML🧩', source: _html2, labels: const []),
      );
      final book = await LocalBooksRepository(
        store,
      ).save(const BookItem(name: '书籍'));
      final doc = (await docs.tree(book)).single;
      _require(doc.id == 1);
      await docs.saveMarkdown(doc.id, _body1);
      _require((await docs.read(doc.id)).markdown == _body1);
      await docs.saveMarkdown(doc.id, _body2);
    }
    final note = await store.readNote(1);
    _require(note['title'] == '\ufeff\ufeff修改🧩' && note['content'] == _body2);
    final cn = await complex.read(2);
    _require(
      cn.title == '\ufeff\ufeff复杂🧩' &&
          cn.document.source == _html2 &&
          cn.labels.single == '保留,字段',
    );
    _require((await html.read(3)).source == _html2);
    _require((await docs.read(1)).markdown == _body2);
    for (final id in [1, 2, 3]) {
      await _bytes(db, 'notes', 'id', id, 'content', id == 1 ? _body2 : _html2);
    }
    await _bytes(db, 'notes', 'id', 1, 'title', '\ufeff\ufeff修改🧩');
    await _bytes(db, 'notes', 'id', 2, 'title', '\ufeff\ufeff复杂🧩');
    await _bytes(db, 'documents', 'document_id', 1, 'markdown', _body2);
    _require(
      (await db.rawQuery('PRAGMA user_version')).single.values.single ==
          assistantActiveSchemaVersion,
    );
    _require(
      (await db.rawQuery('PRAGMA quick_check')).single.values.single == 'ok',
    );
    _require((await db.rawQuery('PRAGMA foreign_key_check')).isEmpty);
    return {
      'passed': true,
      'schema': assistantActiveSchemaVersion,
      'noteRows': 3,
      'documentRows': 1,
      'verifiedExactTextCells': 6,
      'staleComplexSaveRejected': build,
      'productionRepositoryAPIs': true,
      'bomCrLfNonBmpAndMarkdownNul': true,
      'bodySha256': sha256.convert(utf8.encode(_body2)).toString(),
      'htmlSha256': sha256.convert(utf8.encode(_html2)).toString(),
      'all45Complete': false,
    };
  } finally {
    complex.dispose();
    html.dispose();
  }
}
