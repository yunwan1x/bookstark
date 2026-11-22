import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    'local book JSON labels survive reopen; uniqueness, literal search and trash snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-books-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(
        path: '${directory.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(store.close);
      final repo = LocalBooksRepository(store);
      final id = await repo.save(
        const BookItem(name: '100%_阅读', labels: ['a,b', ' 保留空白 ']),
      );
      await repo.save(const BookItem(name: '100普通书'));
      expect((await repo.list(keyword: '%_')).items.single.id, id);
      await expectLater(
        repo.save(const BookItem(name: '100%_阅读')),
        throwsA(isA<DatabaseException>()),
      );
      await store.close();
      final restored = await repo.read(id);
      expect(restored.labels, ['a,b', ' 保留空白 ']);
      expect(restored.identify, 'local-book-$id');
      await repo.save(restored.copyWith(description: '更改说明', labels: []));
      expect((await repo.read(id)).labels, isEmpty);
      await repo.remove(id);
      expect((await repo.list()).total, 1);
      final snapshot = (await (await store.database).query(
        'trash_entries',
      )).single;
      expect(snapshot['resource_type'], 'book');
      expect(
        (jsonDecode(snapshot['payload'] as String)
            as Map)['book']['description'],
        '更改说明',
      );
      await expectLater(repo.save(restored), throwsStateError);
    },
  );
  test('v4 upgrade preserves existing note and task rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bookstark-books-upgrade-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/data.db';
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE notes (id INTEGER PRIMARY KEY, content TEXT)',
          );
          await db.execute(
            'CREATE TABLE tasks (task_id INTEGER PRIMARY KEY, content TEXT)',
          );
          await db.insert('notes', {'id': 9, 'content': '保留笔记'});
          await db.insert('tasks', {'task_id': 41, 'content': '保留待办'});
        },
      ),
    );
    await old.close();
    final store = LocalStore(path: path, factory: databaseFactoryFfiNoIsolate);
    addTearDown(store.close);
    final db = await store.database;
    expect((await db.query('notes')).single['content'], '保留笔记');
    expect((await db.query('tasks')).single['task_id'], 41);
    expect((await LocalBooksRepository(store).list()).total, 0);
  });
}
