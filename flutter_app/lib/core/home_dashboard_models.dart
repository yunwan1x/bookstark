import 'public_share_models.dart';

const homeModuleKeys = <String>[
  'notes',
  'articles',
  'tasks',
  'books',
  'bookmarks',
  'topics',
  'nav',
  'shares',
  'assets',
];

final class HomeLayoutItem {
  const HomeLayoutItem({
    required this.key,
    this.width = 1,
    this.hidden = false,
  });
  final String key;
  final int width;
  final bool hidden;
  HomeLayoutItem copyWith({int? width, bool? hidden}) => HomeLayoutItem(
    key: key,
    width: width ?? this.width,
    hidden: hidden ?? this.hidden,
  );
  Map<String, Object> toJson() => {
    'key': key,
    'width': width,
    'hidden': hidden,
  };
}

/// Keep all nine settings, including currently unavailable modules. Permissions
/// decide which cards are shown; they must not destroy an account's preferences.
List<HomeLayoutItem> readHomeLayout(Object? raw) {
  if (raw == null) {
    return [for (final key in homeModuleKeys) HomeLayoutItem(key: key)];
  }
  if (raw is! List || raw.length > homeModuleKeys.length) {
    throw const FormatException('Invalid home layout');
  }
  final seen = <String>{};
  final result = <HomeLayoutItem>[];
  for (final value in raw) {
    if (value is! Map ||
        value['key'] is! String ||
        value['width'] is! int ||
        !homeModuleKeys.contains(value['key']) ||
        !seen.add(value['key'] as String) ||
        (value['width'] as int) < 1 ||
        (value['width'] as int) > 3 ||
        (value.containsKey('hidden') && value['hidden'] is! bool)) {
      throw const FormatException('Invalid home layout');
    }
    result.add(
      HomeLayoutItem(
        key: value['key'] as String,
        width: value['width'] as int,
        hidden: value['hidden'] == true,
      ),
    );
  }
  for (final key in homeModuleKeys) {
    if (seen.add(key)) result.add(HomeLayoutItem(key: key));
  }
  return List.unmodifiable(result);
}

String homeDayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

DateTime readHomeDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid home date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || homeDayKey(parsed) != value || parsed.year < 1) {
    throw const FormatException('Invalid home date');
  }
  return parsed;
}

enum HomeCalendarView { day, week, month }

DateTime _homeMonth(DateTime? value) {
  final selected = value ?? DateTime.now();
  if (selected.year < 1 || selected.year > 9999) {
    throw const FormatException('Invalid home month');
  }
  return DateTime(selected.year, selected.month);
}

final class HomeQuery {
  HomeQuery({
    DateTime? month,
    this.order = 'updated',
    this.limit = 10,
    this.view = HomeCalendarView.day,
    String? end,
  }) : month = _homeMonth(month),
       end = end == null ? null : homeDayKey(readHomeDay(end)) {
    if (!['updated', 'created'].contains(order) ||
        ![5, 10, 20, 50].contains(limit)) {
      throw const FormatException('Invalid home filter');
    }
  }
  factory HomeQuery.readPreference(Object? raw) {
    if (raw is! Map ||
        raw['month'] is! String ||
        !RegExp(r'^\d{4}-\d{2}$').hasMatch(raw['month'] as String) ||
        raw['order'] is! String ||
        raw['limit'] is! int ||
        raw['view'] is! String ||
        (raw['end'] != null && raw['end'] is! String)) {
      throw const FormatException('Invalid saved home filter');
    }
    final view = HomeCalendarView.values.where((v) => v.name == raw['view']);
    if (view.length != 1) {
      throw const FormatException('Invalid saved home view');
    }
    return HomeQuery(
      month: readHomeDay('${raw['month']}-01'),
      order: raw['order'] as String,
      limit: raw['limit'] as int,
      view: view.single,
      end: raw['end'] as String?,
    );
  }
  Map<String, Object?> toPreference() => {
    'month': homeDayKey(month).substring(0, 7),
    'order': order,
    'limit': limit,
    'view': view.name,
    'end': end,
  };
  final DateTime month;
  final String order;
  final int limit;
  final HomeCalendarView view;
  final String? end;
  HomeQuery copyWith({
    DateTime? month,
    String? order,
    int? limit,
    HomeCalendarView? view,
    String? end,
    bool clearEnd = false,
  }) => HomeQuery(
    month: month ?? this.month,
    order: order ?? this.order,
    limit: limit ?? this.limit,
    view: view ?? this.view,
    end: clearEnd ? null : end ?? this.end,
  );
  String get apiPath => Uri(
    path: '/api/home',
    queryParameters: {
      'order': order,
      'limit': '$limit',
      'month': homeDayKey(month).substring(0, 7),
      'view': view.name,
      'end': ?end,
    },
  ).toString();
  HomeQuery movePeriod(int delta) => copyWith(
    month: DateTime(
      month.year + (view == HomeCalendarView.month ? delta : 0),
      month.month + (view == HomeCalendarView.month ? 0 : delta),
    ),
  );
}

final class HomeCalendarPeriod {
  const HomeCalendarPeriod(this.start, this.end);
  final DateTime start, end;
  String get cutoff => homeDayKey(end);
}

List<HomeCalendarPeriod> homeCalendarPeriods(HomeQuery query) {
  if (query.view == HomeCalendarView.month) {
    return [
      for (var m = 1; m <= 12; m++)
        HomeCalendarPeriod(
          DateTime(query.month.year, m),
          DateTime(query.month.year, m + 1, 0),
        ),
    ];
  }
  final first = DateTime(query.month.year, query.month.month);
  final last = DateTime(query.month.year, query.month.month + 1, 0);
  final begin = DateTime(
    first.year,
    first.month,
    1 - (first.weekday - DateTime.monday),
  );
  final finish = DateTime(
    last.year,
    last.month,
    last.day + DateTime.sunday - last.weekday,
  );
  final result = <HomeCalendarPeriod>[];
  var cursor = begin;
  while (!cursor.isAfter(finish)) {
    final end = query.view == HomeCalendarView.week
        ? DateTime(cursor.year, cursor.month, cursor.day + 6)
        : cursor;
    result.add(HomeCalendarPeriod(cursor, end));
    // Calendar arithmetic, rather than 24-hour instants, survives DST changes.
    cursor = DateTime(end.year, end.month, end.day + 1);
  }
  return List.unmodifiable(result);
}

final class HomeContentItem {
  const HomeContentItem({
    required this.id,
    required this.title,
    this.date = '',
    this.badge = '',
    this.shareIdentify,
  });
  final int id;
  final String title, date, badge;
  final String? shareIdentify;
  factory HomeContentItem.read(Object? raw, {String? module}) {
    if (raw is! Map ||
        raw['id'] is! int ||
        (raw['id'] as int) <= 0 ||
        raw['title'] is! String ||
        (raw['date'] != null && raw['date'] is! String) ||
        (raw['badge'] != null && raw['badge'] is! String)) {
      throw const FormatException('Invalid home item');
    }
    String? identify;
    if (module == 'shares') {
      final url = raw['url'] is String
          ? Uri.tryParse(raw['url'] as String)
          : null;
      if (url == null ||
          url.hasScheme ||
          url.hasAuthority ||
          url.hasQuery ||
          url.hasFragment ||
          !url.path.startsWith('/shares/') ||
          url.pathSegments.length != 2 ||
          !PublicShareReference.validIdentify(url.pathSegments[1])) {
        throw const FormatException('Invalid home share target');
      }
      identify = url.pathSegments[1];
    }
    // Only a validated share identifier is retained; never execute a URL.

    return HomeContentItem(
      id: raw['id'] as int,
      title: raw['title'] as String,
      date: raw['date'] as String? ?? '',
      badge: raw['badge'] as String? ?? '',
      shareIdentify: identify,
    );
  }
}

final class HomeContentSection {
  const HomeContentSection({
    required this.key,
    required this.total,
    required this.items,
  });
  final String key;
  final int total;
  final List<HomeContentItem> items;
  factory HomeContentSection.read(Object? raw) {
    if (raw is! Map ||
        !homeModuleKeys.contains(raw['key']) ||
        raw['total'] is! int ||
        (raw['total'] as int) < 0 ||
        raw['items'] is! List) {
      throw const FormatException('Invalid home section');
    }
    return HomeContentSection(
      key: raw['key'] as String,
      total: raw['total'] as int,
      items: List.unmodifiable(
        (raw['items'] as List).map(
          (item) => HomeContentItem.read(item, module: raw['key'] as String),
        ),
      ),
    );
  }
}

final class HomeRecentVisit {
  const HomeRecentVisit({
    required this.kind,
    required this.id,
    required this.title,
    this.context = '',
    this.visitedAt,
  });
  final String kind, title, context;
  final int id;
  final DateTime? visitedAt;
  String get route =>
      '${['note', 'article'].contains(kind) ? 'blog' : kind}/$id';
  static HomeRecentVisit? read(Object? raw) {
    if (raw is! Map ||
        ![
          'note',
          'article',
          'blog',
          'book',
          'document',
        ].contains(raw['type']) ||
        raw['id'] is! int ||
        (raw['id'] as int) <= 0 ||
        raw['title'] is! String) {
      return null;
    }
    final stamp = raw['visited_at'];
    return HomeRecentVisit(
      kind: raw['type'] as String,
      id: raw['id'] as int,
      title: raw['title'] as String,
      context: raw['context'] is String ? raw['context'] as String : '',
      visitedAt: stamp is String
          ? DateTime.tryParse(stamp)
          : stamp is int
          ? DateTime.fromMillisecondsSinceEpoch(stamp)
          : null,
    );
  }
}

final class HomeDashboardSnapshot {
  const HomeDashboardSnapshot({
    required this.layout,
    required this.sections,
    required this.recent,
    required this.activity,
    this.unknownDates = const {},
  });
  final List<HomeLayoutItem> layout;
  final List<HomeContentSection> sections;
  final List<HomeRecentVisit> recent;
  final Map<String, int> activity;
  final Map<String, int> unknownDates;
  factory HomeDashboardSnapshot.read(Map<String, Object?> raw) {
    if (raw['sections'] is! List ||
        raw['recent'] is! List ||
        raw['activity'] is! Map) {
      throw const FormatException('Invalid home summary');
    }
    final sections = (raw['sections'] as List)
        .map(HomeContentSection.read)
        .toList();
    if (sections.map((e) => e.key).toSet().length != sections.length) {
      throw const FormatException('Duplicate home section');
    }
    final activity = <String, int>{};
    for (final entry in (raw['activity'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          (entry.value as int) < 0) {
        throw const FormatException('Invalid home activity');
      }
      activity[homeDayKey(readHomeDay(entry.key as String))] =
          entry.value as int;
    }
    return HomeDashboardSnapshot(
      layout: readHomeLayout(raw['layout']),
      sections: List.unmodifiable(sections),
      recent: List.unmodifiable(
        (raw['recent'] as List)
            .map(HomeRecentVisit.read)
            .whereType<HomeRecentVisit>(),
      ),
      activity: Map.unmodifiable(activity),
    );
  }
  HomeDashboardSnapshot withLayout(List<HomeLayoutItem> value) =>
      HomeDashboardSnapshot(
        layout: List.unmodifiable(value),
        sections: sections,
        recent: recent,
        activity: activity,
        unknownDates: unknownDates,
      );
  HomeDashboardSnapshot withoutVisits() => HomeDashboardSnapshot(
    layout: layout,
    sections: sections,
    recent: const [],
    activity: activity,
    unknownDates: unknownDates,
  );
}
