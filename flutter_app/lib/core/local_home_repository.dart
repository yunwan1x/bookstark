import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'home_dashboard_models.dart';
import 'home_dashboard_repository.dart';
import 'local_store.dart';

typedef HomeReadValue = Future<String?> Function(String key);
typedef HomeWriteValue = Future<void> Function(String key, String value);

final class LocalHomeVisit {
  const LocalHomeVisit(this.kind, this.id, this.at);
  final String kind;
  final int id;
  final DateTime at;
  Map<String, Object> toJson() => {
    'kind': kind,
    'id': id,
    'at': at.toUtc().toIso8601String(),
  };
}

/// One small encrypted preferences value per actual database identity; no
/// bodies, titles, URLs or credentials are copied into visit history.
final class LocalHomePreferences {
  LocalHomePreferences({
    required String namespace,
    required this.readValue,
    required this.writeValue,
    this.stillCurrent,
    DateTime Function()? now,
  }) : key = jsonEncode(['bookstark.home-v1', namespace]),
       now = now ?? DateTime.now;
  final String key;
  final HomeReadValue readValue;
  final HomeWriteValue writeValue;
  final bool Function()? stillCurrent;
  final DateTime Function() now;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        if (stillCurrent?.call() == false) {
          throw StateError('Local home scope retired');
        }
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<Map<String, Object?>> _read() async {
    final text = await readValue(key);
    if (text == null) {
      return {'format': 1, 'layout': null, 'visits': <Object?>[]};
    }
    try {
      if (utf8.encode(text).length > 16384) {
        throw const FormatException('Local home preferences exceed limit');
      }
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic> ||
          raw['format'] != 1 ||
          raw['visits'] is! List ||
          (raw['visits'] as List).length > 20) {
        throw const FormatException('Invalid local home preferences');
      }
      readHomeLayout(raw['layout']);
      if (raw['query'] != null) HomeQuery.readPreference(raw['query']);
      _visits(raw);
      return Map<String, Object?>.from(raw);
    } on FormatException {
      throw const HomePreferencesCorrupt();
    }
  }

  List<LocalHomeVisit> _visits(Map<String, Object?> state) {
    final result = <LocalHomeVisit>[];
    final seen = <String>{};
    for (final raw in state['visits'] as List) {
      if (raw is! Map ||
          ![
            'note',
            'article',
            'blog',
            'book',
            'document',
          ].contains(raw['kind']) ||
          raw['id'] is! int ||
          (raw['id'] as int) <= 0 ||
          raw['at'] is! String) {
        throw const FormatException('Invalid local home visit');
      }
      final at = DateTime.tryParse(raw['at'] as String);
      if (at == null || !seen.add(jsonEncode([raw['kind'], raw['id']]))) {
        throw const FormatException('Invalid local home visit');
      }
      result.add(LocalHomeVisit(raw['kind'] as String, raw['id'] as int, at));
    }
    return result;
  }

  Future<void> _write(Map<String, Object?> value) async {
    if (stillCurrent?.call() == false) {
      throw StateError('Local home scope retired');
    }
    final text = jsonEncode(value);
    if (utf8.encode(text).length > 16384) {
      throw const FormatException('Local home preferences exceed limit');
    }
    await writeValue(key, text);
  }

  Future<(List<HomeLayoutItem>, List<LocalHomeVisit>)> read() =>
      _serial(() async {
        final raw = await _read();
        return (readHomeLayout(raw['layout']), _visits(raw));
      });
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> desired, {
    bool Function()? cancelled,
  }) {
    final normalized = readHomeLayout(desired.map((e) => e.toJson()).toList());
    return _serial(() async {
      final raw = await _read();
      raw['layout'] = normalized.map((e) => e.toJson()).toList();
      if (cancelled?.call() == true) {
        throw StateError('Local home write retired');
      }
      await _write(raw);
      return normalized;
    });
  }

  Future<HomeQuery?> restoreQuery() => _serial(() async {
    final raw = await _read();
    return raw['query'] == null ? null : HomeQuery.readPreference(raw['query']);
  });
  Future<void> rememberQuery(HomeQuery query) => _serial(() async {
    final raw = await _read();
    raw['query'] = query.toPreference();
    await _write(raw);
  });

  Future<void> reset() => _serial(
    () => _write({'format': 1, 'layout': null, 'visits': <Object?>[]}),
  );

  Future<void> record(String kind, int id) {
    if (!['note', 'article', 'book', 'document'].contains(kind) || id <= 0) {
      throw const FormatException('Invalid local visit identity');
    }
    return _serial(() async {
      final raw = await _read();
      final visits = _visits(raw);
      bool same(LocalHomeVisit visit) =>
          visit.id == id &&
          (visit.kind == kind ||
              (['note', 'article', 'blog'].contains(kind) &&
                  ['note', 'article', 'blog'].contains(visit.kind)));
      raw['visits'] = [
        LocalHomeVisit(kind, id, now()).toJson(),
        ...visits.where((v) => !same(v)).map((v) => v.toJson()),
      ].take(20).toList();
      await _write(raw);
    });
  }

  Future<void> clearVisits({bool Function()? cancelled}) => _serial(() async {
    final raw = await _read();
    raw['visits'] = <Object?>[];
    if (cancelled?.call() == true) throw StateError('Local home write retired');
    await _write(raw);
  });
}

final class _HomeSource {
  const _HomeSource(this.key, this.sql);
  final String key, sql;
}

final class LocalHomeDashboardRepository
    implements HomeDashboardRepository, HomeQueryPreferences {
  LocalHomeDashboardRepository(this.store, this.preferences);
  final LocalStore store;
  final LocalHomePreferences preferences;
  @override
  Future<HomeQuery?> restoreQuery() => preferences.restoreQuery();
  @override
  Future<void> rememberQuery(HomeQuery query) =>
      preferences.rememberQuery(query);
  String _time(String column, {bool milliseconds = false}) {
    if (milliseconds) {
      return "datetime($column / 1000.0, 'unixepoch', 'localtime')";
    }
    return "CASE WHEN $column LIKE '%Z' OR substr($column,-6,1) IN ('+','-') THEN datetime($column,'localtime') ELSE datetime($column) END";
  }

  List<_HomeSource> _sources(HomeQuery query) {
    final created = query.order == 'created';
    final regular = _time(created ? 'create_time' : 'modify_time');
    final note = created ? 'NULL' : _time('updated_at', milliseconds: true);
    final bookmark = _time(
      created ? 'create_time' : 'modify_time',
      milliseconds: true,
    );
    return [
      _HomeSource(
        'notes',
        "SELECT id,title,$note stamp,'' badge FROM notes WHERE deleted=0 AND collection='note'",
      ),
      _HomeSource(
        'articles',
        "SELECT id,title,$note stamp,editor_type badge FROM notes WHERE deleted=0 AND collection='article'",
      ),
      _HomeSource(
        'tasks',
        "SELECT task_id id,substr(content,1,200) title,$regular stamp,CASE WHEN done=1 THEN 'done' ELSE 'pending' END badge FROM tasks WHERE deleted=0",
      ),
      _HomeSource(
        'books',
        "SELECT book_id id,book_name title,$regular stamp,'' badge FROM books WHERE deleted=0",
      ),
      _HomeSource(
        'bookmarks',
        "SELECT bookmark_id id,title,$bookmark stamp,'' badge FROM bookmarks WHERE deleted=0",
      ),
      _HomeSource(
        'topics',
        "SELECT topic_id id,title,$regular stamp,'' badge FROM topics WHERE deleted=0",
      ),
      _HomeSource(
        'nav',
        "SELECT bookmark_id id,title,$bookmark stamp,'' badge FROM bookmarks WHERE deleted=0 AND nav_visible=1",
      ),
    ];
  }

  Future<HomeRecentVisit?> _resolve(
    DatabaseExecutor db,
    LocalHomeVisit visit,
  ) async {
    if (['note', 'article', 'blog'].contains(visit.kind)) {
      final rows = await db.query(
        'notes',
        columns: ['id', 'title', 'collection'],
        where: 'id=? AND deleted=0',
        whereArgs: [visit.id],
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      final kind = row['collection'] as String;
      if (visit.kind != 'blog' && visit.kind != kind) return null;
      return HomeRecentVisit(
        kind: kind,
        id: visit.id,
        title: row['title'] as String,
        visitedAt: visit.at,
      );
    }
    if (visit.kind == 'book') {
      final rows = await db.query(
        'books',
        columns: ['book_name'],
        where: 'book_id=? AND deleted=0',
        whereArgs: [visit.id],
      );
      if (rows.isEmpty) return null;
      return HomeRecentVisit(
        kind: 'book',
        id: visit.id,
        title: rows.single['book_name'] as String,
        visitedAt: visit.at,
      );
    }
    final rows = await db.rawQuery(
      'SELECT d.document_name,b.book_name FROM documents d JOIN books b ON b.book_id=d.book_id WHERE d.document_id=? AND d.deleted=0 AND b.deleted=0',
      [visit.id],
    );
    if (rows.isEmpty) return null;
    return HomeRecentVisit(
      kind: 'document',
      id: visit.id,
      title: rows.single['document_name'] as String,
      context: rows.single['book_name'] as String,
      visitedAt: visit.at,
    );
  }

  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) async {
    var aborted = false;
    unawaited(
      abortTrigger?.then(
        (_) {
          aborted = true;
        },
        onError: (Object _, StackTrace _) {
          aborted = true;
        },
      ),
    );
    final saved = await preferences.read();
    if (aborted) throw StateError('Local home read retired');
    return store.maintenance.use(() async {
      final db = await store.database;
      return db.transaction((tx) async {
        if (aborted) throw StateError('Local home read retired');
        final sections = <HomeContentSection>[];
        final activity = <String, int>{};
        final unknown = <String, int>{};
        final periods = homeCalendarPeriods(query);
        final first = homeDayKey(periods.first.start),
            last = homeDayKey(periods.last.end);
        for (final source in _sources(query)) {
          if (aborted) throw StateError('Local home read retired');
          final base =
              'WITH items AS (${source.sql}), dated AS (SELECT *,substr(stamp,1,10) day FROM items) ';
          final cutoff = query.end == null ? '' : ' WHERE day<=?';
          final args = <Object?>[if (query.end != null) query.end];
          final count = await tx.rawQuery(
            '${base}SELECT COUNT(*) n FROM dated$cutoff',
            args,
          );
          final missing = await tx.rawQuery(
            '${base}SELECT COUNT(*) n FROM dated WHERE day IS NULL',
          );
          final absent = missing.single['n'] as int;
          if (absent > 0) unknown[source.key] = absent;
          final rows = await tx.rawQuery(
            '${base}SELECT id,title,stamp date,badge FROM dated$cutoff ORDER BY stamp DESC,id DESC LIMIT ?',
            [...args, query.limit],
          );
          sections.add(
            HomeContentSection(
              key: source.key,
              total: count.single['n'] as int,
              items: [
                for (final row in rows)
                  HomeContentItem(
                    id: row['id'] as int,
                    title: row['title'] as String,
                    date: row['date'] as String? ?? '',
                    badge: row['badge'] as String,
                  ),
              ],
            ),
          );
          if (source.key != 'nav') {
            final days = await tx.rawQuery(
              '${base}SELECT day,COUNT(*) n FROM dated WHERE day>=? AND day<=? GROUP BY day',
              [first, last],
            );
            for (final day in days) {
              final key = day['day'] as String;
              activity[key] = (activity[key] ?? 0) + (day['n'] as int);
            }
          }
        }
        final visits = <HomeRecentVisit>[];
        for (final visit in saved.$2) {
          if (aborted) throw StateError('Local home read retired');
          final resolved = await _resolve(tx, visit);
          if (resolved != null) visits.add(resolved);
        }
        if (aborted) throw StateError('Local home read retired');
        return HomeDashboardSnapshot(
          layout: saved.$1,
          sections: sections,
          recent: visits,
          activity: activity,
          unknownDates: unknown,
        );
      });
    });
  }

  Future<void> recordVisit(String kind, int id) => store.maintenance.use(
    () async {
      if (!['note', 'article', 'book', 'document'].contains(kind) || id <= 0) {
        throw const FormatException('Invalid local visit identity');
      }
      final current = await _resolve(
        await store.database,
        LocalHomeVisit(kind, id, DateTime.now()),
      );
      if (current != null) await preferences.record(current.kind, current.id);
    },
  );
  Future<T> _writeBound<T>(
    Future<T> Function(bool Function()) action,
    Future<void>? parent,
  ) async {
    var retired = false;
    unawaited(
      parent?.then(
        (_) {
          retired = true;
        },
        onError: (Object _, StackTrace _) {
          retired = true;
        },
      ),
    );
    try {
      return await action(() => retired);
    } catch (_) {
      throw const HomeWriteUnconfirmed();
    }
  }

  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  }) async {
    final normalized = readHomeLayout(value.map((e) => e.toJson()).toList());
    return _writeBound(
      (cancelled) => preferences.saveLayout(normalized, cancelled: cancelled),
      abortTrigger,
    );
  }

  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) => _writeBound(
    (cancelled) => preferences.clearVisits(cancelled: cancelled),
    abortTrigger,
  );
}
