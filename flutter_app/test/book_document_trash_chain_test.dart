// Whole-chain SQLite regression DRAFTS, NOT RUN during Native.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/local_trash_repository.dart';
import 'package:bookstark_flutter/core/local_document_snapshot_reader.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';

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
  Future<(LocalStore, LocalBooksRepository, LocalDocumentsRepository, int)>
  fixture() async {
    final root =
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
        Directory.systemTemp.path;
    final dir = await Directory(root).createTemp('book-trash-bounded-');
    final store = LocalStore(
      path: '${dir.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    final books = LocalBooksRepository(store),
        docs = LocalDocumentsRepository(store);
    final book = await books.save(
      const BookItem(name: '整书', labels: ['保留,字段']),
    );
    return (store, books, docs, book);
  }

  test(
    'whole book bounded source snapshot and restore preserve exact BOM/emoji IDs',
    () async {
      final (store, books, docs, book) = await fixture();
      final parent = await docs.create(book, '父'),
          child = await docs.create(book, '子', parentId: parent.id);
      final source =
          '\ufeff\ufeff${'a' * (262144 - 7)}🙂\r\n${'保留\u0000\r\n' * 180000}';
      final db = await store.database;
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode(source)), child.id],
      );
      final before = await docs.readBounded(child.id, bookId: book);
      await books.remove(book);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      final raw = await db.transaction(
        (tx) => LocalDocumentSnapshotReader.payload(tx, entry.id),
      );
      final snapshot = jsonDecode(raw) as Map;
      expect(
        (snapshot['documents'] as List).singleWhere(
          (row) => row['document_id'] == child.id,
        )['markdown'],
        source,
      );
      await trash.apply(entry, TrashOperation.restore);
      final after = await docs.readBounded(child.id, bookId: book);
      expect(after.source, before.source);
      expect(after.byteLength, before.byteLength);
      expect(after.item.parentId, parent.id);
      expect((await books.read(book)).documentCount, 3);
      expect((await books.read(book)).labels, ['保留,字段']);
      expect(await trash.isAbsent(entry), true);
    },
  );

  test(
    'late soft-delete SQL failure rolls back trash INSERT and all earlier flags',
    () async {
      final (store, books, docs, book) = await fixture();
      final last = await docs.create(book, '最后');
      final db = await store.database;
      final beforeBooks = await db.query('books'),
          beforeDocs = await db.query('documents');
      final beforeTrash = await db.query('trash_entries');
      await db.execute(
        "CREATE TRIGGER fail_book_last BEFORE UPDATE OF deleted ON documents WHEN NEW.document_id=${last.id} AND NEW.deleted=1 BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(books.remove(book), throwsA(anything));
      expect(await db.query('books'), beforeBooks);
      expect(await db.query('documents'), beforeDocs);
      expect(await db.query('trash_entries'), beforeTrash);
    },
  );

  test(
    'restore SQL failure rolls back book flag and leaves original payload bytes',
    () async {
      final (store, books, docs, book) = await fixture();
      final last = await docs.create(book, '最后');
      await docs.saveMarkdown(last.id, '\ufeff\ufeffbody🙂\r\n');
      await books.remove(book);
      final db = await store.database;
      final beforeBooks = await db.query('books'),
          beforeDocs = await db.query('documents');
      final beforeTrash = await db.query('trash_entries');
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      await db.execute(
        "CREATE TRIGGER fail_book_restore BEFORE UPDATE OF deleted ON documents WHEN NEW.document_id=${last.id} AND NEW.deleted=0 BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(
        trash.apply(entry, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await db.query('books'), beforeBooks);
      expect(await db.query('documents'), beforeDocs);
      expect(await db.query('trash_entries'), beforeTrash);
    },
  );

  test(
    'orphan, internal cycle and cross-book reverse children refuse book removal',
    () async {
      for (final kind in ['orphan', 'cycle', 'foreign']) {
        final (store, books, docs, book) = await fixture();
        final parent = await docs.create(book, '父'),
            child = await docs.create(book, '子', parentId: parent.id);
        final db = await store.database;
        if (kind == 'orphan') {
          await db.update(
            'documents',
            {'parent_id': 999999},
            where: 'document_id=?',
            whereArgs: [parent.id],
          );
        }
        if (kind == 'cycle') {
          await db.update(
            'documents',
            {'parent_id': child.id},
            where: 'document_id=?',
            whereArgs: [parent.id],
          );
        }
        if (kind == 'foreign') {
          final other = await books.save(const BookItem(name: '另一本'));
          final foreign = (await docs.tree(other)).single.id;
          await db.update(
            'documents',
            {'parent_id': parent.id},
            where: 'document_id=?',
            whereArgs: [foreign],
          );
        }
        final beforeBooks = await db.query('books'),
            beforeDocs = await db.query('documents');
        await expectLater(books.remove(book), throwsA(anything));
        expect(await db.query('books'), beforeBooks);
        expect(await db.query('documents'), beforeDocs);
        expect(await db.query('trash_entries'), isEmpty);
      }
    },
  );

  test(
    'JSON escaping budget refusal leaves original active source untouched',
    () async {
      final (store, books, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id, db = await store.database;
      // 6MiB NUL source is within20MiB, encoded JSON exceeds32MiB.
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(zeroblob(?) AS TEXT) WHERE document_id=?',
        [6 * 1024 * 1024, id],
      );
      await expectLater(
        books.remove(book),
        throwsA(isA<LocalTrashPayloadLimit>()),
      );
      expect(
        (await db.query(
          'books',
          columns: ['deleted'],
          where: 'book_id=?',
          whereArgs: [book],
        )).single['deleted'],
        0,
      );
      expect(
        (await db.query(
          'documents',
          columns: ['deleted'],
          where: 'document_id=?',
          whereArgs: [id],
        )).single['deleted'],
        0,
      );
      expect(await db.query('trash_entries'), isEmpty);
      expect(
        (await db.rawQuery(
          'SELECT length(CAST(markdown AS BLOB)) AS n FROM documents WHERE document_id=?',
          [id],
        )).single['n'],
        6 * 1024 * 1024,
      );
    },
  );

  test(
    'old-format payload above8Mi UTF16 restores through new bounded consumer',
    () async {
      final (store, books, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id, db = await store.database;
      final source = 'a' * (9 * 1024 * 1024);
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode(source)), id],
      );
      await books.remove(book);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      final raw = await db.transaction(
        (tx) => LocalDocumentSnapshotReader.payload(tx, entry.id),
      );
      expect(raw.length, greaterThan(8 * 1024 * 1024));
      expect((jsonDecode(raw) as Map)['version'], 1);
      await trash.apply(entry, TrashOperation.restore);
      expect((await docs.readBounded(id, bookId: book)).source, source);
    },
  );

  test(
    'independent prior document trash retained; permanent book delete cannot orphan it',
    () async {
      final (store, books, docs, book) = await fixture();
      final parent = (await docs.tree(book)).single.id;
      final child = await docs.create(book, '先回收', parentId: parent);
      await docs.saveMarkdown(child.id, '独立原文🙂');
      await docs.remove(child.id);
      final db = await store.database;
      final original = (await db.query('trash_entries')).single;
      await books.remove(book);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      await expectLater(
        trash.apply(entry, TrashOperation.delete),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(
        (await db.query(
          'trash_entries',
          where: 'trash_id=?',
          whereArgs: [original['trash_id']],
        )).single,
        original,
      );
      expect(
        (await db.query(
          'books',
          columns: ['deleted'],
          where: 'book_id=?',
          whereArgs: [book],
        )).single['deleted'],
        1,
      );
      await trash.apply(entry, TrashOperation.restore);
      expect(
        (await db.query(
          'trash_entries',
          where: 'trash_id=?',
          whereArgs: [original['trash_id']],
        )).single,
        original,
      );
      expect(
        (await db.query(
          'documents',
          columns: ['deleted'],
          where: 'document_id=?',
          whereArgs: [child.id],
        )).single['deleted'],
        1,
      );
      expect(
        (await db.query(
          'documents',
          columns: ['deleted'],
          where: 'document_id=?',
          whereArgs: [parent],
        )).single['deleted'],
        0,
      );
      expect(await trash.isAbsent(entry), true);
      final childEntry = (await trash.read(
        type: 'document',
      )).entries.singleWhere((item) => item.id == original['trash_id']);
      await trash.apply(childEntry, TrashOperation.restore);
      expect((await docs.read(child.id)).markdown, '独立原文🙂');
      expect((await docs.read(child.id)).parentId, parent);
    },
  );

  test('source budget refuses before trash creation', () async {
    final (store, books, docs, book) = await fixture();
    final id = (await docs.tree(book)).single.id, db = await store.database;
    await db.rawUpdate(
      'UPDATE documents SET markdown=CAST(zeroblob(?) AS TEXT) WHERE document_id=?',
      [documentReadMaxBytes + 1, id],
    );
    await expectLater(books.remove(book), throwsA(isA<DocumentReadLimit>()));
    expect(await db.query('trash_entries'), isEmpty);
    expect(
      (await db.query(
        'documents',
        columns: ['deleted'],
        where: 'document_id=?',
        whereArgs: [id],
      )).single['deleted'],
      0,
    );
  });
  test(
    'changed deleted body refuses restoration without rewriting old payload',
    () async {
      final (store, books, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id;
      await docs.saveMarkdown(id, 'original');
      await books.remove(book);
      final db = await store.database;
      final original = (await db.query('trash_entries')).single;
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode('changed')), id],
      );
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      await expectLater(
        trash.apply(entry, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect((await db.query('trash_entries')).single, original);
      expect(
        (await db.query(
          'books',
          columns: ['deleted'],
          where: 'book_id=?',
          whereArgs: [book],
        )).single['deleted'],
        1,
      );
    },
  );

  test(
    'retained cipher is snapshotted/restored exact without entering plaintext reader',
    () async {
      final (store, books, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id, db = await store.database;
      const cipher = '\ufeffENC:future:exact_cipher_bytes';
      await db.rawUpdate(
        'UPDATE documents SET markdown=CAST(? AS TEXT) WHERE document_id=?',
        [Uint8List.fromList(utf8.encode(cipher)), id],
      );
      await books.remove(book);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      final raw = await db.transaction(
        (tx) => LocalDocumentSnapshotReader.payload(tx, entry.id),
      );
      expect(
        ((jsonDecode(raw) as Map)['documents'] as List).single['markdown'],
        cipher,
      );
      await trash.apply(entry, TrashOperation.restore);
      await expectLater(docs.read(id), throwsA(anything)); // remains locked
      final rows = await db.rawQuery(
        'SELECT hex(CAST(markdown AS BLOB)) AS bytes FROM documents WHERE document_id=?',
        [id],
      );
      expect(
        rows.single['bytes'],
        utf8
            .encode(cipher)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase(),
      );
    },
  );

  test(
    'permanent parent deletion cannot strand separately retained child snapshot',
    () async {
      final (store, books, docs, book) = await fixture();
      final parent = await docs.create(book, '父'),
          child = await docs.create(book, '子', parentId: parent.id);
      await docs.remove(child.id);
      await docs.remove(parent.id);
      final db = await store.database, before = await db.query('trash_entries');
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final parentEntry = (await trash.read(
        type: 'document',
      )).entries.singleWhere((entry) => entry.name == '父');
      await expectLater(
        trash.apply(parentEntry, TrashOperation.delete),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await db.query('trash_entries'), before);
    },
  );
  test('oversized existing payload is retained with all flags unchanged', () async {
    final (store, books, docs, book) = await fixture();
    await books.remove(book);
    final db = await store.database;
    final entryId =
        (await db.query(
              'trash_entries',
              columns: ['trash_id'],
            )).single['trash_id']
            as int;
    await db.rawUpdate(
      'UPDATE trash_entries SET payload=CAST(zeroblob(?) AS TEXT) WHERE trash_id=?',
      [localTrashPayloadMaxBytes + 1, entryId],
    );
    final trash = LocalTrashRepository(store);
    addTearDown(trash.dispose);
    final entry = (await trash.read(type: 'book')).entries.single;
    await expectLater(
      trash.apply(entry, TrashOperation.restore),
      throwsA(isA<TrashPreflightFailure>()),
    );
    final retained = (await db.rawQuery(
      'SELECT length(CAST(payload AS BLOB)) AS bytes FROM trash_entries WHERE trash_id=?',
      [entryId],
    )).single;
    expect(retained['bytes'], localTrashPayloadMaxBytes + 1);
    expect(
      (await db.query(
        'books',
        columns: ['deleted'],
        where: 'book_id=?',
        whereArgs: [book],
      )).single['deleted'],
      1,
    );
  });

  test(
    'old v1 fields remain readable without rewriting omitted later metadata',
    () async {
      final (store, books, docs, book) = await fixture();
      final id = (await docs.tree(book)).single.id;
      await docs.saveMarkdown(id, 'legacy body');
      await books.remove(book);
      final db = await store.database;
      final entryId =
          (await db.query(
                'trash_entries',
                columns: ['trash_id'],
              )).single['trash_id']
              as int;
      final raw = await db.transaction(
        (tx) => LocalDocumentSnapshotReader.payload(tx, entryId),
      );
      final legacy = jsonDecode(raw) as Map;
      for (final row in legacy['documents'] as List) {
        (row as Map).remove('doc_type');
      }
      (legacy['book'] as Map).remove('labels');
      final legacyBytes = Uint8List.fromList(utf8.encode(jsonEncode(legacy)));
      await db.rawUpdate(
        'UPDATE trash_entries SET payload=CAST(? AS TEXT) WHERE trash_id=?',
        [legacyBytes, entryId],
      );
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(type: 'book')).entries.single;
      await trash.apply(entry, TrashOperation.restore);
      expect((await docs.read(id)).markdown, 'legacy body');
      expect((await books.read(book)).labels, ['保留,字段']);
    },
  );

  test(
    'graph validator rejects self/cycles/foreign/orphans and accepts scoped partial parent',
    () {
      Map<String, Object?> row(int id, int parent, {int book = 3}) => {
        'document_id': id,
        'book_id': book,
        'parent_id': parent,
      };
      for (final rows in [
        [row(1, 1)],
        [row(1, 2), row(2, 1)],
        [row(1, 0), row(2, 0, book: 4)],
        [row(1, 999)],
      ]) {
        expect(
          () => LocalDocumentSnapshotReader.validateGraph(rows, 3),
          throwsFormatException,
        );
      }
      LocalDocumentSnapshotReader.validateGraph(
        [row(2, 1)],
        3,
        complete: false,
      );
    },
  );
  test(
    'book restore refuses empty/missing-root/missing-leaf payload with exact rollback',
    () async {
      for (final damage in ['empty', 'missing-root', 'missing-leaf']) {
        final (store, books, docs, book) = await fixture();
        final first = (await docs.tree(book)).single.id;
        final parent = await docs.create(book, 'parent'),
            leaf = await docs.create(book, 'leaf', parentId: parent.id);
        await docs.saveMarkdown(leaf.id, 'exact leaf\r\n');
        await books.remove(book);
        final db = await store.database;
        final bookTrash = (await db.query('trash_entries')).single;
        final payload = jsonDecode(bookTrash['payload'] as String) as Map;
        final rows = payload['documents'] as List;
        if (damage == 'empty') {
          rows.clear();
        } else {
          rows.removeWhere(
            (row) =>
                row['document_id'] ==
                (damage == 'missing-root' ? first : leaf.id),
          );
        }
        await db.rawUpdate(
          'UPDATE trash_entries SET payload=CAST(? AS TEXT) WHERE trash_id=?',
          [
            Uint8List.fromList(utf8.encode(jsonEncode(payload))),
            bookTrash['trash_id'],
          ],
        );
        final beforeBooks = await db.query('books'),
            beforeDocs = await db.query('documents');
        final beforeTrash = await db.query('trash_entries');
        final trash = LocalTrashRepository(store);
        addTearDown(trash.dispose);
        final entry = (await trash.read(type: 'book')).entries.single;
        await expectLater(
          trash.apply(entry, TrashOperation.restore),
          throwsA(isA<TrashPreflightFailure>()),
        );
        expect(await db.query('books'), beforeBooks);
        expect(await db.query('documents'), beforeDocs);
        expect(await db.query('trash_entries'), beforeTrash);
      }
    },
  );

  test(
    'omitted document needs complete exact independent proof, not arbitrary JSON ID',
    () async {
      for (final damage in [
        'wrong-book',
        'missing-root',
        'stale-source',
        'wrong-type',
      ]) {
        final (store, books, docs, book) = await fixture();
        final parent = (await docs.tree(book)).single.id;
        final child = await docs.create(book, 'independent', parentId: parent);
        await docs.saveMarkdown(child.id, 'exact independent body');
        await docs.remove(child.id);
        await books.remove(book);
        final db = await store.database;
        final independent = (await db.query(
          'trash_entries',
          where: "resource_type='document'",
        )).single;
        final payload = jsonDecode(independent['payload'] as String) as Map;
        if (damage == 'wrong-book') payload['book_id'] = book + 100;
        if (damage == 'missing-root') {
          await db.update(
            'trash_entries',
            {'resource_id': 999999},
            where: 'trash_id=?',
            whereArgs: [independent['trash_id']],
          );
        }
        if (damage == 'stale-source') {
          (payload['documents'] as List).single['markdown'] =
              'forged/stale body';
        }
        if (damage == 'wrong-type') {
          await db.update(
            'trash_entries',
            {'resource_type': 'bookmark'},
            where: 'trash_id=?',
            whereArgs: [independent['trash_id']],
          );
        }
        await db.rawUpdate(
          'UPDATE trash_entries SET payload=CAST(? AS TEXT) WHERE trash_id=?',
          [
            Uint8List.fromList(utf8.encode(jsonEncode(payload))),
            independent['trash_id'],
          ],
        );
        final beforeBooks = await db.query('books'),
            beforeDocs = await db.query('documents');
        final beforeTrash = await db.query('trash_entries');
        final trash = LocalTrashRepository(store);
        addTearDown(trash.dispose);
        final entry = (await trash.read(type: 'book')).entries.single;
        await expectLater(
          trash.apply(entry, TrashOperation.restore),
          throwsA(isA<TrashPreflightFailure>()),
        );
        expect(await db.query('books'), beforeBooks);
        expect(await db.query('documents'), beforeDocs);
        expect(await db.query('trash_entries'), beforeTrash);
      }
    },
  );
}
