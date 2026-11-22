import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'documents_repository.dart';
import 'local_document_snapshot_reader.dart';

import 'package:bookstark_flutter/core/local_store.dart';

class LocalDocumentsRepository
    implements DocumentsRepository, BoundedDocumentsReader {
  LocalDocumentsRepository(this.store);
  final LocalStore store;
  Future<void> _book(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        if ((await db.query(
          'books',
          columns: ['book_id'],
          where: 'book_id = ? AND deleted = 0',
          whereArgs: [id],
        )).isEmpty) {
          throw StateError('书籍不存在 / Book no longer exists');
        }
      });

  Future<List<Map<String, Object?>>> _rows(DatabaseExecutor db, int bookId) =>
      store.maintenance.use(
        () => LocalDocumentSnapshotReader.metadata(db, bookId: bookId),
      );
  List<DocumentNode> _tree(List<Map<String, Object?>> rows) {
    final nodes = <int, Map<String, Object?>>{
      for (final row in rows)
        row['document_id'] as int: {
          ...row,
          'children': <Map<String, Object?>>[],
        },
    };
    final roots = <Map<String, Object?>>[];
    for (final node in nodes.values) {
      final parent = node['parent_id'] as int;
      if (parent == 0) {
        roots.add(node);
      } else {
        if (!nodes.containsKey(parent)) throw StateError('Orphan document');
        (nodes[parent]!['children'] as List).add(node);
      }
    }
    final result = decodeDocumentTree(roots);
    if (flattenDocuments(result).length != rows.length) {
      throw StateError('Document cycle detected');
    }
    return result;
  }

  Future<Map<String, Object?>> _row(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        final row = await LocalDocumentSnapshotReader.oneMetadata(db, id);
        await _book(db, row['book_id'] as int);
        return row;
      });

  @override
  Future<List<DocumentNode>> tree(int bookId) =>
      store.maintenance.use(() async {
        final db = await store.database;
        return db.transaction((txn) async {
          await _book(txn, bookId);
          return _tree(await _rows(txn, bookId));
        });
      });

  Future<TypedDocumentRead> _read(
    DatabaseExecutor txn,
    int id,
    int? expectedBookId,
    int markdownBudget,
  ) async {
    final row = await _row(txn, id);
    if (expectedBookId != null && row['book_id'] != expectedBookId) {
      throw StateError('Document belongs to another book');
    }
    final ordered = flattenDocuments(
      _tree(await _rows(txn, row['book_id'] as int)),
    ).map((node) => node.id).toList();
    final index = ordered.indexOf(id);
    if (index < 0) throw StateError('Document missing from owned book');
    final body = await _body(txn, row, markdownBudget);
    final item = DocumentItem.fromJson({
      ...row,
      'markdown': body.$1,
      'prev_id': index > 0 ? ordered[index - 1] : 0,
      'next_id': index + 1 < ordered.length ? ordered[index + 1] : 0,
    });
    return TypedDocumentRead(item: item, byteLength: body.$2, source: body.$1);
  }

  Future<(String, int)> _body(
    DatabaseExecutor tx,
    Map<String, Object?> row,
    int markdownBudget,
  ) =>
      LocalDocumentSnapshotReader.body(tx, row, markdownBudget: markdownBudget);

  @override
  Future<DocumentItem> read(int id) => store.maintenance.use(() async {
    final db = await store.database;
    return db.transaction(
      (txn) async => (await _read(txn, id, null, documentReadMaxBytes)).item,
    );
  });

  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) => store.maintenance.use(() async {
    if (id <= 0 || bookId <= 0) {
      throw ArgumentError('Invalid document identity');
    }
    documentBodyBudget('markdown', maxMarkdownReadBytes);
    final db = await store.database;
    return db.transaction(
      (txn) => _read(txn, id, bookId, maxMarkdownReadBytes),
    );
  });

  Future<void> _count(
    DatabaseExecutor db,
    int bookId,
  ) => store.maintenance.use(() async {
    await db.rawUpdate(
      'UPDATE books SET doc_count = (SELECT COUNT(*) FROM documents WHERE book_id = ? AND deleted = 0), modify_time = ? WHERE book_id = ?',
      [bookId, DateTime.now().toIso8601String(), bookId],
    );
  });

  @override
  Future<DocumentItem> create(int bookId, String name, {int parentId = 0}) =>
      store.maintenance.use(() async {
        validateDocumentName(name);
        if (parentId < 0) throw const FormatException('Invalid parent');
        return (await store.database).transaction((txn) async {
          await _book(txn, bookId);
          if (parentId != 0 &&
              (await _row(txn, parentId))['book_id'] != bookId) {
            throw StateError('Parent belongs to another book');
          }
          final now = DateTime.now().toIso8601String();
          final count = (await _rows(
            txn,
            bookId,
          )).where((row) => row['parent_id'] == parentId).length;
          final id = await txn.insert('documents', {
            'book_id': bookId,
            'document_name': name,
            'identify': 'local-pending-$now',
            'parent_id': parentId,
            'order_sort': count + 1,
            'create_time': now,
            'modify_time': now,
          });
          await txn.update(
            'documents',
            {'identify': 'local-doc-$id'},
            where: 'document_id = ?',
            whereArgs: [id],
          );
          await _count(txn, bookId);
          return DocumentItem(
            id: id,
            bookId: bookId,
            name: name,
            parentId: parentId,
          );
        });
      });

  @override
  Future<void> rename(int id, String name) => store.maintenance.use(() async {
    validateDocumentName(name);
    await (await store.database).transaction((txn) async {
      final row = await _row(txn, id);
      await txn.update(
        'documents',
        {
          'document_name': name,
          'modify_time': DateTime.now().toIso8601String(),
        },
        where: 'document_id = ?',
        whereArgs: [id],
      );
      await _count(txn, row['book_id'] as int);
    });
  });

  @override
  Future<void> saveMarkdown(int id, String markdown) =>
      store.maintenance.use(() async {
        if (utf8.encode(markdown).length > 500000) {
          throw const FormatException('Markdown exceeds 500000 UTF-8 bytes');
        }
        await (await store.database).transaction((txn) async {
          final row = await _row(txn, id);
          if (row['doc_type'] != 'markdown') {
            throw StateError('A dedicated editor is required');
          }
          await _body(txn, row, documentMarkdownEditBytes);
          await txn.rawUpdate(
            'UPDATE documents SET markdown=CAST(? AS TEXT),modify_time=? '
            'WHERE document_id = ?',
            [
              Uint8List.fromList(utf8.encode(markdown)),
              DateTime.now().toIso8601String(),
              id,
            ],
          );
          await _count(txn, row['book_id'] as int);
        });
      });

  @override
  Future<void> remove(int id) => store.maintenance.use(() async {
    await (await store.database).transaction((txn) async {
      final row = await _row(txn, id), bookId = row['book_id'] as int;
      final all = await _rows(txn, bookId);
      final root = flattenDocuments(
        _tree(all),
      ).singleWhere((node) => node.id == id);
      if (root.children.isNotEmpty) {
        throw StateError('请先移动或删除子文档 / Move or delete child documents first');
      }
      final ids = flattenDocuments([root]).map((node) => node.id).toSet();
      await LocalDocumentSnapshotReader.rejectForeignChildren(txn, bookId);
      final payloadRows = await LocalDocumentSnapshotReader.snapshots(
        txn,
        all.where((row) => ids.contains(row['document_id'])).toList(),
      );
      final payload = encodeBoundedLocalTrashPayload({
        'version': 1,
        'book_id': bookId,
        'documents': payloadRows,
      });
      await txn.insert('trash_entries', {
        'resource_type': 'document',
        'resource_id': id,
        'name': row['document_name'],
        'payload': payload,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      for (final id in ids) {
        final changed = await txn.update(
          'documents',
          {'deleted': 1},
          where: 'document_id = ? AND book_id = ? AND deleted = 0',
          whereArgs: [id, bookId],
        );
        if (changed != 1) throw StateError('Document deletion count changed');
      }
      await _count(txn, bookId);
    });
  });

  Future<void> _move(
    Transaction txn,
    int bookId,
    int id,
    int parentId,
    int order,
  ) => store.maintenance.use(() async {
    final all = await _rows(txn, bookId);
    final nodes = flattenDocuments(_tree(all));
    final matches = nodes.where((node) => node.id == id);
    if (matches.isEmpty) throw StateError('Document not in book');
    if (parentId < 0 ||
        flattenDocuments([matches.single]).any((node) => node.id == parentId) ||
        (parentId != 0 && !nodes.any((node) => node.id == parentId))) {
      throw StateError('Invalid parent');
    }
    final siblings = all
        .where(
          (row) => row['parent_id'] == parentId && row['document_id'] != id,
        )
        .map((row) => row['document_id'] as int)
        .toList();
    siblings.insert(order.clamp(0, siblings.length), id);
    for (var index = 0; index < siblings.length; index++) {
      await txn.update(
        'documents',
        {'parent_id': parentId, 'order_sort': index + 1},
        where: 'document_id = ?',
        whereArgs: [siblings[index]],
      );
    }
    await _count(txn, bookId);
  });

  @override
  Future<void> move(int bookId, int id, int parentId, {int order = 0}) =>
      store.maintenance.use(() async {
        await (await store.database).transaction((txn) async {
          await _book(txn, bookId);
          await _move(txn, bookId, id, parentId, order);
        });
      });

  @override
  Future<void> reorder(
    int id,
    String direction,
  ) => store.maintenance.use(() async {
    if (!{'up', 'down', 'indent', 'outdent'}.contains(direction)) {
      throw const FormatException('Invalid direction');
    }
    await (await store.database).transaction((txn) async {
      final row = await _row(txn, id), bookId = row['book_id'] as int;
      final all = await _rows(txn, bookId), parentId = row['parent_id'] as int;
      final siblings = all
          .where((row) => row['parent_id'] == parentId)
          .toList();
      final index = siblings.indexWhere((row) => row['document_id'] == id);
      switch (direction) {
        case 'up':
          if (index == 0) throw StateError('Already first');
          await _move(txn, bookId, id, parentId, index - 1);
        case 'down':
          if (index == siblings.length - 1) throw StateError('Already last');
          await _move(txn, bookId, id, parentId, index + 1);
        case 'indent':
          if (index == 0) throw StateError('No previous sibling');
          final target = siblings[index - 1]['document_id'] as int;
          await _move(
            txn,
            bookId,
            id,
            target,
            all.where((row) => row['parent_id'] == target).length,
          );
        case 'outdent':
          if (parentId == 0) throw StateError('Already at root');
          final parent = all.singleWhere(
            (row) => row['document_id'] == parentId,
          );
          final uncles = all
              .where((row) => row['parent_id'] == parent['parent_id'])
              .toList();
          await _move(
            txn,
            bookId,
            id,
            parent['parent_id'] as int,
            uncles.indexWhere((row) => row['document_id'] == parentId) + 1,
          );
      }
    });
  });
}
