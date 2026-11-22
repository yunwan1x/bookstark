import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
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
  Future<LocalStore> setup() async {
    final directory = await Directory.systemTemp.createTemp(
      'bookstark-bookmarks-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(
      path: '${directory.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(store.close);
    return store;
  }

  test(
    'local bookmark survives reopen with exact labels and duplicate confirmation',
    () async {
      final store = await setup();
      final repo = LocalBookmarksRepository(store);
      final id = await repo.save(
        const BookmarkItem(
          title: '书',
          url: 'https://a.test/',
          labels: ['a,b', ' 空格 '],
          favicon: 'keep.ico',
        ),
      );
      await store.close();
      final original = (await repo.findByUrl('https://a.test/'))!;
      expect(original.id, id);
      expect(original.labels, ['a,b', ' 空格 ']);
      await expectLater(
        repo.save(const BookmarkItem(title: '重复', url: 'https://a.test/')),
        throwsA(isA<BookmarkAlreadyExists>()),
      );
      await repo.batch(BookmarkBatch.pin, [id]);
      await repo.setNavVisible(id, true);
      await repo.save(original.copyWith(title: '改名'), original: original);
      final saved = (await repo.findByUrl('https://a.test/'))!;
      expect(saved.isPinned, isTrue);
      expect(saved.navVisible, isTrue);
      expect(saved.favicon, 'keep.ico');
      expect(await LocalLabelsRepository(store).search(''), [' 空格 ', 'a,b']);
      await repo.remove(id);
      expect(await repo.findByUrl('https://a.test/'), isNull);
      final trash = (await (await store.database).query(
        'trash_entries',
      )).single;
      expect(
        (jsonDecode(trash['payload'] as String) as Map)['bookmark']['labels'],
        jsonEncode(['a,b', ' 空格 ']),
      );
      expect(
        await repo.save(
          const BookmarkItem(title: '可重建', url: 'https://a.test/'),
        ),
        isNot(id),
      );
    },
  );
  test(
    'batch failures roll back all changes and filters use JSON names',
    () async {
      final store = await setup();
      final repo = LocalBookmarksRepository(store);
      final id = await repo.save(
        const BookmarkItem(
          title: '书',
          url: 'https://a.test/',
          labels: ['a,b', '白'],
        ),
      );
      await repo.save(const BookmarkItem(title: '其他', url: 'https://b.test/'));
      expect(
        (await repo.list(const BookmarkQuery(labels: ['a,b']))).items.single.id,
        id,
      );
      expect((await repo.list(const BookmarkQuery(noLabel: true))).total, 1);
      await expectLater(
        repo.batch(BookmarkBatch.delete, [id, 99999]),
        throwsStateError,
      );
      expect((await repo.list(const BookmarkQuery())).total, 2);
      expect(await (await store.database).query('trash_entries'), isEmpty);
      await repo.batch(BookmarkBatch.addLabels, [id], labels: ['a,b', '保留']);
      expect((await repo.findByUrl('https://a.test/'))!.labels, [
        'a,b',
        '白',
        '保留',
      ]);
      await repo.batch(BookmarkBatch.removeLabels, [id], labels: ['a,b']);
      expect((await repo.list(const BookmarkQuery(labels: ['a,b']))).total, 0);
      await expectLater(
        repo.list(const BookmarkQuery(scope: BookmarkScope.public)),
        throwsUnsupportedError,
      );
      await expectLater(
        repo.metadata('https://a.test/'),
        throwsUnsupportedError,
      );
    },
  );
  test('v6 upgrade preserves earlier tables and creates bookmarks', () async {
    final store = await setup();
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      store.path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          for (final table in ['notes', 'tasks', 'books', 'documents']) {
            await db.execute(
              'CREATE TABLE $table (id INTEGER PRIMARY KEY, content TEXT)',
            );
            await db.insert(table, {'id': 4, 'content': '保留$table'});
          }
        },
      ),
    );
    await old.close();
    final repo = LocalBookmarksRepository(store);
    await repo.save(const BookmarkItem(title: '书签', url: 'https://a.test/'));
    final db = await store.database;
    expect(await db.getVersion(), 16);
    for (final table in ['notes', 'tasks', 'books', 'documents']) {
      expect((await db.query(table)).single['content'], '保留$table');
    }
  });
}
