import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'dart:io';
import 'dart:ffi';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'local recent updates include notes, articles, books and live documents with typed IDs',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-home-recent-',
      );
      final store = LocalStore(
        path: '${directory.path}/home.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final note = await store.createNote('Note', 'body');
      final article = await store.createNote(
        'Article',
        'body',
        collection: 'article',
      );
      final books = LocalBooksRepository(store),
          docs = LocalDocumentsRepository(store);
      final book = await books.save(const BookItem(name: 'Book'));
      final initial = (await docs.tree(book)).single.id;
      final created = await docs.create(book, 'Actual document');
      await docs.remove(initial);
      final hiddenBook = await books.save(const BookItem(name: 'Hidden book'));
      final db = await store.database;
      await db.update(
        'books',
        {'deleted': 1},
        where: 'book_id = ?',
        whereArgs: [hiddenBook],
      );
      final stamp = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
      await db.update(
        'notes',
        {'updated_at': stamp + 1000},
        where: 'id = ?',
        whereArgs: [note],
      );
      await db.update(
        'notes',
        {'updated_at': stamp + 4000},
        where: 'id = ?',
        whereArgs: [article],
      );
      await db.update(
        'books',
        {'modify_time': '2026-01-01T00:00:02Z'},
        where: 'book_id = ?',
        whereArgs: [book],
      );
      await db.update(
        'documents',
        {'modify_time': '2026-01-01T00:00:03Z'},
        where: 'document_id = ?',
        whereArgs: [created.id],
      );
      final rows = (await store.homeSummary())['recent'] as List;
      expect(rows.map((row) => row['title']), [
        'Article',
        'Actual document',
        'Book',
        'Note',
      ]);
      expect(rows.map((row) => '${row['type']}/${row['id']}'), [
        'blog/$article',
        'document/${created.id}',
        'book/$book',
        'blog/$note',
      ]);
      expect(rows[1]['context'], 'Book');
      expect(rows[0]['modified_at'], stamp + 4000);
    },
  );

  test(
    'local notes survive closing and reopening without a Go process',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-local-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = '${directory.path}/notes.db';
      var store = LocalStore(path: file, factory: databaseFactoryFfiNoIsolate);
      final id = await store.createNote('阅读摘录', '# 标题\n离线内容');
      await store.updateNote(id, '更新后的摘录', '# 标题\n新的离线内容');
      await store.close();
      store = LocalStore(path: file, factory: databaseFactoryFfiNoIsolate);
      final notes = await store.notes();
      expect(notes.single['id'], id);
      expect(notes.single['title'], '更新后的摘录');
      expect(notes.single['content'], '# 标题\n新的离线内容');
      await store.createNote('100%进度', '第二条', labels: ['进度']);
      expect((await store.notes(keyword: '%')).single['title'], '100%进度');
      expect((await store.readNote(id))['content'], '# 标题\n新的离线内容');
      await store.deleteNote(id);
      expect(await store.notes(keyword: '摘录'), isEmpty);
      await expectLater(store.readNote(id), throwsStateError);
      await expectLater(store.updateNote(id, '覆盖', ''), throwsStateError);
      await store.close();
    },
  );
}
