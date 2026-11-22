import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
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
  late LocalNotesRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('notes-protected-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalNotesRepository(store);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<String> rows() async => jsonEncode(
    await (await store.database).rawQuery(
      'SELECT id,hex(CAST(title AS BLOB)) title,hex(CAST(content AS BLOB)) content,'
      'labels,collection,editor_type,deleted,updated_at FROM notes ORDER BY id',
    ),
  );
  for (final prefix in [
    'ENC:v1:',
    'ENC:v2:',
    'ENC:future:',
    'ENC:',
    '\ufeffENC:v1:',
    '\ufeffENC:future:',
  ]) {
    test(
      'stored $prefix is locked and rejects stale plain update without mutations',
      () async {
        final id = await repo.save(
          const Note(title: 'Original', content: 'plain', labels: ['keep']),
        );
        final snapshot = await repo.read(id);
        await (await store.database).rawUpdate(
          'UPDATE notes SET content=CAST(? AS TEXT),updated_at=123 WHERE id=?',
          [utf8.encode('$prefix opaque ciphertext'), id],
        );
        final before = await rows();
        await expectLater(
          repo.read(id),
          throwsA(isA<NoteLocked>().having((e) => e.id, 'id', id)),
        );
        await expectLater(
          repo.save(snapshot.copyWith(content: 'overwrite', labels: ['bad'])),
          throwsA(isA<NoteLocked>()),
        );
        expect(await rows(), before);
        final entries = await repo.listEntries();
        expect(entries.single.isProtected, isTrue);
        expect(entries.single.contentPreview, isEmpty);
        final list = await repo.list();
        expect(list.single.isProtected, isTrue);
        expect(list.single.content, isEmpty);
        expect(await rows(), before);
      },
    );
  }
  test(
    'malformed unknown envelope is refused before UTF8 body decoding',
    () async {
      final id = await store.createNote('Keep', 'plain');
      await (await store.database).execute(
        "UPDATE notes SET content=CAST(X'454E433A7639393AFF' AS TEXT),updated_at=51 WHERE id=$id",
      );
      final before = await rows();
      await expectLater(repo.read(id), throwsA(isA<NoteLocked>()));
      await expectLater(
        repo.save(Note(id: id, title: 'Changed', content: 'plain')),
        throwsA(isA<NoteLocked>()),
      );
      expect(await rows(), before);
    },
  );
  test(
    'large ciphertext never reaches normal full Markdown body reader',
    () async {
      final id = await store.createNote(
        'Keep',
        'ENC:v2:${'x' * (3 * 1024 * 1024)}',
      );
      final before = await rows();
      await expectLater(repo.read(id), throwsA(isA<NoteLocked>()));
      expect(await rows(), before);
    },
  );
  test(
    'ordinary creation and update reject reserved envelope payloads only at start',
    () async {
      await store.database;
      for (final content in [
        'ENC:v1:opaque',
        'ENC:unknown:opaque',
        '\ufeffENC:v2:opaque',
      ]) {
        final before = await rows();
        await expectLater(
          repo.save(Note(title: 'New', content: content)),
          throwsFormatException,
        );
        expect(await rows(), before);
      }
      final id = await repo.save(
        const Note(title: 'Plain', content: 'Discuss ENC:v1: as prose'),
      );
      final before = await rows();
      await expectLater(
        repo.save(Note(id: id, title: 'Changed', content: 'ENC:bad')),
        throwsFormatException,
      );
      expect(await rows(), before);
      await repo.save(
        Note(id: id, title: 'Normal', content: '```\nENC:v1:example\n```'),
      );
      expect((await repo.read(id)).content, contains('ENC:v1:example'));
    },
  );
  test(
    'current collection, deleted identity and editor type are checked inside update',
    () async {
      final id = await repo.save(const Note(title: 'Keep', content: 'plain'));
      final stale = await repo.read(id);
      final db = await store.database;
      for (final changes in [
        {'collection': 'article'},
        {'collection': 'note', 'deleted': 1},
        {'deleted': 0, 'editor_type': 'html'},
      ]) {
        await db.update('notes', changes, where: 'id=?', whereArgs: [id]);
        final before = await rows();
        await expectLater(
          repo.save(stale),
          throwsA(anyOf(isA<StateError>(), isA<DedicatedEditorRequired>())),
        );
        expect(await rows(), before);
      }
      await expectLater(
        repo.read(id),
        throwsA(
          isA<DedicatedEditorRequired>().having(
            (e) => e.editorType,
            'format',
            'html',
          ),
        ),
      );
    },
  );
  test(
    'ordinary title/body BOM, CRLF, labels and HTML routing remain exact',
    () async {
      final id = await repo.save(
        const Note(
          title: 'Normal',
          content: '\ufeff# 正文😀\r\n',
          labels: [' x '],
        ),
      );
      await repo.save(
        Note(
          id: id,
          title: '\ufeffTitle',
          content: '\ufeffUpdated😀\r\n',
          labels: ['new'],
        ),
      );
      final actual = await (await store.database).rawQuery(
        'SELECT hex(CAST(title AS BLOB)) title,hex(CAST(content AS BLOB)) content,labels FROM notes WHERE id=?',
        [id],
      );
      String hex(String value) => utf8
          .encode(value)
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      expect(actual.single['title'], hex('\ufeffTitle'));
      expect(actual.single['content'], hex('\ufeffUpdated😀\r\n'));
      expect((await repo.read(id)).content, '\ufeffUpdated😀\r\n');
      expect((await repo.read(id)).labels, ['new']);
      await (await store.database).update(
        'notes',
        {'editor_type': 'html'},
        where: 'id=?',
        whereArgs: [id],
      );
      final before = await rows();
      await expectLater(repo.read(id), throwsA(isA<DedicatedEditorRequired>()));
      expect(await rows(), before);
    },
  );
  test(
    'protected snapshot cannot be used as a local decryption authority',
    () async {
      final id = await store.createNote('Keep', 'plain');
      final before = await rows();
      await expectLater(
        repo.save(
          Note(
            id: id,
            title: 'Change',
            content: 'plain',
            isProtected: true,
            unlockPassword: 'secret',
          ),
        ),
        throwsA(isA<NoteLocked>()),
      );
      expect(await rows(), before);
    },
  );
}
