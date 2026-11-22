import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
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
  Future<LocalStore> testStore() async {
    final directory = await Directory.systemTemp.createTemp(
      'bookstark-documents-',
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
    'book initial document, full subtree navigation, clear body and transactional snapshots',
    () async {
      final store = await testStore();
      final books = LocalBooksRepository(store),
          docs = LocalDocumentsRepository(store);
      final book = await books.save(const BookItem(name: '书籍'));
      final initial = (await docs.tree(book)).single;
      expect(initial.name, '书籍');
      expect((await books.read(book)).documentCount, 1);
      final parent = await docs.create(book, '章节');
      final child = await docs.create(book, '子文档', parentId: parent.id);
      final grandchild = await docs.create(book, '孙文档', parentId: child.id);
      await docs.saveMarkdown(child.id, '# 需保留正文');
      await docs.rename(child.id, '改名');
      expect((await docs.read(child.id)).markdown, '# 需保留正文');
      expect((await docs.read(parent.id)).nextId, child.id);
      expect((await docs.read(grandchild.id)).previousId, child.id);
      await docs.saveMarkdown(child.id, '');
      expect((await docs.read(child.id)).markdown, '');
      await docs.saveMarkdown(grandchild.id, '**回收站正文**');
      await expectLater(docs.remove(parent.id), throwsStateError);
      await docs.remove(grandchild.id);
      await docs.remove(child.id);
      await docs.remove(parent.id);
      expect((await docs.tree(book)).single.id, initial.id);
      expect((await books.read(book)).documentCount, 1);
      final trash = (await (await store.database).query(
        'trash_entries',
        where: 'resource_id = ? AND resource_type = ?',
        whereArgs: [grandchild.id, 'document'],
      )).single;
      final payload = jsonDecode(trash['payload'] as String) as Map;
      final snapshots = payload['documents'] as List;
      expect(snapshots.length, 1);
      expect(
        snapshots.singleWhere(
          (row) => row['document_id'] == grandchild.id,
        )['markdown'],
        '**回收站正文**',
      );
      await expectLater(docs.read(child.id), throwsStateError);
      final retainedParent = await docs.create(book, '全书回收父章节');
      final retainedChild = await docs.create(
        book,
        '全书回收子文档',
        parentId: retainedParent.id,
      );
      await docs.saveMarkdown(retainedChild.id, '完整书籍快照正文');
      await books.remove(book);
      final bookTrash = (await (await store.database).query(
        'trash_entries',
        where: "resource_type = 'book'",
      )).single;
      final bookDocuments =
          (jsonDecode(bookTrash['payload'] as String) as Map)['documents']
              as List;
      expect(bookDocuments.length, 3);
      expect(
        bookDocuments.singleWhere(
          (row) => row['document_id'] == retainedChild.id,
        )['markdown'],
        '完整书籍快照正文',
      );
      await expectLater(docs.read(initial.id), throwsStateError);
    },
  );
  test(
    'document moves reject cycles/foreign parents; reorder survives reopen',
    () async {
      final store = await testStore();
      final books = LocalBooksRepository(store),
          docs = LocalDocumentsRepository(store);
      final book = await books.save(const BookItem(name: '第一本'));
      final other = await books.save(const BookItem(name: '另一本'));
      final foreign = (await docs.tree(other)).single.id;
      final a = await docs.create(book, 'A'), b = await docs.create(book, 'B');
      final child = await docs.create(book, 'child', parentId: a.id);
      await expectLater(docs.move(book, a.id, child.id), throwsStateError);
      await expectLater(docs.move(book, a.id, foreign), throwsStateError);
      await expectLater(
        docs.create(book, 'invalid', parentId: foreign),
        throwsStateError,
      );
      await docs.reorder(b.id, 'up');
      expect((await docs.tree(book))[1].id, b.id);
      await docs.reorder(a.id, 'indent');
      expect((await docs.read(a.id)).parentId, b.id);
      await docs.reorder(a.id, 'outdent');
      expect((await docs.read(a.id)).parentId, 0);
      await store.close();
      expect(
        flattenDocuments(await docs.tree(book)).map((node) => node.id),
        containsAll([a.id, b.id, child.id]),
      );
      final db = await store.database;
      await db.update(
        'documents',
        {'doc_type': 'drawing'},
        where: 'document_id = ?',
        whereArgs: [b.id],
      );
      await expectLater(docs.saveMarkdown(b.id, 'overwrite'), throwsStateError);
      expect((await docs.read(b.id)).markdown, '');
    },
  );
}
