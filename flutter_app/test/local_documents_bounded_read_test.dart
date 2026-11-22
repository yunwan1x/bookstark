// SQLite regression drafts. NOT RUN. FFI is not Android CursorWindow proof.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';

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
  Future<(LocalStore, LocalDocumentsRepository, int)> fixture() async {
    final root =
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
        Directory.systemTemp.path;
    final dir = await Directory(root).createTemp('docs12-bounded-');
    final store = LocalStore(
      path: '${dir.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    final book = await LocalBooksRepository(
      store,
    ).save(const BookItem(name: '测试书'));
    return (store, LocalDocumentsRepository(store), book);
  }

  test(
    'BLOB chunks preserve repeated BOM and emoji split at 256KiB boundary',
    () async {
      final (store, docs, book) = await fixture();
      final node = (await docs.tree(book)).single;
      final source =
          '\ufeff\ufeff${'a' * (262144 - 7)}🙂\r\n${'末尾\u0000\r\n' * 60000}';
      final db = await store.database;
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode(source)), node.id],
      );
      final read = await docs.readBounded(node.id, bookId: book);
      expect(read.source, source);
      expect(read.item.markdown, source);
      expect(read.byteLength, utf8.encode(source).length);
      expect(read.largeMarkdown, true);
      expect(
        (await docs.read(node.id)).markdown,
        source,
      ); // legacy method retained
      await expectLater(
        docs.saveMarkdown(node.id, 'replacement'),
        throwsA(isA<DocumentReadLimit>()),
      );
      expect((await docs.readBounded(node.id, bookId: book)).source, source);
    },
  );

  test(
    'tree/reorder metadata never requires body; overbudget read and removal mutate nothing',
    () async {
      final (store, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id;
      final db = await store.database;
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(zeroblob(?) AS TEXT) WHERE document_id=?',
        [documentReadMaxBytes + 1, id],
      );
      final beforeBook = await db.query('books');
      final beforeTrash = await db.query('trash_entries');
      expect((await docs.tree(book)).single.id, id);
      await expectLater(docs.read(id), throwsA(isA<DocumentReadLimit>()));
      await expectLater(docs.remove(id), throwsA(isA<DocumentReadLimit>()));
      expect(await db.query('books'), beforeBook);
      expect(await db.query('trash_entries'), beforeTrash);
      final row = (await db.rawQuery(
        'SELECT deleted,length(CAST(markdown AS BLOB)) AS bytes FROM documents WHERE document_id=?',
        [id],
      )).single;
      expect(row['deleted'], 0);
      expect(row['bytes'], documentReadMaxBytes + 1);
    },
  );

  test(
    'leaf trash captures all metadata and full bounded source before deletion',
    () async {
      final (store, docs, book) = await fixture();
      final id = (await docs.create(book, '保留全部字段')).id;
      const source = '\ufeff\ufeff原文🙂\r\nA\u0000B';
      await docs.saveMarkdown(id, source);
      final db = await store.database;
      final before = (await db.query(
        'documents',
        where: 'document_id=?',
        whereArgs: [id],
      )).single;
      await docs.remove(id);
      final trash = (await db.query(
        'trash_entries',
        where: "resource_type='document' AND resource_id=?",
        whereArgs: [id],
      )).single;
      final payload = jsonDecode(trash['payload'] as String) as Map;
      final snapshot = Map<String, Object?>.from(
        (payload['documents'] as List).single as Map,
      );
      // TEXT decoding by the SQLite host driver consumes one initial BOM.
      // Verify exact storage bytes separately, then compare every metadata field.
      final storedBytes = (await db.rawQuery(
        'SELECT CAST(markdown AS BLOB) AS source FROM documents WHERE document_id=?',
        [id],
      )).single['source'];
      expect(storedBytes, utf8.encode(source));
      expect(snapshot['markdown'], source);
      expect(
        {...snapshot}..remove('markdown'),
        {...before}..remove('markdown'),
      );
    },
  );

  test(
    'non-Markdown full source bounded read, wrong book and ENC reject',
    () async {
      final (store, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id;
      final db = await store.database;
      await db.rawUpdate(
        "UPDATE documents SET doc_type='html', markdown=CAST(? AS TEXT) WHERE document_id=?",
        [Uint8List.fromList(utf8.encode('\ufeff<p>原文🙂</p>\r\n')), id],
      );
      expect(
        (await docs.readBounded(id, bookId: book)).source,
        '\ufeff<p>原文🙂</p>\r\n',
      );
      await expectLater(
        docs.readBounded(id, bookId: book + 1),
        throwsStateError,
      );
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode('\ufeffENC:future:retained')), id],
      );
      final before = await db.query('trash_entries');
      await expectLater(docs.read(id), throwsA(isA<NoteLocked>()));
      await docs.remove(id);
      final trashRows = await db.query('trash_entries');
      expect(trashRows.length, before.length + 1);
      final payload = jsonDecode(trashRows.last['payload'] as String) as Map;
      expect(
        (payload['documents'] as List).single['markdown'],
        '\ufeffENC:future:retained',
      );
    },
  );
}
