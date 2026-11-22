import 'label_creation_resolution.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'label_management_repository.dart';
import 'local_store.dart';

class _Source {
  const _Source(this.table, this.id, this.title, this.type, this.modified);
  final String table, id, title, modified;
  final LabelResourceType type;
}

const _sources = [
  _Source('notes', 'id', 'title', LabelResourceType.blog, 'updated_at'),
  _Source(
    'books',
    'book_id',
    'book_name',
    LabelResourceType.book,
    'modify_time',
  ),
  _Source(
    'bookmarks',
    'bookmark_id',
    'title',
    LabelResourceType.bookmark,
    'modify_time',
  ),
  _Source(
    'documents',
    'document_id',
    'document_name',
    LabelResourceType.document,
    'modify_time',
  ),
];

class _Association {
  const _Association(
    this.source,
    this.id,
    this.title,
    this.labels,
    this.modified,
  );
  final _Source source;
  final int id;
  final String title;
  final List<String> labels;
  final DateTime? modified;
  LabelResource get resource =>
      LabelResource(id: id, type: source.type, title: title);
}

abstract interface class DurableLocalLabelCreationHost {
  bool get durableLocalLabelCreation;
  Future<LabelCreationResolution> createLocalLabel(String name);
}

class LocalLabelManagementRepository
    implements LabelManagementRepository, DurableLocalLabelCreationHost {
  LocalLabelManagementRepository(
    this.store, {
    DateTime Function()? clock,
    this.isCurrent,
    this.createRecoverably,
  }) : clock = clock ?? DateTime.now;
  final LocalStore store;
  final Future<LabelCreationResolution> Function(
    String name,
    Future<ManagedLabel> Function() create,
  )?
  createRecoverably;
  @override
  bool get durableLocalLabelCreation => createRecoverably != null;
  @override
  Future<LabelCreationResolution> createLocalLabel(String name) async {
    validateLabelName(name);
    _assertCurrent();
    final callback = createRecoverably;
    if (callback == null) {
      throw StateError('Local recovery coordinator unavailable');
    }
    final resolution = await callback(name, () => createLocalTransaction(name));
    _assertCurrent();
    final actual = ManagedLabel.fromJson(resolution.wire);
    if (actual.id <= 0 || actual.name != name) {
      throw const FormatException('Actual local label differs');
    }
    if (resolution.origin == LabelCreationOrigin.postAcknowledgement) {
      throw const FormatException(
        'HTTP receipt cannot represent local creation',
      );
    }
    return resolution;
  }

  final bool Function()? isCurrent;
  void _assertCurrent() {
    if (!(isCurrent?.call() ?? true) || store.maintenance.retired) {
      throw StateError('Local label owner retired');
    }
  }

  Future<T> _use<T>(Future<T> Function() action) =>
      store.maintenance.use(() async {
        _assertCurrent();
        final result = await action();
        _assertCurrent();
        return result;
      });
  Future<T> _transaction<T>(
    Database db,
    Future<T> Function(Transaction) action,
  ) => db.transaction((tx) async {
    _assertCurrent();
    final result = await action(tx);
    // This check is inside the transaction: retirement rolls every change back,
    // including discovery registration and cached labels on source resources.
    _assertCurrent();
    return result;
  });
  final DateTime Function() clock;
  @override
  bool get canManage => true;
  List<String> _labels(Object? value) {
    final result = jsonDecode(value as String);
    if (result is! List || result.any((name) => name is! String)) {
      throw const FormatException('Invalid local labels');
    }
    return result.cast<String>();
  }

  Future<List<_Association>> _associations(
    DatabaseExecutor db,
  ) => _use(() async {
    final values = <_Association>[];
    for (final source in _sources) {
      final rows = await db.query(
        source.table,
        columns: [source.id, source.title, 'labels', source.modified],
        where: source.type == LabelResourceType.document
            ? 'deleted = 0 AND book_id IN (SELECT book_id FROM books WHERE deleted = 0)'
            : 'deleted = 0',
      );
      for (final row in rows) {
        final labels = _labels(row['labels']);
        final time = row[source.modified];
        values.add(
          _Association(
            source,
            row[source.id] as int,
            row[source.title] as String,
            labels,
            time is int
                ? DateTime.fromMillisecondsSinceEpoch(time)
                : DateTime.tryParse(time as String? ?? ''),
          ),
        );
      }
    }
    return values;
  });

  Future<List<_Association>> _sync(DatabaseExecutor db) => _use(() async {
    final items = await _associations(db);
    for (final name in items.expand((item) => item.labels).toSet()) {
      // Preserve names already present in legacy local resources even if they
      // exceed today's creation limits; never rewrite identities on discovery.
      await db.insert('local_labels', {
        'label_name': name,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return items;
  });

  ManagedLabel _label(Map row, List<_Association> refs) {
    final name = row['label_name'] as String;
    final matches = refs.where((item) => item.labels.contains(name));
    return ManagedLabel(
      id: row['label_id'] as int,
      name: name,
      bookCount: matches
          .where((item) => item.source.type == LabelResourceType.book)
          .length,
      blogCount: matches
          .where((item) => item.source.type == LabelResourceType.blog)
          .length,
      bookmarkCount: matches
          .where((item) => item.source.type == LabelResourceType.bookmark)
          .length,
      recentCount: matches
          .where(
            (item) =>
                item.modified != null &&
                item.modified!.isAfter(
                  clock().subtract(const Duration(days: 90)),
                ),
          )
          .length,
    );
  }

  Future<Map<String, Object?>> _record(DatabaseExecutor db, int id) =>
      _use(() async {
        if (id <= 0) throw const FormatException('Invalid label ID');
        final rows = await db.query(
          'local_labels',
          where: 'label_id = ?',
          whereArgs: [id],
        );
        if (rows.length != 1) {
          throw StateError('标签不存在 / Label no longer exists');
        }
        return rows.single;
      });

  @override
  Future<ManagedLabelsPage> list(LabelManagementQuery query) => _use(() async {
    query.parameters();
    final db = await store.database;
    return _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final rows = await tx.query(
        'local_labels',
        where: query.keyword.isEmpty ? null : 'label_name LIKE ?',
        whereArgs: query.keyword.isEmpty ? null : ['%${query.keyword}%'],
      );
      final labels = rows.map((row) => _label(row, refs)).toList();
      int number(ManagedLabel label) => switch (query.sort) {
        LabelSort.name => 0,
        LabelSort.book => label.bookCount,
        LabelSort.blog => label.blogCount,
        LabelSort.bookmark => label.bookmarkCount,
        LabelSort.total =>
          label.bookCount + label.blogCount + label.bookmarkCount,
        LabelSort.recent => label.recentCount,
      };
      labels.sort((a, b) {
        final count = number(a).compareTo(number(b));
        final compared = count == 0 ? a.name.compareTo(b.name) : count;
        return query.descending ? -compared : compared;
      });
      final used = labels
          .where((label) => refs.any((ref) => ref.labels.contains(label.name)))
          .length;
      return ManagedLabelsPage(
        labels.skip((query.page - 1) * 20).take(20).toList(),
        total: labels.length,
        used: used,
        unused: labels.length - used,
        page: query.page,
        pageSize: 20,
      );
    });
  });

  @override
  Future<ManagedLabelDetail> read(int id) => _use(() async {
    final db = await store.database;
    return _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final row = await _record(tx, id);
      final label = _label(row, refs);
      final items = refs
          .where((item) => item.labels.contains(label.name))
          .map((item) => item.resource)
          .toList();
      return ManagedLabelDetail(label, items, serverLimit: items.length + 1);
    });
  });

  Future<void> _replace(
    DatabaseExecutor tx,
    List<_Association> refs,
    Set<String> remove, {
    String? replacement,
  }) => _use(() async {
    for (final ref in refs) {
      if (!ref.labels.any(remove.contains)) continue;
      final values = <String>[];
      for (final name in ref.labels) {
        final value = remove.contains(name) ? replacement : name;
        if (value != null && !values.contains(value)) values.add(value);
      }
      // Metadata-only changes retain content, encryption, pins and source IDs.
      await tx.update(
        ref.source.table,
        {'labels': jsonEncode(values)},
        where: '${ref.source.id} = ?',
        whereArgs: [ref.id],
      );
    }
  });

  @override
  Future<ManagedLabel> save(String name, {int? id}) async {
    if (id == null && createRecoverably != null) {
      return ManagedLabel.fromJson((await createLocalLabel(name)).wire);
    }
    return _saveDirect(name, id: id);
  }

  /// Actual SQL-only entry for the owned coordinator after its durable claim.
  /// Never call this to automatically replay an unknown creation.
  Future<ManagedLabel> createLocalTransaction(String name) => _saveDirect(name);

  Future<ManagedLabel> _saveDirect(String name, {int? id}) => _use(() async {
    validateLabelName(name);
    final db = await store.database;
    return _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final duplicates = await tx.query(
        'local_labels',
        where: 'label_name = ?',
        whereArgs: [name],
      );
      if (duplicates.any((row) => row['label_id'] != id)) {
        throw StateError('标签已存在 / Label already exists');
      }
      if (id == null) {
        final created = await tx.insert('local_labels', {'label_name': name});
        return ManagedLabel(id: created, name: name);
      }
      final old = await _record(tx, id);
      await tx.update(
        'local_labels',
        {'label_name': name},
        where: 'label_id = ?',
        whereArgs: [id],
      );
      await _replace(tx, refs, {
        old['label_name'] as String,
      }, replacement: name);
      return _label({
        'label_id': id,
        'label_name': name,
      }, await _associations(tx));
    });
  });

  @override
  Future<void> remove(int id) => _use(() async {
    final db = await store.database;
    await _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final old = await _record(tx, id);
      await _replace(tx, refs, {old['label_name'] as String});
      await tx.delete('local_labels', where: 'label_id = ?', whereArgs: [id]);
    });
  });

  @override
  Future<int> removeUnused() => _use(() async {
    final db = await store.database;
    return _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final used = refs.expand((item) => item.labels).toSet();
      final rows = await tx.query('local_labels');
      var count = 0;
      for (final row in rows) {
        if (!used.contains(row['label_name'])) {
          count += await tx.delete(
            'local_labels',
            where: 'label_id = ?',
            whereArgs: [row['label_id']],
          );
        }
      }
      return count;
    });
  });

  @override
  Future<void> merge(int targetId, List<int> sourceIds) => _use(() async {
    if (targetId <= 0 ||
        sourceIds.isEmpty ||
        sourceIds.length > 100 ||
        sourceIds.any((id) => id <= 0) ||
        sourceIds.contains(targetId) ||
        sourceIds.toSet().length != sourceIds.length) {
      throw const FormatException('Invalid label merge');
    }
    final db = await store.database;
    await _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final target = await _record(tx, targetId);
      final names = <String>{};
      for (final id in sourceIds) {
        names.add((await _record(tx, id))['label_name'] as String);
      }
      await _replace(
        tx,
        refs,
        names,
        replacement: target['label_name'] as String,
      );
      for (final id in sourceIds) {
        await tx.delete('local_labels', where: 'label_id = ?', whereArgs: [id]);
      }
    });
  });

  @override
  Future<void> unbind(int labelId, LabelResource resource) => _use(() async {
    final db = await store.database;
    await _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final label = await _record(tx, labelId);
      final matches = refs
          .where(
            (ref) => ref.source.type == resource.type && ref.id == resource.id,
          )
          .toList();
      if (matches.length != 1) {
        throw StateError('资源已失效 / Resource unavailable');
      }
      await _replace(tx, matches, {label['label_name'] as String});
    });
  });

  Future<LabelRecommendationSettings> _settings(DatabaseExecutor tx) =>
      _use(() async {
        final rows = await tx.query(
          'label_recommendation_settings',
          where: 'id = 1',
        );
        return rows.isEmpty
            ? const LabelRecommendationSettings(
                strategy: LabelRecommendationStrategy.recent,
              )
            : LabelRecommendationSettings.fromJson(
                jsonDecode(rows.single['settings'] as String) as Map,
              );
      });

  @override
  Future<LabelRecommendationSettings> recommendationSettings() =>
      _use(() async => _settings(await store.database));
  @override
  Future<void> saveRecommendationSettings(LabelRecommendationSettings value) =>
      _use(() async {
        final body = value.writeBody();
        final db = await store.database;
        await _transaction(db, (tx) async {
          await tx.insert('label_recommendation_settings', {
            'id': 1,
            'settings': jsonEncode(body),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
      });

  @override
  Future<List<ManagedLabel>> recommendations(
    LabelRecommendationSettings value,
  ) => _use(() async {
    final body = value.writeBody();
    final db = await store.database;
    return _transaction(db, (tx) async {
      final refs = await _sync(tx);
      final rows = (await tx.query(
        'local_labels',
      )).map((row) => _label(row, refs)).toList();
      if (value.strategy == LabelRecommendationStrategy.manual) {
        final names = (body['manual_labels'] as List).cast<String>();
        return [
          for (final name in names)
            for (final row in rows)
              if (row.name == name) row,
        ].take(value.pageSize).toList();
      }
      int score(ManagedLabel row) => switch (value.strategy) {
        LabelRecommendationStrategy.recent => row.recentCount,
        LabelRecommendationStrategy.total =>
          row.bookCount + row.blogCount + row.bookmarkCount,
        LabelRecommendationStrategy.book => row.bookCount,
        LabelRecommendationStrategy.bookmark => row.bookmarkCount,
        LabelRecommendationStrategy.manual => 0,
      };
      rows.removeWhere((row) => score(row) == 0);
      rows.sort((a, b) {
        final number = score(b).compareTo(score(a));
        return number == 0 ? a.name.compareTo(b.name) : number;
      });
      return rows.take(value.pageSize).toList();
    });
  });
}
