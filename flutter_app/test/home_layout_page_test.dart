import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:bookstark_flutter/core/home_dashboard_repository.dart';
import 'package:bookstark_flutter/features/home_dashboard_controller.dart';
import 'package:bookstark_flutter/features/home_layout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LayoutRepository implements HomeDashboardRepository {
  var value = HomeDashboardSnapshot(
    layout: readHomeLayout([
      {'key': 'assets', 'width': 3, 'hidden': true},
      {'key': 'notes', 'width': 1, 'hidden': false},
      {'key': 'articles', 'width': 2, 'hidden': false},
    ]),
    sections: const [
      HomeContentSection(key: 'notes', total: 0, items: []),
      HomeContentSection(key: 'articles', total: 0, items: []),
    ],
    recent: const [],
    activity: const {},
  );
  int saves = 0;
  bool loseReceipt = false;
  List<HomeLayoutItem>? submitted;
  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) async => value;
  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> desired, {
    Future<void>? abortTrigger,
  }) async {
    saves++;
    submitted = List.of(desired);
    value = value.withLayout(desired);
    if (loseReceipt) throw const HomeWriteUnconfirmed();
    return desired;
  }

  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) async =>
      throw StateError('Not part of layout editing');
}

Future<void> mount(
  WidgetTester t,
  HomeDashboardController controller, {
  bool large = false,
}) async {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = large ? const Size(640, 1280) : const Size(780, 1688);
  t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await controller.load();
  await t.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => HomeLayoutPage(
                  controller: controller,
                  english: large,
                  scopeLabel: large ? 'Current account' : '当前账号',
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open editor'));
  await t.pumpAndSettle();
}

Future<void> toggleNotes(WidgetTester t) async {
  final toggle = find.descendant(
    of: find.byKey(const ValueKey('home-layout-notes')),
    matching: find.byType(Switch),
  );
  await t.scrollUntilVisible(
    toggle,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.tap(toggle);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'draft edits require explicit save, discard cancellation preserves draft and unavailable module',
    (t) async {
      final repo = LayoutRepository();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      await mount(t, c);
      await toggleNotes(t);
      expect(repo.saves, 0);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('放弃未保存的布局？'), findsOneWidget);
      await t.tap(find.text('继续编辑'));
      await t.pumpAndSettle();
      final toggle = t.widget<Switch>(
        find.descendant(
          of: find.byKey(const ValueKey('home-layout-notes')),
          matching: find.byType(Switch),
        ),
      );
      expect(toggle.value, false);
      expect(repo.saves, 0);
      final move = find.byTooltip('上移 文章');
      await t.scrollUntilVisible(
        move,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(move);
      await t.pumpAndSettle();
      await t.tap(find.text('保存布局'));
      await t.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
      expect(repo.saves, 1);
      expect(repo.submitted!.length, 9);
      expect(repo.submitted!.first.toJson(), {
        'key': 'assets',
        'width': 3,
        'hidden': true,
      });
      expect(repo.submitted![1].key, 'articles');
      expect(repo.submitted![2].hidden, true);
    },
  );
  testWidgets(
    'lost receipt requires readback and matching server result never resubmits',
    (t) async {
      final repo = LayoutRepository()..loseReceipt = true;
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      await mount(t, c);
      await toggleNotes(t);
      await t.tap(find.text('保存布局'));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('重新读取核对'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存布局'))
            .onPressed,
        isNull,
      );
      await t.tap(find.text('重新读取核对'));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('已重新读取，服务器布局与草稿一致。'), findsOneWidget);
      await t.tap(find.text('返回首页'));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('Open editor'), findsOneWidget);
    },
  );
  testWidgets(
    'English 320dp 200 percent layout controls scroll without overflow',
    (t) async {
      final repo = LayoutRepository();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      await mount(t, c, large: true);
      await toggleNotes(t);
      expect(t.takeException(), isNull);
      final move = find.byTooltip('Move up Articles');
      await t.scrollUntilVisible(
        move,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(move);
      await t.pumpAndSettle();
      await t.tap(find.text('Save layout'));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(t.takeException(), isNull);
    },
  );
}
