import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'bookmarks_repository.dart';
import 'local_store.dart';

class LocalBookmarksRepository implements BookmarksRepository {
  LocalBookmarksRepository(this.store);
  final LocalStore store;
  @override
  int get memberId => 1;
  @override
  bool get isAdmin => true;
  @override
  bool canEdit(BookmarkItem item) => true;
  BookmarkItem _item(Map<String, Object?> row) => BookmarkItem.fromJson({
    ...row,
    'member_id': memberId,
    'labels': jsonDecode(row['labels'] as String),
    for (final key in ['is_public', 'is_pinned', 'nav_visible'])
      key: row[key] == 1,
    for (final key in ['create_time', 'modify_time'])
      key: DateTime.fromMillisecondsSinceEpoch(
        row[key] as int,
      ).toIso8601String(),
  });
  Future<BookmarkItem> _read(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        final rows = await db.query(
          'bookmarks',
          where: 'bookmark_id = ? AND deleted = 0',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw StateError('书签不存在 / Bookmark no longer exists');
        return _item(rows.single);
      });

  @override
  Future<BookmarkPageResult> list(
    BookmarkQuery query,
  ) => store.maintenance.use(() async {
    query.parameters();
    // A local space has no public network feed. Public flags remain local data.
    if (query.scope == BookmarkScope.public) {
      throw UnsupportedError(
        '本地空间没有联网公开列表 / Public feed requires a server space',
      );
    }
    final clauses = ['deleted = 0'];
    final args = <Object?>[];
    if (query.keyword.isNotEmpty) {
      clauses.add('(title LIKE ? OR url LIKE ? OR description LIKE ?)');
      args.addAll(List.filled(3, '%${query.keyword}%'));
    }
    for (final flag in {
      'is_public': query.isPublic,
      'is_pinned': query.isPinned,
      'nav_visible': query.navVisible,
    }.entries) {
      if (flag.value != null) {
        clauses.add('${flag.key} = ?');
        args.add(flag.value! ? 1 : 0);
      }
    }
    if (query.noLabel) clauses.add("labels = '[]'");
    for (final label in query.labels) {
      clauses.add(
        'EXISTS (SELECT 1 FROM json_each(bookmarks.labels) WHERE value = ?)',
      );
      args.add(label);
    }
    if (query.labelsOr.isNotEmpty) {
      clauses.add(
        'EXISTS (SELECT 1 FROM json_each(bookmarks.labels) WHERE value IN (${List.filled(query.labelsOr.length, '?').join(',')}))',
      );
      args.addAll(query.labelsOr);
    }
    if (query.site.isNotEmpty) {
      final sites = <String>[];
      for (final scheme in ['https://', 'http://']) {
        final prefix = scheme + query.site;
        sites.add(
          "(substr(url,1,length(?)) = ? COLLATE NOCASE AND (length(url)=length(?) OR substr(url,length(?)+1,1) IN ('/','?','#')))",
        );
        args.addAll([prefix, prefix, prefix, prefix]);
      }
      clauses.add('(${sites.join(' OR ')})');
    }
    final time = query.modified ? 'modify_time' : 'create_time';
    if (query.start != null) {
      clauses.add('$time >= ?');
      args.add(query.start!.millisecondsSinceEpoch);
    }
    if (query.end != null) {
      clauses.add('$time <= ?');
      args.add(query.end!.millisecondsSinceEpoch);
    }
    return (await store.database).transaction((txn) async {
      final where = clauses.join(' AND ');
      final count = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM bookmarks WHERE $where',
        args,
      );
      final rows = await txn.query(
        'bookmarks',
        where: where,
        whereArgs: args,
        orderBy: 'is_pinned DESC, modify_time DESC, bookmark_id DESC',
        limit: 20,
        offset: (query.page - 1) * 20,
      );
      return BookmarkPageResult(
        rows.map(_item).toList(),
        count.single['total'] as int,
        query.page,
        20,
      );
    });
  });

  @override
  Future<BookmarkItem> read(int id) => store.maintenance.use(() async {
    if (id <= 0) throw const FormatException('Invalid bookmark ID');
    return _read(await store.database, id);
  });

  @override
  Future<BookmarkItem?> findByUrl(String url) =>
      store.maintenance.use(() async {
        bookmarkUri(url);
        final rows = await (await store.database).query(
          'bookmarks',
          where: 'url = ? AND deleted = 0',
          whereArgs: [url],
        );
        return rows.isEmpty ? null : _item(rows.single);
      });

  @override
  Future<int> save(BookmarkItem bookmark, {BookmarkItem? original}) =>
      store.maintenance.use(() async {
        bookmark.validate();
        if (original != null &&
            (original.id != bookmark.id || bookmark.id == null)) {
          throw const FormatException('Original bookmark ID mismatch');
        }
        return (await store.database).transaction((txn) async {
          final existing = await txn.query(
            'bookmarks',
            where: 'url = ? AND deleted = 0',
            whereArgs: [bookmark.url],
          );
          if (existing.isNotEmpty &&
              existing.single['bookmark_id'] != bookmark.id) {
            throw BookmarkAlreadyExists(_item(existing.single));
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final values = {
            'title': bookmark.title,
            'url': bookmark.url,
            'description': bookmark.description,
            'labels': jsonEncode(bookmark.labels.toSet().toList()),
            'is_public': bookmark.isPublic ? 1 : 0,
            'modify_time': now,
          };
          if (bookmark.id == null) {
            return txn.insert('bookmarks', {
              ...values,
              'create_time': now,
              'favicon': bookmark.favicon,
            });
          }
          final current = await _read(txn, bookmark.id!);
          if (current.url != bookmark.url) values['favicon'] = '';
          await txn.update(
            'bookmarks',
            values,
            where: 'bookmark_id = ?',
            whereArgs: [bookmark.id],
          );
          return bookmark.id!;
        });
      });

  Future<void> _delete(DatabaseExecutor txn, int id) =>
      store.maintenance.use(() async {
        final rows = await txn.query(
          'bookmarks',
          where: 'bookmark_id = ? AND deleted = 0',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw StateError('Bookmark no longer exists');
        await txn.insert('trash_entries', {
          'resource_type': 'bookmark',
          'resource_id': id,
          'name': rows.single['title'],
          'payload': jsonEncode({'version': 1, 'bookmark': rows.single}),
          'deleted_at': DateTime.now().toIso8601String(),
        });
        await txn.update(
          'bookmarks',
          {'deleted': 1},
          where: 'bookmark_id = ?',
          whereArgs: [id],
        );
      });

  @override
  Future<void> remove(int id) =>
      store.maintenance.use(() async => batch(BookmarkBatch.delete, [id]));
  @override
  Future<void> setPublic(int id, bool value) => store.maintenance.use(
    () async =>
        batch(value ? BookmarkBatch.share : BookmarkBatch.unshare, [id]),
  );
  @override
  Future<void> setNavVisible(int id, bool value) => store.maintenance.use(
    () async =>
        batch(value ? BookmarkBatch.showNav : BookmarkBatch.hideNav, [id]),
  );
  @override
  Future<void> batch(
    BookmarkBatch action,
    List<int> ids, {
    List<String> labels = const [],
  }) => store.maintenance.use(() async {
    if (ids.isEmpty ||
        ids.length > 200 ||
        ids.any((id) => id <= 0) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Select 1–200 unique bookmarks');
    }
    if ({
          BookmarkBatch.addLabels,
          BookmarkBatch.removeLabels,
        }.contains(action) &&
        (labels.isEmpty || labels.length > 50)) {
      throw const FormatException('Select 1–50 labels');
    }
    await (await store.database).transaction((txn) async {
      for (final id in ids) {
        final current = await _read(txn, id);
        if (action == BookmarkBatch.delete) {
          await _delete(txn, id);
          continue;
        }
        final values = <String, Object?>{
          'modify_time': DateTime.now().millisecondsSinceEpoch,
        };
        switch (action) {
          case BookmarkBatch.share:
            values['is_public'] = 1;
          case BookmarkBatch.unshare:
            values['is_public'] = 0;
          case BookmarkBatch.pin:
            values['is_pinned'] = 1;
          case BookmarkBatch.unpin:
            values['is_pinned'] = 0;
          case BookmarkBatch.showNav:
            values['nav_visible'] = 1;
          case BookmarkBatch.hideNav:
            values['nav_visible'] = 0;
          case BookmarkBatch.addLabels:
            values['labels'] = jsonEncode(
              {...current.labels, ...labels}.toList(),
            );
          case BookmarkBatch.removeLabels:
            values['labels'] = jsonEncode(
              current.labels.where((name) => !labels.contains(name)).toList(),
            );
          case BookmarkBatch.delete:
            break;
        }
        await txn.update(
          'bookmarks',
          values,
          where: 'bookmark_id = ?',
          whereArgs: [id],
        );
      }
    });
  });

  @override
  Future<void> sort(Map<int, int> order) => store.maintenance.use(() async {
    if (order.isEmpty ||
        order.length > 200 ||
        order.keys.any((id) => id <= 0)) {
      throw const FormatException('Invalid bookmark sort');
    }
    await (await store.database).transaction((txn) async {
      for (final entry in order.entries) {
        await _read(txn, entry.key);
        await txn.update(
          'bookmarks',
          {'order_sort': entry.value},
          where: 'bookmark_id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  });

  @override
  Future<BookmarkMetadata> metadata(String url) => store.maintenance.use(
    () async => throw UnsupportedError(
      '网页信息抓取需要服务器空间 / Metadata requires a server space',
    ),
  );
  @override
  Future<void> refreshFavicon(int id) => store.maintenance.use(
    () async => throw UnsupportedError(
      '图标刷新需要服务器空间 / Icon refresh requires a server space',
    ),
  );
}
