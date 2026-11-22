// Legacy compatibility draft: not executed during Native freeze.
import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

class EditorTasks implements TasksRepository {
  final calls = <TaskItem>[];
  final records = <int, TaskItem>{};
  Completer<int>? gate;
  bool fail = false, metadataFail = false;
  @override
  Future<int> save(TaskItem task) async {
    calls.add(task);
    if (fail) throw StateError('保存失败');
    final id = await (gate?.future ?? Future.value(task.id ?? 41));
    records[id] = task.copyWith(id: id, content: task.content.trim());
    if (metadataFail) throw TaskSaveFailure(id, "任务已保存，回执需要核对");
    return id;
  }

  @override
  Future<TaskItem> read(int id) async => records[id]!;
  @override
  Future<TaskPage> list(TaskQuery query) async => TaskPage(
    items: records.values.toList(),
    total: records.length,
    page: 1,
    pageSize: 30,
  );
  @override
  Future<void> setDone(int id, bool done) async {}
  @override
  Future<void> remove(int id) async {}
  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) async => [];
}

TaskDraftVault vaultFor(
  Map<String, String> values, {
  Future<void> Function(String)? remove,
}) => TaskDraftVault(
  namespace: 'test-space',
  readValue: (key) async => values[key],
  writeValue: (key, value) async {
    values[key] = value;
  },
  deleteValue:
      remove ??
      (key) async {
        values.remove(key);
      },
);
const savedTask = TaskItem(
  id: 7,
  content: '已保存正文',
  dueDate: '2026-11-08',
  parentId: 3,
  topicId: 9,
);
Future<void> mount(
  WidgetTester tester,
  EditorTasks repository, {
  TaskItem task = savedTask,
  TaskDraftVault? vault,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TaskEditorPage(
                  repository: repository,
                  task: task,
                  vault: vault,
                ),
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'known committed ID survives metadata failure and subsequent editing cannot recreate',
    (tester) async {
      final repository = EditorTasks()..metadataFail = true;
      await mount(
        tester,
        repository,
        task: const TaskItem(content: 'Initial', dueDate: '2028-02-29'),
      );
      await tester.enterText(
        find.byKey(const Key('task-content')),
        'Actual edited task',
      );
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.calls.single.id, isNull);
      expect(repository.records.keys, [41]);
      expect(find.textContaining('回执需要核对'), findsOneWidget);
      repository.metadataFail = false;
      await tester.enterText(
        find.byKey(const Key('task-content')),
        'Further edit',
      );
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.calls.last.id, 41);
      expect(repository.records.length, 1);
      expect(repository.records[41]!.content, 'Further edit');
    },
  );

  testWidgets(
    'failed task save retains content, due date, done and actual parent/topic',
    (tester) async {
      final repository = EditorTasks()..fail = true;
      await mount(tester, repository);
      await tester.enterText(find.byKey(const Key('task-content')), ' 修改后的待办 ');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.calls.single.parentId, 3);
      expect(repository.calls.single.topicId, 9);
      expect(repository.calls.single.done, isTrue);
      expect(repository.calls.single.dueDate, '2026-11-08');
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-content')))
            .controller!
            .text,
        ' 修改后的待办 ',
      );
    },
  );
  testWidgets(
    'typing during create preserves new input and subsequent save uses created ID',
    (tester) async {
      final repository = EditorTasks()..gate = Completer<int>();
      final values = <String, String>{};
      final vault = vaultFor(values);
      await mount(
        tester,
        repository,
        task: const TaskItem(content: '', dueDate: '2026-11-08'),
        vault: vault,
      );
      await tester.enterText(find.byKey(const Key('task-content')), '较早正文');
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('task-content')), '更新中的正文');
      repository.gate!.complete(41);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-content')))
            .controller!
            .text,
        '更新中的正文',
      );
      expect((await vault.read(41, parentId: 0))!.content, '更新中的正文');
      expect(await vault.read(null, parentId: 0), isNull);
      repository.gate = null;
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.calls.map((task) => task.id), [null, 41]);
      expect(repository.records[41]!.content, '更新中的正文');
    },
  );
  testWidgets(
    'keep and restore draft includes picked date/status; discard clears without resurrection',
    (tester) async {
      final repository = EditorTasks();
      final values = <String, String>{};
      final vault = vaultFor(values);
      await mount(tester, repository, vault: vault);
      await tester.enterText(find.byKey(const Key('task-content')), '保留修改');
      await tester.tap(find.text('2026-11-08'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并离开'));
      await tester.pumpAndSettle();
      final draft = (await vault.read(7, parentId: 3))!;
      expect(draft.content, '保留修改');
      expect(draft.dueDate, '2026-11-15');
      expect(draft.done, isTrue);
      await tester.tap(find.text('打开编辑器'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-content')))
            .controller!
            .text,
        '保留修改',
      );
      expect(find.text('2026-11-15'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(await vault.read(7, parentId: 3), isNull);
      expect(repository.calls, isEmpty);
    },
  );
  testWidgets(
    'saved task draft cleanup failure explains receipt and can retry before leaving',
    (tester) async {
      final repository = EditorTasks();
      final values = <String, String>{};
      var failedDelete = true;
      final vault = vaultFor(
        values,
        remove: (key) async {
          if (failedDelete) throw StateError('草稿清理失败');
          values.remove(key);
        },
      );
      await mount(
        tester,
        repository,
        task: const TaskItem(content: '', dueDate: '2026-11-08'),
        vault: vault,
      );
      await tester.enterText(find.byKey(const Key('task-content')), ' 已创建的任务 ');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.calls.length, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-content')))
            .controller!
            .text,
        '已创建的任务',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('任务#41'), findsOneWidget);
      await tester.tap(find.text('保留编辑页'));
      await tester.pumpAndSettle();
      failedDelete = false;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('打开编辑器'), findsOneWidget);
      expect(await vault.read(null, parentId: 0), isNull);
      expect(repository.calls.length, 1);
    },
  );
  testWidgets(
    'shared bold insertion and native preview preserve emoji without an editor WebView',
    (tester) async {
      final repository = EditorTasks();
      await mount(tester, repository);
      final field = find.byKey(const Key('task-content'));
      await tester.enterText(field, '阅读📖');
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.ensureVisible(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加粗'));
      await tester.pumpAndSettle();
      expect(controller.text, '**阅读📖**');
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byKey(const Key('task-content')), findsNothing);
    },
  );
  testWidgets(
    'English task editor with double text and keyboard remains scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          home: TaskEditorPage(
            repository: EditorTasks(),
            task: savedTask,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unreadable draft requires explicit successful clearing before editing',
    (tester) async {
      final repository = EditorTasks();
      var failDelete = true;
      final vault = TaskDraftVault(
        namespace: 'broken',
        readValue: (_) async => throw StateError('无法读取'),
        writeValue: (_, _) async {},
        deleteValue: (_) async {
          if (failDelete) throw StateError('无法清理');
        },
      );
      await mount(tester, repository, vault: vault);
      expect(
        tester.widget<TextField>(find.byKey(const Key('task-content'))).enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(TextButton, '清除草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清除草稿'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('task-content'))).enabled,
        isFalse,
      );
      expect(repository.calls, isEmpty);
      failDelete = false;
      await tester.tap(find.widgetWithText(TextButton, '清除草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清除草稿'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('task-content'))).enabled,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('task-content')))
            .controller!
            .text,
        savedTask.content,
      );
      expect(repository.calls, isEmpty);
    },
  );
}
