import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/tasks_page.dart';
import 'package:bookstark_flutter/features/tasks/task_card.dart';
import 'package:bookstark_flutter/features/tasks/task_month_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/tasks.dart';

Finder markdown(String data) => find.byWidgetPredicate(
  (widget) => widget is MarkdownBody && widget.data == data,
);
Future<void> mount(
  WidgetTester tester,
  TaskFixture repository, {
  bool calendar = false,
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: TasksPage(
        repository: repository,
        clock: () => repository.now,
        calendar: calendar,
        english: english,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'filtered-out parent never hides matching descendants; inline child toggles its own ID',
    (tester) async {
      final repository = TaskFixture();
      final due = taskDate(repository.now);
      repository.records[5] = TaskItem(
        id: 5,
        content: '孙待办仍需显示',
        dueDate: due,
        parentId: 2,
      );
      repository.records[99] = TaskItem(
        id: 99,
        content: '已完成的父级',
        dueDate: due,
        done: true,
      );
      repository.records[6] = TaskItem(
        id: 6,
        content: '命中未完成的子级',
        dueDate: due,
        parentId: 99,
      );
      await mount(tester, repository);
      expect(markdown('每天阅读20分钟'), findsOneWidget);
      expect(markdown('记录一个可执行的观点'), findsOneWidget);
      await tester.scrollUntilVisible(
        markdown('命中未完成的子级'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(markdown('孙待办仍需显示'), findsOneWidget);
      expect(markdown('命中未完成的子级'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(markdown('记录一个可执行的观点'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(repository.doneCalls.single, (2, true));
      expect(repository.records[1]!.done, isFalse);
      expect(repository.records[2]!.done, isTrue);
    },
  );
  testWidgets(
    'completion waits for actual response and failed mutation requires successful refresh',
    (tester) async {
      final repository = TaskFixture()..doneGate = Completer<void>();
      await mount(tester, repository);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isFalse,
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged,
        isNull,
      );
      repository.failDone = true;
      repository.doneGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.records[1]!.done, isFalse);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged,
        isNull,
      );
      expect(repository.doneCalls.length, 1);
      repository.failDone = false;
      await tester.tap(find.text('重试刷新'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged,
        isNotNull,
      );
      expect(repository.doneCalls.length, 1);
    },
  );
  testWidgets(
    'mutating a loaded page refetches all loaded pages so shifted records are not skipped',
    (tester) async {
      final repository = TaskFixture(sample: false);
      for (var id = 1; id <= 61; id++) {
        repository.records[id] = TaskItem(
          id: id,
          content: 'Task $id',
          dueDate: '2026-11-08',
        );
      }
      await mount(tester, repository);
      await tester.scrollUntilVisible(
        find.text('加载更多'),
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 50,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 20000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        markdown('Task 1'),
        -500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 50,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(repository.queries.map((query) => query.page), [1, 2, 1, 2]);
      await tester.scrollUntilVisible(
        markdown('Task 61'),
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 50,
      );
      await tester.pumpAndSettle();
      expect(markdown('Task 61'), findsOneWidget);
      expect(repository.doneCalls.single, (1, true));
    },
  );
  testWidgets('older task search cannot overwrite the current search', (
    tester,
  ) async {
    final repository = TaskFixture(sample: false)
      ..delayedSearch = Completer<TaskPage>();
    repository.records[1] = const TaskItem(
      id: 1,
      content: '新结果',
      dueDate: '2026-11-08',
    );
    await mount(tester, repository);
    await tester.enterText(find.byKey(const Key('task-search')), '旧');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('task-search')), '新');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    repository.delayedSearch!.complete(
      TaskPage(
        items: [const TaskItem(id: 2, content: '旧结果', dueDate: '2026-11-08')],
        total: 1,
        page: 1,
        pageSize: 30,
      ),
    );
    await tester.pumpAndSettle();
    expect(markdown('新结果'), findsOneWidget);
    expect(markdown('旧结果'), findsNothing);
  });
  testWidgets(
    'calendar selects modification dates while due filters remain separate',
    (tester) async {
      final repository = TaskFixture();
      await mount(tester, repository, calendar: true);
      expect(repository.queries.last.done, isNull);
      expect(repository.queries.last.dueOn, '');
      final day = taskDate(
        DateTime(repository.now.year, repository.now.month, 1),
      );
      await tester.ensureVisible(find.byKey(Key('task-day:$day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('task-day:$day')));
      await tester.pumpAndSettle();
      expect(repository.queries.last.modifiedOn, day);
      expect(repository.queries.last.dueOn, '');
      await tester.scrollUntilVisible(
        find.text('清除日期筛选'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除日期筛选'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.modifiedOn, '');
      expect(repository.queries.last.dueOn, '');
    },
  );
  testWidgets('calendar failure exposes unavailable counts and offers retry', (
    tester,
  ) async {
    final repository = TaskFixture()..failCounts = true;
    await mount(tester, repository, calendar: true);
    expect(
      tester
          .widget<TaskMonthGrid>(find.byType(TaskMonthGrid))
          .countsUnavailable,
      isTrue,
    );
    expect(find.text('重试计数'), findsOneWidget);
    repository.failCounts = false;
    await tester.tap(find.text('重试计数'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TaskMonthGrid>(find.byType(TaskMonthGrid))
          .countsUnavailable,
      isFalse,
    );
  });
  testWidgets(
    'delete explicitly confirms entire subtree then calls removal only once',
    (tester) async {
      final repository = TaskFixture();
      await mount(tester, repository);
      await tester.tap(find.byTooltip('待办操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到回收站'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全部子待办'), findsOneWidget);
      expect(repository.removed, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '移到回收站'));
      await tester.pumpAndSettle();
      expect(repository.removed, [1]);
      expect(repository.records.containsKey(1), isFalse);
      expect(repository.records.containsKey(2), isFalse);
    },
  );
  testWidgets(
    'English task list and calendar support keyboard and double text on 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(bool calendar) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: bookstarkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 200),
              ),
              child: child!,
            ),
            home: TasksPage(
              key: ValueKey(calendar),
              repository: TaskFixture(),
              english: true,
              calendar: calendar,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await show(false);
      await show(true);
    },
  );
  testWidgets(
    'calendar crosses the year with modification-day filtering and fresh month counts',
    (tester) async {
      final repository = TaskFixture(today: DateTime(2026, 12, 31));
      await mount(tester, repository, calendar: true);
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      expect(repository.countQueries.last, (2027, 1));
      expect(repository.queries.last.modifiedOn, '2027-01-01');
      expect(repository.queries.last.dueOn, '');
      expect(
        tester.widget<TaskMonthGrid>(find.byType(TaskMonthGrid)).month,
        DateTime(2027, 1),
      );
    },
  );
  testWidgets(
    'month grid renders November Sunday start and leap February actual day limits',
    (tester) async {
      Future<void> show(DateTime month) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskMonthGrid(
                  month: month,
                  selected: '',
                  counts: const [],
                  onDay: (_) {},
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(DateTime(2026, 11));
      final sunday = tester.getTopLeft(
        find.byKey(const Key('task-day:2026-11-01')),
      );
      final monday = tester.getTopLeft(
        find.byKey(const Key('task-day:2026-11-02')),
      );
      expect(sunday.dx, greaterThan(monday.dx));
      expect(sunday.dy, lessThan(monday.dy));
      expect(find.byKey(const Key('task-day:2026-11-30')), findsOneWidget);
      expect(find.byKey(const Key('task-day:2026-11-31')), findsNothing);
      await show(DateTime(2024, 2));
      expect(find.byKey(const Key('task-day:2024-02-29')), findsOneWidget);
      expect(find.byKey(const Key('task-day:2024-02-30')), findsNothing);
      await show(DateTime(2026, 2));
      expect(find.byKey(const Key('task-day:2026-02-29')), findsNothing);
    },
  );

  testWidgets(
    'list create and child-create routes save the visible default date and parent/topic context',
    (tester) async {
      final repository = TaskFixture(today: DateTime(2026, 11, 4));
      repository.records[1] = TaskItem(
        id: 1,
        content: '每天阅读20分钟',
        dueDate: taskDate(repository.now),
        topicId: 9,
      );
      await mount(tester, repository);
      await tester.tap(find.byTooltip('新建待办'));
      await tester.pumpAndSettle();
      expect(find.text('2026-11-11'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-content')), '新的行动');
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repository.saved.single.parentId, 0);
      expect(repository.saved.single.dueDate, '2026-11-11');
      await tester.tap(find.byTooltip('待办操作').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<TaskCardAction>, '添加子待办'),
      );
      await tester.pumpAndSettle();
      expect(find.text('新建子待办'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-content')), '新的子行动');
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repository.saved.last.parentId, 1);
      expect(repository.saved.last.topicId, 9);
      expect(repository.saved.last.dueDate, '2026-11-11');
    },
  );
}
