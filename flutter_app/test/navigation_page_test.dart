import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/navigation_preferences.dart';
import 'package:bookstark_flutter/features/navigation/navigation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/navigation.dart';

void main() {
  testWidgets(
    'navigation group selection keeps pinned and persists per namespace',
    (tester) async {
      final repo = navigationBookmarksFixture();
      final values = <String, String>{};
      final preferences = NavigationPreferencesVault(
        namespace: 'test',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: NavigationPage(
            repository: NavigationFixture(repo),
            bookmarks: repo,
            labels: repo,
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前显示5条 · 已加载5条'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, '开发'));
      await tester.pumpAndSettle();
      expect(find.text('当前显示4条 · 已加载5条'), findsOneWidget);
      expect(find.text('Flutter 开发文档'), findsOneWidget);
      expect(find.text('未分组  1'), findsNothing);
      expect((await preferences.read()).groups, {'开发'});
      expect(repo.saves, 0);
    },
  );
  testWidgets('navigation hide confirms and changes only visible flag', (
    tester,
  ) async {
    final repo = navigationBookmarksFixture();
    final original = repo.items[1]!;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: NavigationPage(
          repository: NavigationFixture(repo),
          bookmarks: repo,
          labels: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('快捷收藏操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从导航隐藏'));
    await tester.pumpAndSettle();
    expect(repo.items[1]!.navVisible, isTrue);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('Flutter 开发文档'), findsNothing);
    expect(repo.items[1]!.navVisible, isFalse);
    expect(repo.items[1]!.isPinned, original.isPinned);
    expect(repo.items[1]!.url, original.url);
    expect(find.text('当前显示4条 · 已加载4条'), findsOneWidget);
  });
  testWidgets('bad preferences do not block navigation and can be reset', (
    tester,
  ) async {
    final repo = navigationBookmarksFixture();
    String? value = '{broken';
    final preferences = NavigationPreferencesVault(
      namespace: 'test',
      readValue: (_) async => value,
      writeValue: (_, next) async {
        value = next;
      },
      deleteValue: (_) async {
        value = null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: NavigationPage(
          repository: NavigationFixture(repo),
          bookmarks: repo,
          labels: repo,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前显示5条 · 已加载5条'), findsOneWidget);
    await tester.tap(find.text('重置显示偏好'));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('重置显示偏好'), findsNothing);
  });
  testWidgets('English navigation supports 320dp 200 percent text and scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = navigationBookmarksFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NavigationPage(
          repository: NavigationFixture(repo),
          bookmarks: repo,
          labels: repo,
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Manage bookmarks'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('个人知识库'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
