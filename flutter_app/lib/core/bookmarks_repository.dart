import 'dart:convert';
import 'api_client.dart';
import 'resource_labels.dart';

Uri bookmarkUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value) ||
      (uri.hasPort && (uri.port <= 0 || uri.port > 65535))) {
    throw const FormatException(
      '请输入不含账号的HTTP/HTTPS网址 / Enter an HTTP(S) URL without credentials',
    );
  }
  return uri;
}

class BookmarkItem {
  const BookmarkItem({
    this.id,
    required this.title,
    required this.url,
    this.description = '',
    this.favicon = '',
    this.labels = const [],
    this.memberId = 0,
    this.account = '',
    this.isPublic = false,
    this.isPinned = false,
    this.navVisible = false,
    this.order = 0,
    this.createdAt,
    this.modifiedAt,
  });
  final int? id;
  final int memberId, order;
  final String title, url, description, favicon, account;
  final List<String> labels;
  final bool isPublic, isPinned, navVisible;
  final DateTime? createdAt, modifiedAt;
  factory BookmarkItem.fromJson(Map row) => BookmarkItem(
    id: row['bookmark_id'] as int,
    memberId: row['member_id'] as int,
    title: row['title'] as String? ?? '',
    url: row['url'] as String? ?? '',
    description: row['description'] as String? ?? '',
    favicon: row['favicon'] as String? ?? '',
    labels: List.unmodifiable((row['labels'] as List? ?? []).cast<String>()),
    account: row['account'] as String? ?? '',
    order: row['order_sort'] as int? ?? 0,
    isPublic: row['is_public'] as bool? ?? false,
    isPinned: row['is_pinned'] as bool? ?? false,
    navVisible: row['nav_visible'] as bool? ?? false,
    createdAt: _time(row['create_time']),
    modifiedAt: _time(row['modify_time']),
  );
  static DateTime? _time(Object? value) =>
      value is String && !value.startsWith('0001-')
      ? DateTime.tryParse(value)
      : null;
  BookmarkItem copyWith({
    int? id,
    int? memberId,
    String? title,
    String? url,
    String? description,
    String? favicon,
    List<String>? labels,
    bool? isPublic,
    bool? isPinned,
    bool? navVisible,
    int? order,
  }) => BookmarkItem(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    title: title ?? this.title,
    url: url ?? this.url,
    description: description ?? this.description,
    favicon: favicon ?? this.favicon,
    labels: labels ?? this.labels,
    isPublic: isPublic ?? this.isPublic,
    isPinned: isPinned ?? this.isPinned,
    navVisible: navVisible ?? this.navVisible,
    order: order ?? this.order,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    account: account,
  );
  void validate() {
    if (id != null && id! <= 0) {
      throw const FormatException('Invalid bookmark ID');
    }
    bookmarkUri(url);
    if (title.trim().isEmpty ||
        utf8.encode(title).length > 500 ||
        utf8.encode(url).length > 2048 ||
        utf8.encode(description).length > 2000) {
      throw const FormatException(
        '标题必填，最多500字节；网址2048字节；说明2000字节 / Name required: 500 UTF-8 bytes; URL: 2048; description: 2000',
      );
    }
  }

  Map<String, Object?> writeBody({
    bool includeUrl = true,
    bool arrayLabels = false,
  }) {
    validate();
    return {
      'title': title,
      if (includeUrl) 'url': url,
      'description': description,
      'is_public': isPublic,
      'labels': arrayLabels ? '' : encodeResourceLabels(labels),
      if (id == null && favicon.isNotEmpty) 'favicon': favicon,
    };
  }
}

enum BookmarkScope { mine, public }

class BookmarkQuery {
  const BookmarkQuery({
    this.scope = BookmarkScope.mine,
    this.keyword = '',
    this.labels = const [],
    this.labelsOr = const [],
    this.isPublic,
    this.isPinned,
    this.navVisible,
    this.noLabel = false,
    this.site = '',
    this.start,
    this.end,
    this.modified = false,
    this.page = 1,
  });
  final BookmarkScope scope;
  final String keyword, site;
  final List<String> labels, labelsOr;
  final bool? isPublic, isPinned, navVisible;
  final bool noLabel, modified;
  final DateTime? start, end;
  final int page;
  BookmarkQuery atPage(int page) => BookmarkQuery(
    scope: scope,
    keyword: keyword,
    labels: labels,
    labelsOr: labelsOr,
    isPublic: isPublic,
    isPinned: isPinned,
    navVisible: navVisible,
    noLabel: noLabel,
    site: site,
    start: start,
    end: end,
    modified: modified,
    page: page,
  );
  static String _timestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  Map<String, dynamic> parameters() {
    if (labels.any((name) => name.isEmpty)) {
      throw const FormatException(
        '旧接口无法筛选空名称标签 / Empty-name labels cannot be filtered by this API',
      );
    }
    if (page < 1 ||
        (scope == BookmarkScope.public && isPublic == false) ||
        (start != null && (start!.year < 1 || start!.year > 9999)) ||
        (end != null && (end!.year < 1 || end!.year > 9999)) ||
        (start != null && end != null && end!.isBefore(start!))) {
      throw const FormatException('Invalid bookmark query');
    }
    if (site.isNotEmpty) {
      final uri = bookmarkUri('https://$site/');
      if (uri.path != '/' || uri.hasQuery || uri.hasFragment) {
        throw const FormatException(
          '请输入站点域名，可含端口 / Enter a host, optionally with a port',
        );
      }
    }
    if (labelsOr.any((name) => name.trim() != name)) {
      throw const FormatException(
        '旧接口无法按原名处理带首尾空格的OR标签，请使用AND / Use AND for labels with surrounding whitespace',
      );
    }
    return {
      'scope': scope.name,
      'page': '$page',
      'keyword': keyword,
      if (labels.isNotEmpty) 'label': List.of(labels),
      if (labelsOr.isNotEmpty) 'labels_or': encodeResourceLabels(labelsOr),
      if (isPublic != null && scope == BookmarkScope.mine)
        'is_public': isPublic! ? '1' : '0',
      if (isPinned != null) 'is_pinned': isPinned! ? '1' : '0',
      if (navVisible != null) 'nav_visible': navVisible! ? '1' : '0',
      if (noLabel) 'no_label': '1',
      if (site.isNotEmpty) 'site': site,
      if (start != null) 'start_time': _timestamp(start!),
      if (end != null) 'end_time': _timestamp(end!),
      'time_field': modified ? 'modify' : 'create',
    };
  }
}

class BookmarkPageResult {
  const BookmarkPageResult(this.items, this.total, this.page, this.pageSize);
  final List<BookmarkItem> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

class BookmarkMetadata {
  const BookmarkMetadata({
    this.title = '',
    this.description = '',
    this.favicon = '',
    this.error,
  });
  final String title, description, favicon;
  final String? error;
}

class BookmarkAlreadyExists implements Exception {
  const BookmarkAlreadyExists(this.bookmark);
  final BookmarkItem bookmark;
  @override
  String toString() =>
      '已有相同网址的书签，请先确认编辑 / This URL already exists; confirm editing that bookmark';
}

class BookmarkSaveFailure implements Exception {
  const BookmarkSaveFailure(this.savedId, this.cause);
  final int savedId;
  final Object cause;
  @override
  String toString() =>
      '书签已保存，标签待核对 / Bookmark saved; labels need verification: $cause';
}

enum BookmarkBatch {
  delete,
  share,
  unshare,
  addLabels,
  removeLabels,
  pin,
  unpin,
  showNav,
  hideNav,
}

abstract interface class BookmarksRepository {
  int get memberId;
  bool get isAdmin;
  bool canEdit(BookmarkItem item);
  Future<BookmarkPageResult> list(BookmarkQuery query);
  Future<BookmarkItem?> findByUrl(String url);
  Future<BookmarkItem> read(int id);
  Future<int> save(BookmarkItem bookmark, {BookmarkItem? original});
  Future<BookmarkMetadata> metadata(String url);
  Future<void> remove(int id);
  Future<void> setPublic(int id, bool value);
  Future<void> setNavVisible(int id, bool value);
  Future<void> batch(
    BookmarkBatch action,
    List<int> ids, {
    List<String> labels = const [],
  });
  Future<void> sort(Map<int, int> order);
  Future<void> refreshFavicon(int id);
}

class RemoteBookmarksRepository implements BookmarksRepository {
  RemoteBookmarksRepository(
    this.client, {
    required this.memberId,
    this.isAdmin = false,
    this.isCurrent,
    this.createRecoverably,
  }) : _sessionRevision = client.sessionRevision {
    if (memberId <= 0) throw ArgumentError.value(memberId);
  }
  final BookstarkClient client;
  final Future<BookmarkItem> Function(BookmarkItem)? createRecoverably;
  final bool Function()? isCurrent;
  final int _sessionRevision;
  void _assertCurrent() {
    if (client.sessionRevision != _sessionRevision ||
        !(isCurrent?.call() ?? true)) {
      throw StateError('Bookmark owner changed; request was not replayed');
    }
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
  final int memberId;
  @override
  final bool isAdmin;
  @override
  bool canEdit(BookmarkItem item) => item.memberId == memberId || isAdmin;
  @override
  Future<BookmarkPageResult> list(BookmarkQuery query) async {
    final result = await client.get(
      '/api/bookmarks?${Uri(queryParameters: query.parameters()).query}',
    );
    final size = result['page_size'] as int;
    if (size < 1) throw const FormatException('Invalid bookmark page size');
    return BookmarkPageResult(
      (result['data'] as List? ?? [])
          .map((row) => BookmarkItem.fromJson(row as Map))
          .toList(),
      result['total'] as int,
      result['page'] as int,
      size,
    );
  }

  @override
  Future<BookmarkItem?> findByUrl(String url) async {
    bookmarkUri(url);
    var page = 1;
    while (true) {
      final result = await list(BookmarkQuery(keyword: url, page: page));
      for (final item in result.items) {
        if (item.url == url) return item;
      }
      if (!result.hasMore) return null;
      if (result.items.isEmpty || result.page != page) {
        throw const FormatException('Invalid bookmark pagination');
      }
      page++;
    }
  }

  @override
  Future<BookmarkItem> read(int id) async {
    if (id <= 0) throw const FormatException('Invalid bookmark ID');
    // The compatibility endpoint exposes no owner/pin/nav/order metadata.
    // Resolve its URL to the canonical list row instead of fabricating flags.
    final detail = await client.get('/api/bookmarks/$id/');
    final url = detail['url'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('Invalid bookmark detail');
    }
    for (final scope in BookmarkScope.values) {
      var page = 1;
      while (true) {
        final result = await list(
          BookmarkQuery(scope: scope, keyword: url, page: page),
        );
        for (final item in result.items) {
          if (item.id == id) return item;
        }
        if (!result.hasMore) break;
        if (result.items.isEmpty || result.page != page) {
          throw const FormatException('Invalid bookmark pagination');
        }
        page++;
      }
    }
    throw StateError(
      '无法加载书签完整资料，请刷新核对 / Canonical bookmark unavailable; reload to verify',
    );
  }

  @override
  Future<int> save(BookmarkItem bookmark, {BookmarkItem? original}) async {
    if (original != null &&
        (original.id != bookmark.id || bookmark.id == null)) {
      throw const FormatException('Original bookmark ID mismatch');
    }
    final arrayLabels = bookmark.labels.any(
      (name) => name.isEmpty || name.contains(RegExp('[,，]')),
    );
    final body = bookmark.writeBody(
      includeUrl: original == null || original.url != bookmark.url,
      arrayLabels: arrayLabels,
    );
    if (bookmark.id != null && !canEdit(bookmark)) {
      throw StateError('无权修改此书签 / Cannot edit this bookmark');
    }
    if (bookmark.id == null && createRecoverably != null) {
      // The durable account slot must run before legacy URL preflight: editing
      // URL cannot bypass a previous unknown creation or silently authorize POST.
      _assertCurrent();
      final actual = await createRecoverably!(bookmark);
      _assertCurrent();
      if (actual.id == null || actual.id! <= 0 || actual.memberId != memberId) {
        throw const FormatException('Actual owned creation receipt required');
      }
      // New endpoint atomically binds exact labels; do not replay legacy
      // follow-up PUTs over a complete transactional receipt.
      return actual.id!;
    }
    if (bookmark.id == null) {
      final duplicate = await findByUrl(bookmark.url);
      if (duplicate != null) throw BookmarkAlreadyExists(duplicate);
    }
    final int id;
    if (bookmark.id == null) {
      id = (await _write('POST', '/api/bookmarks', body))['bookmark_id'] as int;
    } else {
      id = bookmark.id!;
      await _write('PUT', '/api/bookmarks/$id', body);
    }
    try {
      if (arrayLabels) {
        // Canonical save clears the CSV relation first. Bookmark batch labels
        // bind exact array names atomically, including commas and whitespace.
        // Keep the real ID on any later failure so retry restores these names.
        final names = bookmark.labels.toSet().toList();
        for (var offset = 0; offset < names.length; offset += 50) {
          await batch(
            BookmarkBatch.addLabels,
            [id],
            labels: names.sublist(offset, (offset + 50).clamp(0, names.length)),
          );
        }
      } else {
        await _write('PUT', '/api/labels/resource/bookmark/$id', {
          'labels': body['labels'],
        });
      }
      final result = await client.get('/api/labels/resource/bookmark/$id');
      final actual = (result['data'] as List? ?? []).cast<String>().toSet(),
          expected = bookmark.labels.toSet();
      if (actual.length != expected.length || !actual.containsAll(expected)) {
        throw StateError('标签核对失败 / Label verification failed');
      }
    } catch (error) {
      throw BookmarkSaveFailure(id, error);
    }
    return id;
  }

  @override
  Future<BookmarkMetadata> metadata(String url) async {
    bookmarkUri(url);
    final result = await _write('POST', '/api/fetch-meta', {'url': url});
    return BookmarkMetadata(
      title: result['title'] as String? ?? '',
      description: result['description'] as String? ?? '',
      favicon: result['favicon'] as String? ?? '',
      error: result['error'] as String?,
    );
  }

  @override
  Future<void> remove(int id) async {
    await _write('DELETE', '/api/bookmarks/$id', {});
  }

  @override
  Future<void> setPublic(int id, bool value) async {
    await _write('PATCH', '/api/bookmarks/$id/public', {'is_public': value});
  }

  @override
  Future<void> setNavVisible(int id, bool value) async {
    await _write('PATCH', '/api/bookmarks/$id/nav-visible', {
      'nav_visible': value,
    });
  }

  @override
  Future<void> batch(
    BookmarkBatch action,
    List<int> ids, {
    List<String> labels = const [],
  }) async {
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
    final route = const {
      BookmarkBatch.delete: 'delete',
      BookmarkBatch.share: 'share',
      BookmarkBatch.unshare: 'unshare',
      BookmarkBatch.addLabels: 'add-labels',
      BookmarkBatch.removeLabels: 'remove-labels',
      BookmarkBatch.pin: 'pin',
      BookmarkBatch.unpin: 'unpin',
      BookmarkBatch.showNav: 'show-nav',
      BookmarkBatch.hideNav: 'hide-nav',
    }[action]!;
    final result = await _write('POST', '/api/bookmarks/batch-$route', {
      'ids': ids,
      if (labels.isNotEmpty) 'tags': labels,
    });
    if (result['count'] != ids.length) {
      throw StateError(
        '批量结果数量不一致，请刷新核对 / Batch count differs; reload to verify',
      );
    }
  }

  @override
  Future<void> sort(Map<int, int> order) async {
    if (order.isEmpty ||
        order.length > 200 ||
        order.keys.any((id) => id <= 0)) {
      throw const FormatException('Invalid bookmark sort');
    }
    await _write('PATCH', '/api/bookmarks/sort', {
      'items': [
        for (final entry in order.entries)
          {'id': entry.key, 'order_sort': entry.value},
      ],
    });
  }

  @override
  Future<void> refreshFavicon(int id) async {
    await _write('PATCH', '/api/bookmarks/$id/favicon', {});
  }
}
