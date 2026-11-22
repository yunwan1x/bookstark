import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
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
  late LocalComplexNotesRepository repository;
  const key = '11111111111111111111111111111111';
  ComplexNoteEdit edit({
    String title = '\ufeff阅读📚',
    String source = '\ufeff\ufeff# 阅读\r\n- 原文\r\n',
    List<String> labels = const ['z', 'a,b'],
  }) => ComplexNoteEdit(
    title: title,
    document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
    labels: labels,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('complex-create-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.markdown,
      collection: 'article',
    );
  });
  tearDown(() async {
    repository.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<List<Map<String, Object?>>> receipts() async =>
      (await store.database).query('html_creation_receipts');

  test(
    'atomic creation preserves UTF8 BOM CRLF labels and unrelated tables',
    () async {
      final db = await store.database;
      final sentinel = await store.createNote(
        'ordinary',
        'untouched',
        labels: ['legacy'],
        collection: 'note',
      );
      Future<Map<String, String>> otherTables() async => {
        for (final row in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        ))
          if (!{
            'notes',
            'html_creation_receipts',
            'sqlite_sequence',
            'android_metadata',
          }.contains(row['name']))
            row['name'] as String: jsonEncode(
              await db.query(row['name'] as String),
            ),
      };
      final before = await otherTables();
      final other = await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [sentinel],
      );
      final input = edit();
      final result = await repository.createOnce(input, creationKey: key);
      expect(result.inserted, isTrue);
      expect(input.matches(result.note), isTrue);
      final bytes = await db.rawQuery(
        'SELECT CAST(title AS BLOB) title, CAST(content AS BLOB) body FROM notes WHERE id = ?',
        [result.note.id],
      );
      expect(bytes.single['title'], utf8.encode(input.title));
      expect(bytes.single['body'], utf8.encode(input.document.source));
      expect(
        await db.query('notes', where: 'id = ?', whereArgs: [sentinel]),
        other,
      );
      expect(await otherTables(), before);
      final rows = await receipts();
      expect(rows, hasLength(1));
      expect(rows.single['note_id'], result.note.id);
      expect(
        rows.single['input_hash'],
        complexCreationInputDigest(repository.kind, 'article', input),
      );
    },
  );
  test(
    'same key and input returns exactly one original resource without updating',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      final second = await repository.createOnce(edit(), creationKey: key);
      expect(second.inserted, isFalse);
      expect(first.note.same(second.note), isTrue);
      expect(await receipts(), hasLength(1));
      expect(await (await store.database).query('notes'), hasLength(1));
    },
  );
  test(
    'same key changed source title or label order cannot create again',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      for (final input in [
        edit(source: 'changed'),
        edit(title: 'changed'),
        edit(labels: ['a,b', 'z']),
      ]) {
        await expectLater(
          repository.createOnce(input, creationKey: key),
          throwsStateError,
        );
      }
      expect((await repository.read(first.note.id)).same(first.note), isTrue);
      expect(await receipts(), hasLength(1));
    },
  );
  test(
    'deleted resource keeps receipt and can never be resurrected by retry',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      await (await store.database).delete(
        'notes',
        where: 'id = ?',
        whereArgs: [first.note.id],
      );
      final found = await repository.findCreation(key);
      expect(found!.noteId, first.note.id);
      expect(found.note, isNull);
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsA(isA<ComplexCreationTargetUnavailable>()),
      );
      expect(await (await store.database).query('notes'), isEmpty);
      expect(await receipts(), hasLength(1));
    },
  );
  test(
    'soft delete and format change retain unavailable creation identity',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      final db = await store.database;
      await db.update(
        'notes',
        {'deleted': 1},
        where: 'id = ?',
        whereArgs: [first.note.id],
      );
      expect((await repository.findCreation(key))!.note, isNull);
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsA(isA<ComplexCreationTargetUnavailable>()),
      );
      await db.update(
        'notes',
        {'deleted': 0, 'editor_type': 'html'},
        where: 'id = ?',
        whereArgs: [first.note.id],
      );
      expect((await repository.findCreation(key))!.note, isNull);
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsA(isA<ComplexCreationTargetUnavailable>()),
      );
      expect(await db.query('notes'), hasLength(1));
    },
  );
  test(
    'duplicate article title rolls back new receipt and inserted resource',
    () async {
      await repository.createOnce(edit(), creationKey: key);
      final before = await receipts();
      await expectLater(
        repository.createOnce(
          edit(),
          creationKey: '22222222222222222222222222222222',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await receipts(), before);
      expect(await (await store.database).query('notes'), hasLength(1));
    },
  );
  test(
    'changed created content is exposed for explicit review without overwrite',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      await (await store.database).update(
        'notes',
        {'content': 'changed later'},
        where: 'id = ?',
        whereArgs: [first.note.id],
      );
      final found = await repository.findCreation(key);
      expect(found!.note!.document.source, 'changed later');
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsA(isA<ComplexNoteConflict>()),
      );
      expect(
        (await repository.read(first.note.id)).document.source,
        'changed later',
      );
    },
  );
  test(
    'other collection and legacy HTML receipt digest cannot be adopted',
    () async {
      final first = await repository.createOnce(edit(), creationKey: key);
      final db = await store.database;
      await db.update(
        'html_creation_receipts',
        {'collection': 'note'},
        where: 'creation_key = ?',
        whereArgs: [key],
      );
      await expectLater(repository.findCreation(key), throwsStateError);
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsStateError,
      );
      await db.update(
        'html_creation_receipts',
        {'collection': 'article', 'input_hash': '0' * 64},
        where: 'creation_key = ?',
        whereArgs: [key],
      );
      await expectLater(
        repository.createOnce(edit(), creationKey: key),
        throwsStateError,
      );
      expect((await repository.read(first.note.id)).same(first.note), isTrue);
    },
  );
  test('invalid identity and metadata never write either table', () async {
    for (final bad in [
      '',
      'a' * 31,
      'A' * 32,
      '../aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ]) {
      await expectLater(
        repository.createOnce(edit(), creationKey: bad),
        throwsFormatException,
      );
    }
    await expectLater(
      repository.createOnce(edit(title: ''), creationKey: key),
      throwsFormatException,
    );
    expect(await (await store.database).query('notes'), isEmpty);
    expect(await receipts(), isEmpty);
  });
  test(
    'full 20MiB UTF8 article is read in bounded chunks without losing BOM',
    () async {
      const prefix = '\ufeff\ufeff# 阅读\r\n';
      final source =
          prefix + 'a' * (20 * 1024 * 1024 - utf8.encode(prefix).length);
      final result = await repository.createOnce(
        edit(source: source),
        creationKey: key,
      );
      expect(result.note.document.byteLength, 20 * 1024 * 1024);
      expect(result.note.document.source, source);
      expect(
        (await repository.findCreation(key))!.note!.document.source,
        source,
      );
    },
  );
}
