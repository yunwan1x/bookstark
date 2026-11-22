import 'dart:convert';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'local_document_snapshot_reader.dart';

class LocalBooksRepository implements BooksRepository {
  LocalBooksRepository(this.store);
  final LocalStore store;
  BookItem _book(Map<String, Object?> row) => BookItem.fromJson({
    ...row,
    'labels': jsonDecode(row['labels'] as String),
  }, detail: true);
  @override
  Future<BooksPageResult> list({
    String keyword = '',
    int page = 1,
  }) => store.maintenance.use(() async {
    if (page < 1) throw const FormatException('Invalid page');
    final db = await store.database;
    final pattern =
        '%${keyword.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    const where =
        "deleted = 0 AND (book_name LIKE ? ESCAPE '\\' OR labels LIKE ? ESCAPE '\\')";
    return db.transaction((txn) async {
      final count = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM books WHERE $where',
        [pattern, pattern],
      );
      final rows = await txn.query(
        'books',
        where: where,
        whereArgs: [pattern, pattern],
        orderBy: 'modify_time DESC, book_id DESC',
        limit: 12,
        offset: (page - 1) * 12,
      );
      return BooksPageResult(
        rows.map(_book).toList(),
        count.single['total'] as int,
        page,
        12,
      );
    });
  });

  @override
  Future<BookItem> read(int id) => store.maintenance.use(() async {
    final rows = await (await store.database).query(
      'books',
      where: 'book_id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('书籍不存在 / Book no longer exists');
    return _book(rows.single);
  });

  @override
  Future<int> save(BookItem book) => store.maintenance.use(() async {
    // JSON labels are lossless locally; only legacy HTTP CSV needs restrictions.
    book.copyWith(labels: const []).writeBody();
    if (!book.labelsLoaded) throw StateError('Load details before saving');
    final now = DateTime.now().toIso8601String();
    final values = {
      'book_name': book.name,
      'description': book.description,
      'labels': jsonEncode(book.labels.toSet().toList()),
      'modify_time': now,
    };
    final db = await store.database;
    return db.transaction((txn) async {
      if (book.id == null) {
        final id = await txn.insert('books', {
          ...values,
          'identify': 'local-pending-$now',
          'create_time': now,
        });
        await txn.update(
          'books',
          {'identify': 'local-book-$id'},
          where: 'book_id = ?',
          whereArgs: [id],
        );
        // Match Go Book.Insert: every new book starts with a same-name document.
        final documentId = await txn.insert('documents', {
          'book_id': id,
          'document_name': book.name,
          'identify': 'local-first-book-$id',
          'create_time': now,
          'modify_time': now,
        });
        await txn.update(
          'documents',
          {'identify': 'local-doc-$documentId'},
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
        await txn.update(
          'books',
          {'doc_count': 1},
          where: 'book_id = ?',
          whereArgs: [id],
        );
        return id;
      }
      final changed = await txn.update(
        'books',
        values,
        where: 'book_id = ? AND deleted = 0',
        whereArgs: [book.id],
      );
      if (changed != 1) throw StateError('书籍不存在 / Book no longer exists');
      return book.id!;
    });
  });

  @override
  Future<void> remove(int id) => store.maintenance.use(() async {
    await (await store.database).transaction((txn) async {
      final book = await LocalDocumentSnapshotReader.book(txn, id, deleted: 0);
      final metadata = await LocalDocumentSnapshotReader.metadata(
        txn,
        bookId: id,
      );
      LocalDocumentSnapshotReader.validateGraph(metadata, id);
      await LocalDocumentSnapshotReader.rejectForeignChildren(txn, id);
      final documents = await LocalDocumentSnapshotReader.snapshots(
        txn,
        metadata,
      );
      final payload = encodeBoundedLocalTrashPayload({
        'version': 1,
        'book': book,
        'documents': documents,
      });
      await txn.insert('trash_entries', {
        'resource_type': 'book',
        'resource_id': id,
        'name': book['book_name'],
        'payload': payload,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      final changedDocuments = await txn.update(
        'documents',
        {'deleted': 1},
        where: 'book_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      if (changedDocuments != metadata.length) {
        throw StateError('Document deletion count changed');
      }
      final changedBook = await txn.update(
        'books',
        {'deleted': 1},
        where: 'book_id = ?',
        whereArgs: [id],
      );
      if (changedBook != 1) throw StateError('Book deletion count changed');
    });
  });
}
