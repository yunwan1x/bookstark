// PREPARED ONLY; SQLite FFI is not Native WebView/secure-draft acceptance.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';

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
  test(
    'local complex note metadata save preserves exact body and every unrelated column',
    () async {
      final root =
          Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path;
      final directory = await Directory(
        root,
      ).createTemp('local-complex-note-metadata-');
      final store = LocalStore(
        path: '${directory.path}/db.sqlite',
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      const source =
          '{"elements":[],"future":{"exact":"保留 😀","spacing":"  "}}';
      final id = await store.createNote(
        'old title',
        source,
        labels: ['old', 'legacy,value'],
      );
      final db = await store.database;
      await db.execute('ALTER TABLE notes ADD COLUMN future_metadata TEXT');
      await db.update(
        'notes',
        {'editor_type': 'drawing', 'future_metadata': 'exact unknown metadata'},
        where: 'id=?',
        whereArgs: [id],
      );
      final repository = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.drawing,
      );
      addTearDown(repository.dispose);
      final baseline = await repository.read(id),
          before = (await db.query(
            'notes',
            where: 'id=?',
            whereArgs: [id],
          )).single;
      final saved = await repository.save(
        baseline,
        ComplexNoteEdit(
          title: 'new title',
          document: baseline.document,
          labels: ['new,tag', ' exact '],
        ),
      );
      final after = (await db.query(
        'notes',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(saved.title, 'new title');
      expect(saved.labels, ['new,tag', ' exact ']);
      expect(saved.document.source, source);
      expect(
        (await db.rawQuery(
          'SELECT CAST(content AS BLOB) AS bytes FROM notes WHERE id=?',
          [id],
        )).single['bytes'],
        utf8.encode(source),
      );
      expect(
        {...after}
          ..remove('title')
          ..remove('labels')
          ..remove('updated_at'),
        {...before}
          ..remove('title')
          ..remove('labels')
          ..remove('updated_at'),
      );
      expect(after['future_metadata'], 'exact unknown metadata');
    },
  );
}
