import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topic_calendar_page.dart';
import 'package:bookstark_flutter/widgets/month_activity_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/topics.dart';

void main() {
  testWidgets(
    'topic calendar shows activity categories and filters only after confirmation',
    (tester) async {
      final repo = TopicsFixture();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TopicCalendarPage(
                        repository: repo,
                        selectedDate: '2026-11-04',
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('2026-11-04 · 7项活动'), findsOneWidget);
      expect(find.text('主题1'), findsOneWidget);
      expect(find.text('小结2'), findsOneWidget);
      expect(find.text('资料3'), findsOneWidget);
      expect(find.text('任务1'), findsOneWidget);
      expect(selected, isNull);
      expect(repo.saveCalls, 0);
      await tester.scrollUntilVisible(
        find.text('筛选此日期'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('筛选此日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选此日期'));
      await tester.pumpAndSettle();
      expect(selected, '2026-11-04');
    },
  );
  testWidgets('failed calendar counts are unavailable instead of fake zeros', (
    tester,
  ) async {
    final repo = TopicsFixture()..failCounts = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicCalendarPage(repository: repo, selectedDate: '2026-11-04'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MonthActivityGrid>(find.byType(MonthActivityGrid))
          .countsUnavailable,
      isTrue,
    );
    expect(find.text('2026-11-04 · 0项活动'), findsNothing);
    repo.failCounts = false;
    await tester.ensureVisible(find.text('重试活动计数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试活动计数'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-04 · 7项活动'), findsOneWidget);
  });
  testWidgets('old month response cannot replace current month counts', (
    tester,
  ) async {
    final old = Completer<List<TopicDailyCount>>(),
        current = Completer<List<TopicDailyCount>>();
    final repo = TopicsFixture()
      ..countsOverride = (year, month) =>
          month == 11 ? old.future : current.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicCalendarPage(repository: repo, selectedDate: '2026-11-04'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('下个月'));
    await tester.pump();
    current.complete([]);
    await tester.pumpAndSettle();
    old.complete([const TopicDailyCount('2026-11-04', 7, 1, 2, 3, 1)]);
    await tester.pumpAndSettle();
    final grid = tester.widget<MonthActivityGrid>(
      find.byType(MonthActivityGrid),
    );
    expect(grid.month.month, 12);
    expect(grid.counts, isEmpty);
    expect(find.text('2026-12-01 · 0项活动'), findsOneWidget);
  });
  testWidgets('calendar boundaries and English large text remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = TopicsFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: TopicCalendarPage(
          repository: repo,
          selectedDate: '1970-01-01',
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Previous month',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.text('Filter by this date'),
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
