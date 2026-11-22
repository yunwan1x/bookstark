import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:bookstark_flutter/core/home_dashboard_repository.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/home_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DashboardRepository implements HomeDashboardRepository {
  var value = HomeDashboardSnapshot(
    layout: readHomeLayout(null),
    sections: const [
      HomeContentSection(
        key: 'notes',
        total: 1,
        items: [
          HomeContentItem(id: 7, title: 'Module note', date: '2026-11-10'),
        ],
      ),
      HomeContentSection(key: 'articles', total: 0, items: []),
    ],
    recent: const [
      HomeRecentVisit(kind: 'note', id: 17, title: 'Visited note'),
    ],
    activity: const {'2026-11-10': 1},
  );
  final queries = <HomeQuery>[];
  int clears = 0, saves = 0;
  bool loseReceipt = false, corruptPreferences = false;
  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) async {
    queries.add(query);
    if (corruptPreferences) throw const HomePreferencesCorrupt();
    return value;
  }

  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> items, {
    Future<void>? abortTrigger,
  }) async {
    saves++;
    value = value.withLayout(items);
    return items;
  }

  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) async {
    clears++;
    value = value.withoutVisits();
    if (loseReceipt) throw const HomeWriteUnconfirmed();
  }
}

Future<void> mount(
  WidgetTester t,
  DashboardRepository repo, {
  List<String>? routes,
  bool large = false,
  bool local = false,
  Future<void> Function()? reset,
}) async {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = large ? const Size(640, 1280) : const Size(780, 1688);
  t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: HomeDashboardPage(
        repository: repo,
        strings: AppStrings(english: large),
        local: local,
        onResetLocalPreferences: reset,
        initialQuery: HomeQuery(month: DateTime(2026, 11)),
        onLanguage: () {},
        onNavigate: (route) => routes?.add(route),
        onOpenAll: (key) => routes?.add('all/$key'),
        onOpenItem: (key, item) => routes?.add('$key/${item.id}'),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder target, {bool up = false}) async {
  await t.scrollUntilVisible(
    target,
    up ? -180 : 180,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'recent identity and content item use typed callbacks with real module data',
    (t) async {
      final repo = DashboardRepository();
      final routes = <String>[];
      await mount(t, repo, routes: routes);
      await reveal(t, find.text('Visited note'));
      await t.tap(find.text('Visited note'));
      await t.pumpAndSettle();
      expect(routes.single, 'blog/17');
      await reveal(t, find.text('Module note'));
      await t.tap(find.text('Module note'));
      await t.pumpAndSettle();
      expect(routes.last, 'notes/7');
      expect(repo.queries.length, 1);
      expect(repo.clears, 0);
      expect(repo.saves, 0);
    },
  );
  testWidgets(
    'clear cancellation has no write and confirmation removes only visits',
    (t) async {
      final repo = DashboardRepository();
      await mount(t, repo);
      await reveal(t, find.byKey(const Key('home-clear-visits')));
      await t.tap(find.byKey(const Key('home-clear-visits')));
      await t.pumpAndSettle();
      expect(find.text('清空最近访问？'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(repo.clears, 0);
      await t.tap(find.byKey(const Key('home-clear-visits')));
      await t.pumpAndSettle();
      await t.tap(find.text('清空记录'));
      await t.pumpAndSettle();
      expect(repo.clears, 1);
      expect(find.byKey(const Key('home-clear-visits')), findsNothing);
      await reveal(t, find.text('Module note'));
      expect(find.text('Module note'), findsOneWidget);
      expect(repo.value.sections.first.total, 1);
    },
  );
  testWidgets(
    'applied clear with lost receipt requires explicit readback and never replays',
    (t) async {
      final repo = DashboardRepository()..loseReceipt = true;
      await mount(t, repo);
      await reveal(t, find.byKey(const Key('home-clear-visits')));
      await t.tap(find.byKey(const Key('home-clear-visits')));
      await t.pumpAndSettle();
      await t.tap(find.text('清空记录'));
      await t.pumpAndSettle();
      expect(repo.clears, 1);
      await reveal(t, find.text('重新读取核对'), up: true);
      await t.tap(find.text('重新读取核对'));
      await t.pumpAndSettle();
      expect(repo.clears, 1);
      expect(repo.queries.length, 2);
      await reveal(t, find.text('最近访问'));
      expect(find.byKey(const Key('home-clear-visits')), findsNothing);
    },
  );
  testWidgets(
    'English 320dp 200 percent filters and content remain scrollable',
    (t) async {
      final repo = DashboardRepository();
      await mount(t, repo, large: true);
      await reveal(t, find.byKey(const ValueKey('home-limit-10')));
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('home-limit-10')));
      await t.pumpAndSettle();
      await t.tap(find.text('20 per module').last);
      await t.pumpAndSettle();
      expect(repo.queries.last.limit, 20);
      await reveal(t, find.text('Module note'));
      expect(t.takeException(), isNull);
      expect(repo.clears, 0);
      expect(repo.saves, 0);
    },
  );
  testWidgets(
    'corrupt local preferences require confirmed reset and restore default filters',
    (t) async {
      final repo = DashboardRepository()..corruptPreferences = true;
      var resets = 0;
      await mount(
        t,
        repo,
        local: true,
        reset: () async {
          resets++;
          repo.corruptPreferences = false;
        },
      );
      await t.tap(find.text('重置首页偏好'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(resets, 0);
      await t.tap(find.text('重置首页偏好'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, '重置首页偏好').last);
      await t.pumpAndSettle();
      expect(resets, 1);
      expect(repo.queries.last.order, 'updated');
      expect(repo.queries.last.limit, 10);
      expect(repo.queries.last.end, isNull);
      expect(find.text('重置首页偏好'), findsNothing);
      expect(repo.clears, 0);
    },
  );
}
