/// Public discovery is a remote service, distinct from personal resource lists.
enum PublicFeedKind { article, note, book, bookmark }

enum PublicFeedSort { latest, updated }

class PublicFeedQuery {
  PublicFeedQuery({
    this.kind = PublicFeedKind.article,
    this.sort = PublicFeedSort.latest,
    this.label = '',
    this.keyword = '',
    this.page = 1,
  }) {
    if (page < 1 ||
        page > 100000 ||
        keyword.length > 200 ||
        label.length > 1000 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch('$label$keyword')) {
      throw const FormatException('无效广场筛选条件 / Invalid public feed filter');
    }
  }
  final PublicFeedKind kind;
  final PublicFeedSort sort;
  final String label, keyword;
  final int page;
  String get requestPath =>
      '/shares?${Uri(queryParameters: {'type': kind.name, 'sort': sort.name, if (label.isNotEmpty) 'label': label, if (keyword.isNotEmpty) 'keyword': keyword, 'page': '$page'}).query}';

  /// Interpret only the server's fixed discovery route. This never follows a
  /// link and rejects duplicate keys before Uri.queryParameters can hide them.
  static PublicFeedQuery fromNavigation(String href, {required Uri server}) {
    final uri = Uri.parse(href);
    final root = server.path.replaceFirst(RegExp(r'/+$'), '');
    if (uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        href.startsWith('//') ||
        uri.hasAuthority &&
            (uri.scheme != server.scheme ||
                uri.host != server.host ||
                uri.port != server.port) ||
        uri.hasScheme && !uri.hasAuthority ||
        !{'/shares', '$root/shares'}.contains(uri.path)) {
      throw const FormatException('Invalid public navigation route');
    }
    const allowed = {'type', 'sort', 'label', 'keyword', 'page'};
    final all = uri.queryParametersAll;
    if (all.keys.any((key) => !allowed.contains(key)) ||
        all.values.any((values) => values.length != 1)) {
      throw const FormatException('Invalid public navigation parameters');
    }
    final values = uri.queryParameters;
    final kindName = values['type'] ?? 'article';
    final sortName = values['sort'] ?? 'latest';
    final pageText = values['page'] ?? '1';
    if (!PublicFeedKind.values.any((kind) => kind.name == kindName) ||
        !PublicFeedSort.values.any((sort) => sort.name == sortName) ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(pageText)) {
      throw const FormatException('Invalid public navigation filter');
    }
    final page = int.tryParse(pageText);
    if (page == null) {
      throw const FormatException('Invalid public navigation page');
    }
    return PublicFeedQuery(
      kind: PublicFeedKind.values.byName(kindName),
      sort: PublicFeedSort.values.byName(sortName),
      label: values['label'] ?? '',
      keyword: values['keyword'] ?? '',
      page: page,
    );
  }

  PublicFeedQuery copyWith({
    PublicFeedKind? kind,
    PublicFeedSort? sort,
    String? label,
    String? keyword,
    int? page,
  }) => PublicFeedQuery(
    kind: kind ?? this.kind,
    sort: sort ?? this.sort,
    label: label ?? this.label,
    keyword: keyword ?? this.keyword,
    page: page ?? this.page,
  );
  @override
  bool operator ==(Object other) =>
      other is PublicFeedQuery &&
      other.kind == kind &&
      other.sort == sort &&
      other.label == label &&
      other.keyword == keyword &&
      other.page == page;
  @override
  int get hashCode => Object.hash(kind, sort, label, keyword, page);
}

class PublicFeedCategory {
  const PublicFeedCategory({required this.label, required this.selected});

  /// Empty string is the server's unfiltered category, not a fabricated label.
  final String label;
  final bool selected;
}

class PublicFeedItem {
  PublicFeedItem({
    required this.kind,
    required this.identity,
    required this.title,
    required this.author,
    required this.date,
    required this.format,
    required this.locked,
    required this.pinned,
    required String excerpt,
    required List<String> labels,
    this.shareIdentify,
    this.externalUri,
    this.manageTargetId,
    this.manageType,
  }) : excerpt = locked ? '' : excerpt,
       labels = List.unmodifiable(locked ? <String>[] : labels) {
    if (identity.isEmpty) {
      throw const FormatException('Invalid public resource identity');
    }
    if (kind == PublicFeedKind.bookmark) {
      if (externalUri == null ||
          !{'http', 'https'}.contains(externalUri!.scheme) ||
          externalUri!.host.isEmpty ||
          externalUri!.userInfo.isNotEmpty ||
          shareIdentify != null) {
        throw const FormatException('Invalid public bookmark URL');
      }
    } else if (shareIdentify == null ||
        shareIdentify!.isEmpty ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(shareIdentify!) ||
        externalUri != null) {
      throw const FormatException('Invalid public share identifier');
    }
    if ((manageTargetId == null) != (manageType == null) ||
        manageTargetId != null && manageTargetId! <= 0 ||
        manageType != null &&
            manageType !=
                (kind == PublicFeedKind.article || kind == PublicFeedKind.note
                    ? 'blog'
                    : kind.name)) {
      throw const FormatException('Invalid public management identity');
    }
  }
  final PublicFeedKind kind;

  /// A typed opaque identity. Public bookmarks do not always expose numeric IDs;
  /// public blogs without md_shares rows may have negative API share IDs.
  final String identity, title, author, date, format, excerpt;
  final bool locked, pinned;
  final List<String> labels;
  final String? shareIdentify, manageType;
  final Uri? externalUri;
  final int? manageTargetId;
}

class PublicFeedPageData {
  PublicFeedPageData({
    required this.query,
    required List<PublicFeedItem> items,
    required List<PublicFeedCategory> categories,
    required this.previous,
    required this.next,
  }) : items = List.unmodifiable(items),
       categories = List.unmodifiable(categories) {
    if (items.map((item) => item.identity).toSet().length != items.length ||
        categories.map((category) => category.label).toSet().length !=
            categories.length ||
        categories.where((category) => category.selected).length > 1 ||
        categories
            .where((category) => category.selected)
            .any((category) => category.label != query.label) ||
        !categories.any((category) => category.label.isEmpty) ||
        categories.any(
          (category) => category.label == query.label && !category.selected,
        ) ||
        items.any((item) => item.kind != query.kind)) {
      throw const FormatException('Invalid public feed membership');
    }
    for (final neighbor in [previous, next]) {
      if (neighbor != null &&
          (neighbor.kind != query.kind ||
              neighbor.sort != query.sort ||
              neighbor.label != query.label ||
              neighbor.keyword != query.keyword)) {
        throw const FormatException('Public pagination changed filters');
      }
    }
    if (previous != null && previous!.page != query.page - 1 ||
        next != null && next!.page != query.page + 1) {
      throw const FormatException('Invalid public page boundary');
    }
  }
  final PublicFeedQuery query;
  final List<PublicFeedItem> items;
  final List<PublicFeedCategory> categories;
  final PublicFeedQuery? previous, next;

  /// The old server HTML provides actual adjacent pages, not a global total.
  int get loadedCount => items.length;
}
