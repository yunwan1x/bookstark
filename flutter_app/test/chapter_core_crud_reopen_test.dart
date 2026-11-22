import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });
  test('chapter core CRUD retains exact source and parent after database reopen', () async {
    final directory = await Directory.systemTemp.createTemp('chapter-core-');
    final path = '${directory.path}/content.db';
    LocalStore makeStore() => LocalStore(path: path, factory: databaseFactoryFfiNoIsolate);
    var store = makeStore();
    addTearDown(() async { await store.close(); await directory.delete(recursive: true); });
    final book = await LocalBooksRepository(store).save(const BookItem(name: 'Core book'));
    var documents = LocalDocumentsRepository(store);
    final parent = await documents.create(book, 'Parent');
    final chapter = await documents.create(book, 'Draft');
    const source = '\ufeff# Exact😀\r\n正文\r\n';
    await documents.saveMarkdown(chapter.id, source);
    await documents.rename(chapter.id, 'Saved chapter');
    await documents.move(book, chapter.id, parent.id);
    await store.close();
    store = makeStore();
    documents = LocalDocumentsRepository(store);
    final actual = await documents.read(chapter.id);
    expect(actual.id, chapter.id);
    expect(actual.name, 'Saved chapter');
    expect(actual.parentId, parent.id);
    expect(actual.markdown, source);
    expect((await LocalBooksRepository(store).read(book)).documentCount, 3);
    await documents.remove(chapter.id);
    await store.close();
    store = makeStore();
    await expectLater(LocalDocumentsRepository(store).read(chapter.id), throwsStateError);
    expect((await LocalBooksRepository(store).read(book)).documentCount, 2);
    expect((await LocalDocumentsRepository(store).read(parent.id)).name, 'Parent');
  });
}
