import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'local_document_snapshot_reader.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';

// Local negative IDs identify legacy soft-deleted notes; positive IDs identify
// existing trash snapshots. Neither is sent to the server.
class LocalTrashRepository implements TrashRepository {
  LocalTrashRepository(this.store);
  final LocalStore store;
  bool _closed = false;
  final _observed = <int, TrashEntry>{};
  void _open() {
    if (_closed) {
      throw const TrashPreflightFailure();
    }
  }

  TrashEntry _snapshot(Map row) => TrashEntry(
    id: row['trash_id'] as int,
    memberId: 0,
    type: row['resource_type'] as String,
    name: row['name'] as String,
    deletedAt: row['deleted_at'] as String,
  );
  TrashEntry _note(Map row) => TrashEntry(
    id: -(row['id'] as int),
    memberId: 0,
    type: 'blog',
    name: row['title'] as String,
    deletedAt: '',
  );
  @override
  Future<TrashPageData> read({
    String type = '',
    int page = 1,
  }) => store.maintenance.use(() async {
    _open();
    if (type.isNotEmpty && !trashTypes.contains(type) ||
        page < 1 ||
        page > 1000000) {
      throw const FormatException('Invalid local trash query');
    }
    const source =
        "SELECT trash_id AS id, resource_type AS type, name, deleted_at FROM trash_entries UNION ALL SELECT -id AS id, 'blog' AS type, title AS name, '' AS deleted_at FROM notes WHERE deleted = 1";
    final result = await (await store.database).transaction((tx) async {
      final count = await tx.rawQuery(
        "SELECT COUNT(*) AS total FROM ($source) WHERE (? = '' OR type = ?)",
        [type, type],
      );
      final rows = await tx.rawQuery(
        "SELECT * FROM ($source) WHERE (? = '' OR type = ?) ORDER BY deleted_at DESC, id DESC LIMIT 20 OFFSET ?",
        [type, type, (page - 1) * 20],
      );
      final entries = rows
          .map(
            (row) => TrashEntry(
              id: row['id'] as int,
              memberId: 0,
              type: row['type'] as String,
              name: row['name'] as String,
              deletedAt: row['deleted_at'] as String,
            ),
          )
          .toList();
      if (entries.any((v) => !trashTypes.contains(v.type) || v.id == 0)) {
        throw const FormatException('Invalid local trash metadata');
      }
      return TrashPageData(
        entries: entries,
        total: count.single['total'] as int,
        page: page,
        pageSize: 20,
      );
    });
    _open();
    for (final entry in result.entries) {
      _observed[entry.id] = entry;
    }
    return result;
  });

  Future<Map<String, Object?>> _deleted(
    DatabaseExecutor tx,
    String table,
    String key,
    Map snapshot,
  ) => store.maintenance.use(() async {
    final id = snapshot[key];
    if (id is! int || id <= 0) {
      throw const TrashPreflightFailure();
    }
    Map<String, Object?> actual;
    if (table == 'documents') {
      if (key != 'document_id' ||
          !{
            'document_id',
            'book_id',
            'parent_id',
            'markdown',
          }.every(snapshot.containsKey)) {
        throw const TrashPreflightFailure();
      }
      actual = await LocalDocumentSnapshotReader.oneMetadata(
        tx,
        id,
        deleted: 1,
      );
      final source = await LocalDocumentSnapshotReader.body(
        tx,
        actual,
        allowProtected: true,
      );
      actual = {...actual, 'markdown': source.$1};
    } else if (table == 'books') {
      if (key != 'book_id') throw const TrashPreflightFailure();
      actual = await LocalDocumentSnapshotReader.book(tx, id, deleted: 1);
      if (!{
        'book_id',
        'book_name',
        'description',
        'identify',
      }.every(snapshot.containsKey)) {
        throw const TrashPreflightFailure();
      }
    } else {
      final rows = await tx.query(
        table,
        where: '$key = ? AND deleted = 1',
        whereArgs: [id],
      );
      if (rows.length != 1) throw const TrashPreflightFailure();
      actual = rows.single;
    }
    // Never overwrite a changed or active resource using a stale snapshot.
    for (final field in snapshot.keys) {
      if (field != 'deleted' &&
          field != 'doc_count' &&
          actual[field] != snapshot[field]) {
        throw const TrashPreflightFailure();
      }
    }
    return actual;
  });

  Future<void> _active(DatabaseExecutor tx, String table, String key, int id) =>
      store.maintenance.use(() async {
        if (id <= 0) {
          throw const TrashPreflightFailure();
        }
        if ((await tx.query(
              table,
              columns: [key],
              where: '$key = ? AND deleted = 0',
              whereArgs: [id],
            )).length !=
            1) {
          throw const TrashPreflightFailure();
        }
      });

  List<Map<String, Object?>> _rows(Map payload, String key) {
    final value = payload[key];
    if (value is! List || value.length > 10000) {
      throw const FormatException('Invalid local trash snapshot');
    }
    final rows = value.map((v) {
      if (v is! Map) {
        throw const FormatException('Invalid snapshot row');
      }
      return Map<String, Object?>.from(v);
    }).toList();
    return rows;
  }

  Map<String, Object?> _row(Map payload, String key) {
    final value = payload[key];
    if (value is! Map) {
      throw const FormatException('Invalid snapshot root');
    }
    return Map<String, Object?>.from(value);
  }

  Future<void> _set(
    DatabaseExecutor tx,
    String table,
    String key,
    Map row,
    TrashOperation operation,
  ) => store.maintenance.use(() async {
    await _deleted(tx, table, key, row);
    final id = row[key];
    final changed = operation == TrashOperation.restore
        ? await tx.update(
            table,
            {'deleted': 0},
            where: '$key = ? AND deleted = 1',
            whereArgs: [id],
          )
        : await tx.delete(
            table,
            where: '$key = ? AND deleted = 1',
            whereArgs: [id],
          );
    if (changed != 1) {
      throw const TrashPreflightFailure();
    }
  });

  /// A book snapshot may legitimately omit documents already in independent
  /// trash entries. Every omission needs an exact, still-restorable full entry;
  /// an ID appearing in arbitrary JSON is not sufficient evidence.
  Future<void> _bookRestoreCoverage(
    DatabaseExecutor tx,
    int bookId,
    List<Map<String, Object?>> bookDocuments,
    int bookTrashId,
  ) async {
    LocalDocumentSnapshotReader.validateGraph(
      bookDocuments,
      bookId,
      complete: false,
    );
    final included = bookDocuments.map((row) => row['document_id']).toSet();
    final deleted = await LocalDocumentSnapshotReader.metadata(
      tx,
      bookId: bookId,
      deleted: 1,
    );
    final active = await LocalDocumentSnapshotReader.metadata(
      tx,
      bookId: bookId,
    );
    if (active.isNotEmpty) throw const TrashPreflightFailure();
    LocalDocumentSnapshotReader.validateGraph(deleted, bookId);
    final missing = deleted
        .map((row) => row['document_id'] as int)
        .where((id) => !included.contains(id))
        .toSet();
    if (missing.isEmpty) return;
    final candidates = await tx.query(
      'trash_entries',
      columns: ['trash_id', 'resource_id'],
      where:
          "resource_type='document' AND trash_id != ? AND resource_id IN "
          "(SELECT document_id FROM documents WHERE book_id=? AND deleted=1)",
      whereArgs: [bookTrashId, bookId],
      orderBy: 'trash_id',
      limit: localDocumentSnapshotMaxRows + 1,
    );
    if (candidates.length > localDocumentSnapshotMaxRows) {
      throw const TrashPreflightFailure();
    }
    final covered = <int>{};
    var inspectedBytes = 0;
    for (final candidate in candidates) {
      final root = candidate['resource_id'], trashId = candidate['trash_id'];
      if (root is! int ||
          root <= 0 ||
          !missing.contains(root) ||
          trashId is! int) {
        continue;
      }
      final lengths = await tx.rawQuery(
        'SELECT length(CAST(payload AS BLOB)) AS bytes '
        "FROM trash_entries WHERE trash_id=? AND resource_type='document' AND resource_id=?",
        [trashId, root],
      );
      final length = lengths.length == 1 ? lengths.single['bytes'] : null;
      if (length is! int || length < 0 || length > localTrashPayloadMaxBytes) {
        continue;
      }
      inspectedBytes += length;
      if (inspectedBytes > localTrashPayloadMaxBytes) {
        throw const TrashPreflightFailure();
      }
      try {
        final raw = await LocalDocumentSnapshotReader.payload(tx, trashId);
        final payload = jsonDecode(raw);
        if (payload is! Map ||
            payload['version'] is! int ||
            payload['version'] != 1 ||
            payload['book_id'] != bookId ||
            payload['book_id'] is! int) {
          continue;
        }
        final rows = _rows(payload, 'documents');
        if (!rows.any((row) => row['document_id'] == root)) continue;
        LocalDocumentSnapshotReader.validateGraph(
          rows,
          bookId,
          complete: false,
        );
        for (final row in rows) {
          // Entire candidate must match, including current source and all old
          // snapshot fields. Never rewrite/adopt a partial or stale snapshot.
          await _deleted(tx, 'documents', 'document_id', row);
        }
        covered.addAll(
          rows.map((row) => row['document_id'] as int).where(missing.contains),
        );
        if (covered.containsAll(missing)) return;
      } catch (_) {
        // Bad unrelated/stale candidates remain untouched, never promoted.
      }
    }
    throw const TrashPreflightFailure();
  }

  Future<void> _documents(
    DatabaseExecutor tx,
    List<Map<String, Object?>> rows,
    TrashOperation operation, {
    required int bookId,
    bool restoringBook = false,
  }) => store.maintenance.use(() async {
    final ids = rows.map((v) => v['document_id']).toSet();
    if (ids.length != rows.length) {
      throw const TrashPreflightFailure();
    }
    LocalDocumentSnapshotReader.validateGraph(rows, bookId, complete: false);
    await LocalDocumentSnapshotReader.rejectForeignChildren(tx, bookId);
    if (operation == TrashOperation.restore) {
      final active = await LocalDocumentSnapshotReader.metadata(
        tx,
        bookId: bookId,
      );
      if (restoringBook && active.isNotEmpty) {
        throw const TrashPreflightFailure();
      }
      if (active.any((row) => ids.contains(row['document_id']))) {
        throw const TrashPreflightFailure();
      }
      LocalDocumentSnapshotReader.validateGraph([...active, ...rows], bookId);
    }
    if (operation == TrashOperation.restore && !restoringBook) {
      await _active(tx, 'books', 'book_id', bookId);
    }
    for (final row in rows) {
      if (row['book_id'] != bookId) {
        throw const TrashPreflightFailure();
      }
      await _deleted(tx, 'documents', 'document_id', row);
      final parent = row['parent_id'];
      if (parent is! int || parent < 0) {
        throw const TrashPreflightFailure();
      }
      if (operation == TrashOperation.restore &&
          parent > 0 &&
          !ids.contains(parent)) {
        await _active(tx, 'documents', 'document_id', parent);
        final actual = (await tx.query(
          'documents',
          columns: ['document_id', 'book_id'],
          where: 'document_id = ?',
          whereArgs: [parent],
        )).single;
        if (actual['book_id'] != bookId) {
          throw const TrashPreflightFailure();
        }
      }
      if (operation == TrashOperation.delete) {
        final children = await tx.query(
          'documents',
          columns: ['document_id'],
          where: 'parent_id = ?',
          whereArgs: [row['document_id']],
        );
        // Do not orphan even a separately soft-deleted child's retained snapshot.
        if (children.any((child) => !ids.contains(child['document_id']))) {
          throw const TrashPreflightFailure();
        }
      }
    }
    for (final row in rows) {
      await _set(tx, 'documents', 'document_id', row, operation);
    }
    await tx.rawUpdate(
      'UPDATE books SET doc_count = (SELECT COUNT(*) FROM documents WHERE book_id = ? AND deleted = 0) WHERE book_id = ?',
      [bookId, bookId],
    );
  });

  Future<void> _tasks(
    DatabaseExecutor tx,
    List<Map<String, Object?>> rows,
    TrashOperation operation, {
    int? restoringTopic,
  }) => store.maintenance.use(() async {
    final ids = rows.map((v) => v['task_id']).toSet();
    if (ids.length != rows.length) {
      throw const TrashPreflightFailure();
    }
    for (final row in rows) {
      await _deleted(tx, 'tasks', 'task_id', row);
      final parent = row['parent_id'], topic = row['topic_id'];
      if (parent is! int || parent < 0 || topic is! int || topic < 0) {
        throw const TrashPreflightFailure();
      }
      if (operation == TrashOperation.restore) {
        if (parent > 0 && !ids.contains(parent)) {
          await _active(tx, 'tasks', 'task_id', parent);
        }
        if (topic > 0 && topic != restoringTopic) {
          await _active(tx, 'topics', 'topic_id', topic);
        }
      } else if ((await tx.query(
        'tasks',
        columns: ['task_id'],
        where: 'parent_id = ? AND deleted = 0',
        whereArgs: [row['task_id']],
      )).isNotEmpty) {
        throw const TrashPreflightFailure();
      }
    }
    for (final row in rows) {
      await _set(tx, 'tasks', 'task_id', row, operation);
    }
  });

  @override
  Future<void> apply(
    TrashEntry entry,
    TrashOperation operation,
  ) => store.maintenance.use(() async {
    _open();
    if (entry.memberId != 0 || !(_observed[entry.id]?.same(entry) ?? false)) {
      throw const TrashPreflightFailure();
    }
    try {
      await (await store.database).transaction((tx) async {
        _open();
        if (entry.id < 0) {
          final rows = await tx.query(
            'notes',
            columns: ['id', 'title'],
            where: 'id = ? AND deleted = 1',
            whereArgs: [-entry.id],
          );
          if (rows.length != 1 || !_note(rows.single).same(entry)) {
            throw const TrashPreflightFailure();
          }
          if (operation == TrashOperation.restore) {
            await tx.update(
              'notes',
              {'deleted': 0},
              where: 'id = ? AND deleted = 1',
              whereArgs: [-entry.id],
            );
          } else {
            await tx.delete(
              'notes',
              where: 'id = ? AND deleted = 1',
              whereArgs: [-entry.id],
            );
          }
          return;
        }
        final snapshots = await tx.query(
          'trash_entries',
          columns: [
            'trash_id',
            'resource_type',
            'resource_id',
            'CASE WHEN length(CAST(name AS BLOB))<=65536 THEN name ELSE NULL END AS name',
            'deleted_at',
          ],
          where: 'trash_id = ?',
          whereArgs: [entry.id],
        );
        if (snapshots.length != 1 || !_snapshot(snapshots.single).same(entry)) {
          throw const TrashPreflightFailure();
        }
        final snapshot = snapshots.single;
        final raw = await LocalDocumentSnapshotReader.payload(tx, entry.id);
        final payload = jsonDecode(raw);
        if (payload is! Map || payload['version'] != 1) {
          throw const FormatException('Unsupported trash snapshot');
        }
        final rootId = snapshot['resource_id'];
        switch (entry.type) {
          case 'book':
            final book = _row(payload, 'book');
            if (book['book_id'] != rootId) {
              throw const TrashPreflightFailure();
            }
            await _deleted(tx, 'books', 'book_id', book);
            final bookDocuments = _rows(payload, 'documents');
            if (operation == TrashOperation.restore) {
              await _bookRestoreCoverage(
                tx,
                rootId as int,
                bookDocuments,
                entry.id,
              );
            }
            if (operation == TrashOperation.delete) {
              final owned = await tx.query(
                'documents',
                columns: ['document_id'],
                where: 'book_id=?',
                whereArgs: [rootId],
                limit: localDocumentSnapshotMaxRows + 1,
              );
              final selected = bookDocuments
                  .map((row) => row['document_id'])
                  .toSet();
              if (owned.length > localDocumentSnapshotMaxRows ||
                  owned.any((row) => !selected.contains(row['document_id']))) {
                throw const TrashPreflightFailure();
              }
            }
            if (operation == TrashOperation.delete &&
                (await tx.query(
                  'documents',
                  columns: ['document_id'],
                  where: 'book_id = ? AND deleted = 0',
                  whereArgs: [rootId],
                )).isNotEmpty) {
              throw const TrashPreflightFailure();
            }
            if (operation == TrashOperation.restore) {
              await _set(tx, 'books', 'book_id', book, operation);
            }
            await _documents(
              tx,
              bookDocuments,
              operation,
              bookId: rootId as int,
              restoringBook: true,
            );
            if (operation == TrashOperation.delete) {
              await _set(tx, 'books', 'book_id', book, operation);
            }
          case 'document':
            final docs = _rows(payload, 'documents');
            if (!docs.any((v) => v['document_id'] == rootId) ||
                payload['book_id'] is! int) {
              throw const TrashPreflightFailure();
            }
            await _documents(
              tx,
              docs,
              operation,
              bookId: payload['book_id'] as int,
            );
          case 'task':
            final rows = _rows(payload, 'items');
            if (payload['root_id'] != rootId ||
                !rows.any((v) => v['task_id'] == rootId)) {
              throw const TrashPreflightFailure();
            }
            await _tasks(tx, rows, operation);
          case 'bookmark':
            final row = _row(payload, 'bookmark');
            if (row['bookmark_id'] != rootId) {
              throw const TrashPreflightFailure();
            }
            await _set(tx, 'bookmarks', 'bookmark_id', row, operation);
          case 'topic':
            final row = _row(payload, 'topic');
            if (row['topic_id'] != rootId) {
              throw const TrashPreflightFailure();
            }
            await _deleted(tx, 'topics', 'topic_id', row);
            if (operation == TrashOperation.restore) {
              await _set(tx, 'topics', 'topic_id', row, operation);
            }
            await _tasks(
              tx,
              _rows(payload, 'tasks'),
              operation,
              restoringTopic: rootId as int,
            );
            for (final table in {
              'summaries': 'topic_summaries',
              'resources': 'topic_resources',
              'comments': 'topic_comments',
            }.entries) {
              final rows = _rows(payload, table.key);
              if ((await tx.query(
                table.value,
                where: 'topic_id = ?',
                whereArgs: [rootId],
              )).isNotEmpty) {
                throw const TrashPreflightFailure();
              }
              for (final child in rows) {
                if (child['topic_id'] != rootId) {
                  throw const TrashPreflightFailure();
                }
                if (operation == TrashOperation.restore) {
                  await tx.insert(
                    table.value,
                    child,
                    conflictAlgorithm: ConflictAlgorithm.abort,
                  );
                }
              }
            }
            if (operation == TrashOperation.delete) {
              await _set(tx, 'topics', 'topic_id', row, operation);
            }
          default:
            throw const FormatException('Unsupported local trash type');
        }
        if (await tx.delete(
              'trash_entries',
              where: 'trash_id = ?',
              whereArgs: [entry.id],
            ) !=
            1) {
          throw const TrashPreflightFailure();
        }
      });
    } catch (_) {
      throw const TrashPreflightFailure();
    }
    _open();
  });

  @override
  Future<bool> isAbsent(TrashEntry entry) => store.maintenance.use(() async {
    _open();
    final db = await store.database;
    final rows = entry.id < 0
        ? await db.query(
            'notes',
            columns: ['id'],
            where: 'id = ? AND deleted = 1',
            whereArgs: [-entry.id],
          )
        : await db.query(
            'trash_entries',
            columns: ['trash_id'],
            where: 'trash_id = ?',
            whereArgs: [entry.id],
          );
    _open();
    return rows.isEmpty;
  });

  @override
  void dispose() {
    _closed = true;
    _observed.clear();
  }
}
