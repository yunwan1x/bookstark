// Deterministic fixture for tests and screenshot target only.
import 'package:bookstark_flutter/core/label_management_repository.dart';

class LabelManagementFixture implements LabelManagementRepository {
  LabelManagementFixture({this.canManage = true}) {
    for (final row in records.values) {
      _resources[row.id] = [
        for (var i = 0; i < row.bookCount; i++)
          LabelResource(
            id: 11 + i,
            type: LabelResourceType.book,
            title: i == 0 ? '阅读的方法' : '阅读书籍${i + 1}',
          ),
        for (var i = 0; i < row.blogCount; i++)
          LabelResource(
            id: 21 + i,
            type: LabelResourceType.blog,
            title: i == 0 ? '阅读的意义' : '阅读记录${i + 1}',
          ),
        for (var i = 0; i < row.bookmarkCount; i++)
          LabelResource(
            id: 31 + i,
            type: LabelResourceType.bookmark,
            title: i == 0 ? 'Flutter 开发文档' : '参考书签${i + 1}',
          ),
        if (row.id != 4)
          const LabelResource(
            id: 41,
            type: LabelResourceType.document,
            title: '',
          ),
      ];
    }
  }
  @override
  final bool canManage;
  final records = <int, ManagedLabel>{
    1: const ManagedLabel(
      id: 1,
      name: '阅读',
      bookCount: 3,
      blogCount: 8,
      bookmarkCount: 2,
    ),
    2: const ManagedLabel(
      id: 2,
      name: '学习方法',
      bookCount: 2,
      blogCount: 5,
      bookmarkCount: 1,
    ),
    3: const ManagedLabel(
      id: 3,
      name: 'Flutter',
      bookCount: 1,
      blogCount: 3,
      bookmarkCount: 2,
    ),
    4: const ManagedLabel(id: 4, name: '待整理'),
  };
  final _resources = <int, List<LabelResource>>{};
  int saveCalls = 0,
      nextId = 20,
      settingsWrites = 0,
      previewCalls = 0,
      mergeCalls = 0;
  bool failAfterCreate = false, failAfterMerge = false;
  LabelRecommendationSettings settings = const LabelRecommendationSettings(
    strategy: LabelRecommendationStrategy.recent,
    manualLabels: ['阅读', '学习方法'],
  );
  ManagedLabel _actual(ManagedLabel row) {
    final refs = _resources[row.id] ?? [];
    return ManagedLabel(
      id: row.id,
      name: row.name,
      bookCount: refs.where((ref) => ref.type == LabelResourceType.book).length,
      blogCount: refs.where((ref) => ref.type == LabelResourceType.blog).length,
      bookmarkCount: refs
          .where((ref) => ref.type == LabelResourceType.bookmark)
          .length,
      recentCount: refs.length,
    );
  }

  @override
  Future<ManagedLabelsPage> list(LabelManagementQuery query) async {
    query.parameters();
    final rows = records.values
        .where((item) => item.name.contains(query.keyword))
        .map(_actual)
        .toList();
    int number(ManagedLabel row) => switch (query.sort) {
      LabelSort.name => 0,
      LabelSort.book => row.bookCount,
      LabelSort.blog => row.blogCount,
      LabelSort.bookmark => row.bookmarkCount,
      LabelSort.total => row.bookCount + row.blogCount + row.bookmarkCount,
      LabelSort.recent => row.recentCount,
    };
    rows.sort((a, b) {
      final n = number(a).compareTo(number(b));
      final order = n == 0 ? a.name.compareTo(b.name) : n;
      return query.descending ? -order : order;
    });
    final unused = rows
        .where((row) => (_resources[row.id] ?? []).isEmpty)
        .length;
    return ManagedLabelsPage(
      rows.skip((query.page - 1) * 20).take(20).toList(),
      total: rows.length,
      used: rows.length - unused,
      unused: unused,
      page: query.page,
      pageSize: 20,
    );
  }

  @override
  Future<ManagedLabelDetail> read(int id) async {
    final row = records[id];
    if (row == null) throw StateError('标签不存在');
    return ManagedLabelDetail(_actual(row), List.of(_resources[id] ?? []));
  }

  @override
  Future<ManagedLabel> save(String name, {int? id}) async {
    validateLabelName(name);
    saveCalls++;
    final value = ManagedLabel(id: id ?? nextId++, name: name);
    records[value.id] = value;
    _resources.putIfAbsent(value.id, () => []);
    if (failAfterCreate && id == null) {
      failAfterCreate = false;
      throw StateError('Connection interrupted after creation');
    }
    return _actual(value);
  }

  @override
  Future<void> remove(int id) async {
    records.remove(id);
    _resources.remove(id);
  }

  @override
  Future<int> removeUnused() async {
    final ids = records.keys
        .where((id) => (_resources[id] ?? []).isEmpty)
        .toList();
    for (final id in ids) {
      await remove(id);
    }
    return ids.length;
  }

  @override
  Future<void> merge(int targetId, List<int> sourceIds) async {
    mergeCalls++;
    if (!records.containsKey(targetId)) throw StateError('目标已失效');
    final refs = {
      for (final ref in _resources[targetId] ?? <LabelResource>[])
        (ref.type, ref.id): ref,
    };
    for (final id in sourceIds) {
      if (id == targetId) continue;
      for (final ref in _resources[id] ?? <LabelResource>[]) {
        refs[(ref.type, ref.id)] = ref;
      }
      await remove(id);
    }
    _resources[targetId] = refs.values.toList();
    if (failAfterMerge) {
      failAfterMerge = false;
      throw StateError('Connection interrupted after merge');
    }
  }

  @override
  Future<void> unbind(int labelId, LabelResource resource) async {
    _resources[labelId]?.removeWhere(
      (item) => item.id == resource.id && item.type == resource.type,
    );
  }

  @override
  Future<LabelRecommendationSettings> recommendationSettings() async =>
      settings;
  @override
  Future<void> saveRecommendationSettings(
    LabelRecommendationSettings value,
  ) async {
    value.writeBody();
    settingsWrites++;
    settings = value;
  }

  @override
  Future<List<ManagedLabel>> recommendations(
    LabelRecommendationSettings value,
  ) async {
    value.writeBody();
    previewCalls++;
    final rows = records.values.map(_actual).toList();
    if (value.strategy == LabelRecommendationStrategy.manual) {
      return [
        for (final name in value.manualLabels)
          for (final row in rows)
            if (row.name == name) row,
      ].take(value.pageSize).toList();
    }
    rows.removeWhere((row) => row.recentCount == 0);
    rows.sort((a, b) => b.recentCount.compareTo(a.recentCount));
    return rows.take(value.pageSize).toList();
  }
}
