import 'package:bookstark_flutter/core/trash_repository.dart';

class TrashFixture implements TrashRepository {
  TrashFixture({this.loseReceipt = false, this.partial = false});
  final bool loseReceipt, partial;
  final rows = <TrashEntry>[
    const TrashEntry(
      id: 1,
      memberId: 7,
      type: 'blog',
      name: '旅行阅读笔记',
      deletedAt: '2026-11-05T14:20:00+08:00',
    ),
    const TrashEntry(
      id: 2,
      memberId: 7,
      type: 'bookmark',
      name: '旅行书签',
      deletedAt: '2026-11-05T14:18:00+08:00',
      resourceUrl: 'https://example.test/travel',
    ),
    const TrashEntry(
      id: 3,
      memberId: 7,
      type: 'task',
      name: '整理阅读记录',
      deletedAt: '2026-11-05T14:15:00+08:00',
    ),
  ];
  @override
  Future<TrashPageData> read({String type = '', int page = 1}) async {
    final filtered = rows.where((v) => type.isEmpty || v.type == type).toList();
    return TrashPageData(
      entries: filtered.skip((page - 1) * 20).take(20).toList(),
      total: filtered.length,
      page: page,
      pageSize: 20,
    );
  }

  @override
  Future<void> apply(TrashEntry entry, TrashOperation operation) async {
    if (partial && entry.id == 2) {
      throw const TrashPreflightFailure();
    }
    rows.removeWhere((v) => v.id == entry.id);
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
  }

  @override
  Future<bool> isAbsent(TrashEntry entry) async =>
      !rows.any((v) => v.id == entry.id);
  @override
  void dispose() {
    rows.clear();
  }
}
