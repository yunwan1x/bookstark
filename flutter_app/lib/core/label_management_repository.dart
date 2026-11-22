import 'label_creation_resolution.dart';
import 'dart:convert';
import 'api_client.dart';

enum LabelSort { name, book, blog, bookmark, total, recent }

enum LabelRecommendationStrategy { recent, total, book, bookmark, manual }

int _number(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0)) {
    throw const FormatException('Invalid label number');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String) throw const FormatException('Invalid label text');
  return value;
}

void validateLabelName(String value) {
  if (value.trim().isEmpty || utf8.encode(value).length > 100) {
    throw const FormatException(
      '标签名称不能为空，最多100字节（UTF-8） / Name must be nonempty and at most 100 UTF-8 bytes',
    );
  }
}

class ManagedLabel {
  const ManagedLabel({
    required this.id,
    required this.name,
    this.bookCount = 0,
    this.blogCount = 0,
    this.bookmarkCount = 0,
    this.recentCount = 0,
  });
  final int id, bookCount, blogCount, bookmarkCount, recentCount;
  final String name;
  // Document associations are absent from these three server counters.
  // Zero must never be interpreted as proof that this label is unused.
  factory ManagedLabel.fromJson(Map row) => ManagedLabel(
    id: _number(row['label_id'], positive: true),
    name: _text(row['label_name']),
    bookCount: _number(row['book_count'] ?? 0),
    blogCount: _number(row['blog_count'] ?? 0),
    bookmarkCount: _number(row['bookmark_count'] ?? 0),
    recentCount: _number(row['recent_count'] ?? 0),
  );
}

class LabelManagementQuery {
  const LabelManagementQuery({
    this.keyword = '',
    this.sort = LabelSort.name,
    this.descending = false,
    this.page = 1,
  });
  final String keyword;
  final LabelSort sort;
  final bool descending;
  final int page;
  Map<String, String> parameters() {
    if (page < 1) throw const FormatException('Invalid label page');
    return {
      'keyword': keyword,
      'sort_by': sort.name,
      'sort_order': descending ? 'desc' : 'asc',
      'page': '$page',
      'page_size': '20',
    };
  }
}

class ManagedLabelsPage {
  const ManagedLabelsPage(
    this.items, {
    required this.total,
    required this.used,
    required this.unused,
    required this.page,
    required this.pageSize,
  });
  final List<ManagedLabel> items;
  final int total, used, unused, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

enum LabelResourceType { book, blog, bookmark, document }

class LabelResource {
  const LabelResource({
    required this.id,
    required this.type,
    required this.title,
    this.identify = '',
  });
  final int id;
  final LabelResourceType type;
  final String title, identify;
  factory LabelResource.fromJson(Map row) => LabelResource(
    id: _number(row['resource_id'], positive: true),
    type: LabelResourceType.values.byName(_text(row['relation_type'])),
    title: _text(row['title']),
    identify: _text(row['identify'] ?? ''),
  );
}

class ManagedLabelDetail {
  const ManagedLabelDetail(this.label, this.items, {this.serverLimit = 500});
  final ManagedLabel label;
  final List<LabelResource> items;
  final int serverLimit;
  bool get possiblyTruncated => items.length >= serverLimit;
  bool get verifiedUnused => items.isEmpty && !possiblyTruncated;
}

class LabelRecommendationSettings {
  const LabelRecommendationSettings({
    required this.strategy,
    this.manualLabels = const [],
    this.pageSize = 10,
  });
  final LabelRecommendationStrategy strategy;
  final List<String> manualLabels;
  final int pageSize;
  factory LabelRecommendationSettings.fromJson(Map row) {
    final names = row['manual_labels'];
    if (names is! List || names.any((value) => value is! String)) {
      throw const FormatException('Invalid selected labels');
    }
    final value = LabelRecommendationSettings(
      strategy: LabelRecommendationStrategy.values.byName(
        _text(row['strategy']),
      ),
      manualLabels: names.cast<String>(),
      pageSize: _number(row['page_size'], positive: true),
    );
    if (value.pageSize > 50) {
      throw const FormatException('Invalid recommendation size');
    }
    return value;
  }
  Map<String, Object?> writeBody() {
    if (pageSize < 1 || pageSize > 50 || manualLabels.length > 50) {
      throw const FormatException(
        '推荐数量1—50，精选最多50项 / Use 1–50 recommendations and up to 50 selected labels',
      );
    }
    final names = <String>[];
    for (final raw in manualLabels) {
      final name = raw.trim();
      validateLabelName(name);
      if (name.contains(',') || name.contains('，')) {
        throw const FormatException(
          '精选标签包含旧设置无法无损保存的分隔符 / Selected name contains an unsupported separator',
        );
      }
      if (!names.contains(name)) names.add(name);
    }
    return {
      'strategy': strategy.name,
      'manual_labels': names,
      'page_size': pageSize,
    };
  }
}

abstract interface class LabelManagementRepository {
  bool get canManage;
  Future<ManagedLabelsPage> list(LabelManagementQuery query);
  Future<ManagedLabelDetail> read(int id);
  Future<ManagedLabel> save(String name, {int? id});
  Future<void> remove(int id);
  Future<int> removeUnused();
  Future<void> merge(int targetId, List<int> sourceIds);
  Future<void> unbind(int labelId, LabelResource resource);
  Future<LabelRecommendationSettings> recommendationSettings();
  Future<void> saveRecommendationSettings(LabelRecommendationSettings value);
  Future<List<ManagedLabel>> recommendations(LabelRecommendationSettings value);
}

/// New-label coordinator capability. Existing-ID writes keep legacy interfaces.
abstract interface class DurableLabelCreationHost {
  bool get durableLabelCreation;
  Future<LabelCreationResolution> createGlobalLabel(String name);
}

class RemoteLabelManagementRepository
    implements LabelManagementRepository, DurableLabelCreationHost {
  RemoteLabelManagementRepository(
    this.client, {
    required this.canManage,
    this.isCurrent,
    this.createRecoverably,
  }) : _sessionRevision = client.sessionRevision;
  final BookstarkClient client;
  final Future<LabelCreationResolution> Function(String name)?
  createRecoverably;
  @override
  bool get durableLabelCreation => createRecoverably != null;
  final bool Function()? isCurrent;
  final int _sessionRevision;
  void _assertCurrent() {
    if (client.sessionRevision != _sessionRevision ||
        !(isCurrent?.call() ?? true)) {
      throw StateError('Label owner changed; operation was not replayed');
    }
  }

  Future<Map<String, Object?>> _read(String path) async {
    _assertCurrent();
    final result = await client.get(path);
    _assertCurrent();
    return result;
  }

  Future<Map<String, Object?>> _write(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    _assertCurrent();
    final result = await client.mutate(
      method,
      path,
      body,
      beforeSubmit: _assertCurrent,
    );
    _assertCurrent();
    return result;
  }

  @override
  final bool canManage;
  void _admin() {
    _assertCurrent();
    if (!canManage) {
      throw const ApiFailure(
        403,
        '需要管理员权限 / Administrator permission required',
      );
    }
  }

  void _id(int id) {
    _number(id, positive: true);
  }

  @override
  Future<ManagedLabelsPage> list(LabelManagementQuery query) async {
    final result = await _read(
      '/api/labels?${Uri(queryParameters: query.parameters()).query}',
    );
    final data = result['data'];
    if (data != null && data is! List) {
      throw const FormatException('Invalid labels');
    }
    final rows = (data as List? ?? const [])
        .map((row) => ManagedLabel.fromJson(row as Map))
        .toList();
    final page = _number(result['page'], positive: true),
        size = _number(result['page_size'], positive: true);
    if (page != query.page ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      throw const FormatException('Invalid label pagination');
    }
    return ManagedLabelsPage(
      rows,
      total: _number(result['total']),
      used: _number(result['used_count']),
      unused: _number(result['unused_count']),
      page: page,
      pageSize: size,
    );
  }

  @override
  Future<ManagedLabelDetail> read(int id) async {
    _id(id);
    final result = await _read('/api/labels/$id/detail');
    final label = ManagedLabel.fromJson(result);
    if (label.id != id) throw const FormatException('Label ID mismatch');
    final data = result['items'];
    if (data != null && data is! List) {
      throw const FormatException('Invalid label resources');
    }
    return ManagedLabelDetail(
      label,
      (data as List? ?? const [])
          .map((row) => LabelResource.fromJson(row as Map))
          .toList(),
    );
  }

  @override
  Future<LabelCreationResolution> createGlobalLabel(String name) async {
    validateLabelName(name);
    _assertCurrent();
    final callback = createRecoverably;
    if (callback == null) throw StateError('Durable creation unavailable');
    final resolution = await callback(name);
    _assertCurrent();
    final actual = ManagedLabel.fromJson(resolution.wire);
    if (actual.id <= 0 || actual.name != name) {
      throw const FormatException(
        'Actual global label differs; review required',
      );
    }
    return resolution;
  }

  @override
  Future<ManagedLabel> save(String name, {int? id}) async {
    validateLabelName(name);
    if (id == null) {
      if (createRecoverably != null) {
        return ManagedLabel.fromJson((await createGlobalLabel(name)).wire);
      }
      return ManagedLabel.fromJson(
        await _write('POST', '/api/labels', {'label_name': name}),
      );
    }
    _admin();
    _id(id);
    await _write('PUT', '/api/labels/$id', {'label_name': name});
    return (await read(id)).label;
  }

  @override
  Future<void> remove(int id) async {
    _admin();
    _id(id);
    await _write('DELETE', '/api/labels/$id', {});
  }

  @override
  Future<int> removeUnused() async {
    _admin();
    return _number(
      (await _write('DELETE', '/api/labels/unused', {}))['deleted'],
    );
  }

  @override
  Future<void> merge(int targetId, List<int> sourceIds) async {
    _admin();
    _id(targetId);
    if (sourceIds.isEmpty ||
        sourceIds.length > 100 ||
        sourceIds.contains(targetId) ||
        sourceIds.toSet().length != sourceIds.length) {
      throw const FormatException('Invalid merge sources');
    }
    for (final id in sourceIds) {
      _id(id);
    }
    // The old Go merge does not validate target existence. Verify all selected
    // records before the single transaction endpoint; never emulate by loops.
    await read(targetId);
    for (final id in sourceIds) {
      await read(id);
    }
    await _write('POST', '/api/labels/merge', {
      'target_id': targetId,
      'source_ids': sourceIds,
    });
  }

  @override
  Future<void> unbind(int labelId, LabelResource resource) async {
    _id(labelId);
    _id(resource.id);
    await _write('DELETE', '/api/labels/bindlist', {
      'label_id': labelId,
      'resource_ids': [resource.id],
      'relation_type': resource.type.name,
    });
  }

  @override
  Future<LabelRecommendationSettings> recommendationSettings() async =>
      LabelRecommendationSettings.fromJson(
        await _read('/api/labels/recommendation-settings'),
      );
  @override
  Future<void> saveRecommendationSettings(
    LabelRecommendationSettings value,
  ) async {
    _admin();
    await _write(
      'PUT',
      '/api/labels/recommendation-settings',
      value.writeBody(),
    );
  }

  @override
  Future<List<ManagedLabel>> recommendations(
    LabelRecommendationSettings value,
  ) async {
    final body = value.writeBody();
    final result = await _read(
      '/api/labels/recommendations?${Uri(queryParameters: {'strategy': body['strategy'] as String, 'manual_labels': (body['manual_labels'] as List).join(','), 'page_size': '${value.pageSize}'}).query}',
    );
    final rows = result['data'];
    if (rows != null && rows is! List) {
      throw const FormatException('Invalid recommendations');
    }
    return (rows as List? ?? const [])
        .map((row) => ManagedLabel.fromJson(row as Map))
        .toList();
  }
}
