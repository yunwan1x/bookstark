import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory directory;
  late LocalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('webview-protected-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<String> snapshot() async {
    final db = await store.database;
    return jsonEncode([
      await db.rawQuery(
        'SELECT id,collection,editor_type,hex(CAST(title AS BLOB)) title,hex(CAST(content AS BLOB)) content,labels,updated_at,deleted FROM notes ORDER BY id',
      ),
      await db.query('html_creation_receipts', orderBy: 'creation_key'),
      await db.query('sqlite_sequence', orderBy: 'name'),
    ]);
  }

  Future<void> encrypt(int id, String source) async =>
      (await store.database).rawUpdate(
        'UPDATE notes SET content=CAST(? AS TEXT),updated_at=42 WHERE id=?',
        [utf8.encode(source), id],
      );

  test(
    'shared envelope rule reserves optional single BOM and unknown versions only at start',
    () {
      for (final source in [
        'ENC:',
        'ENC:v1:',
        'ENC:v2:',
        'ENC:future:',
        '\ufeffENC:v1:',
      ]) {
        expect(isLocalProtectedEnvelopePrefix(source), isTrue);
      }
      for (final source in [
        'prose ENC:v1:',
        '```\nENC:v1:',
        ' Enc:v1:',
        '\ufeffnormal',
      ]) {
        expect(isLocalProtectedEnvelopePrefix(source), isFalse);
      }
      expect(isLocalProtectedEnvelopeHexPrefix('454E433AFF'), isTrue);
      expect(isLocalProtectedEnvelopeHexPrefix('EFBBBF454E433A'), isTrue);
      expect(isLocalProtectedEnvelopeHexPrefix(''), isFalse);
    },
  );
  test(
    'all seven WebView kind reads refuse known unknown and BOM envelopes before parsing',
    () async {
      var sequence = 0;
      for (final kind in ComplexEditorKind.values) {
        final collection = kind == ComplexEditorKind.markdown
            ? 'article'
            : 'note';
        final repo = LocalComplexNotesRepository(
          store,
          kind: kind,
          collection: collection,
        );
        addTearDown(repo.dispose);
        for (final source in [
          'ENC:v1:opaque',
          'ENC:v2:opaque',
          'ENC:future:opaque',
          '\ufeffENC:bad',
        ]) {
          final id = await store.createNote(
            'Protected-${kind.name}-${sequence++}',
            source,
            collection: collection,
            labels: ['keep'],
          );
          await (await store.database).update(
            'notes',
            {'editor_type': kind.name},
            where: 'id=?',
            whereArgs: [id],
          );
          final before = await snapshot();
          await expectLater(
            repo.read(id),
            throwsA(isA<NoteLocked>().having((e) => e.id, 'id', id)),
          );
          expect(await snapshot(), before);
        }
      }
    },
  );
  test(
    'HTML read metadata source and stale transaction save never expose or overwrite ciphertext',
    () async {
      final repo = LocalHtmlNotesRepository(store);
      addTearDown(repo.dispose);
      final edit = HtmlNoteEdit(
        title: 'Keep',
        source: '\ufeff<p>plain😀</p>\r\n',
        labels: [' x '],
      );
      final baseline = await repo.createOnce(edit, creationKey: 'a' * 32);
      for (final source in [
        'ENC:v1:opaque',
        'ENC:unknown:bad',
        '\ufeffENC:v2:opaque',
      ]) {
        await encrypt(baseline.note.metadata.id, source);
        final before = await snapshot();
        await expectLater(
          repo.read(baseline.note.metadata.id),
          throwsA(isA<NoteLocked>()),
        );
        await expectLater(
          repo.save(baseline.note, edit),
          throwsA(isA<NoteLocked>()),
        );
        await expectLater(
          repo.findCreation('a' * 32),
          throwsA(isA<NoteLocked>()),
        );
        await expectLater(
          repo.createOnce(edit, creationKey: 'a' * 32),
          throwsA(isA<NoteLocked>()),
        );
        expect(await snapshot(), before);
      }
    },
  );
  test(
    'article WebView stale baseline and retained creation receipt cannot overwrite or recreate encrypted target',
    () async {
      final repo = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.markdown,
        collection: 'article',
      );
      addTearDown(repo.dispose);
      final edit = ComplexNoteEdit(
        title: 'Original',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          '\ufeff# plain😀\r\n',
        ),
        labels: [' x '],
      );
      final baseline = await repo.createOnce(edit, creationKey: 'b' * 32);
      await encrypt(baseline.note.id, '\ufeffENC:future:opaque');
      final before = await snapshot();
      await expectLater(
        repo.read(baseline.note.id),
        throwsA(isA<NoteLocked>()),
      );
      await expectLater(
        repo.save(baseline.note, edit),
        throwsA(isA<NoteLocked>()),
      );
      await expectLater(
        repo.findCreation('b' * 32),
        throwsA(isA<NoteLocked>()),
      );
      await expectLater(
        repo.createOnce(edit, creationKey: 'b' * 32),
        throwsA(isA<NoteLocked>()),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'HTML and Markdown WebView creation and proposed updates reject reserved input before mutation',
    () async {
      final html = LocalHtmlNotesRepository(store);
      addTearDown(html.dispose);
      final complex = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.markdown,
        collection: 'article',
      );
      addTearDown(complex.dispose);
      final oldHtml = await html.create(
        HtmlNoteEdit(title: 'Original', source: '<p>ok</p>', labels: []),
      );
      final oldComplex = (await complex.createOnce(
        ComplexNoteEdit(
          title: 'Article',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            'plain',
          ),
          labels: [],
        ),
        creationKey: 'c' * 32,
      )).note;
      for (final source in [
        'ENC:v1:opaque',
        'ENC:unknown:opaque',
        '\ufeffENC:v2:opaque',
      ]) {
        final htmlEdit = HtmlNoteEdit(
          title: 'Changed',
          source: source,
          labels: [],
        );
        final complexEdit = ComplexNoteEdit(
          title: 'Changed',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            source,
          ),
          labels: [],
        );
        final before = await snapshot();
        await expectLater(
          html.createOnce(htmlEdit, creationKey: 'd' * 32),
          throwsFormatException,
        );
        await expectLater(html.save(oldHtml, htmlEdit), throwsFormatException);
        await expectLater(
          complex.createOnce(complexEdit, creationKey: 'e' * 32),
          throwsFormatException,
        );
        await expectLater(
          complex.save(oldComplex, complexEdit),
          throwsFormatException,
        );
        expect(await snapshot(), before);
      }
      final normal = HtmlNoteEdit(
        title: 'BOM',
        source: '\ufeff<p>ENC:v1: is prose 😀</p>\r\n',
        labels: ['keep'],
      );
      final saved = await html.save(oldHtml, normal);
      expect(saved.note.source, normal.source);
      expect(saved.note.metadata.protected, isFalse);
    },
  );
  test(
    'malformed UTF8 ciphertext is refused using the bounded prefix before source decode',
    () async {
      final id = await store.createNote('Keep', 'plain');
      await (await store.database).execute(
        "UPDATE notes SET editor_type='html',content=CAST(X'454E433A7639393AFF' AS TEXT) WHERE id=$id",
      );
      final repo = LocalHtmlNotesRepository(store);
      addTearDown(repo.dispose);
      final complex = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.html,
      );
      addTearDown(complex.dispose);
      final before = await snapshot();
      await expectLater(repo.read(id), throwsA(isA<NoteLocked>()));
      await expectLater(complex.read(id), throwsA(isA<NoteLocked>()));
      expect(await snapshot(), before);
    },
  );
}
