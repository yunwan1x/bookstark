import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/topics/topic_detail_page.dart';
import 'package:bookstark_flutter/features/topics/topic_comments_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/topics.dart';
import '../tool/fixtures/topic_picker.dart';

Future<void> mount(
  WidgetTester tester,
  TopicsFixture repo, {
  Future<void> Function(TopicResource)? open,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: TopicDetailPage(
        repository: repo,
        topicId: 1,
        tasks: repo.taskRepository,
        picker: TopicPickerFixture(),
        onOpenResource: open ?? (_) async {},
        clock: () => DateTime(2026, 11, 4),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'resource comments bind association ID while opening uses source ID',
    (tester) async {
      final repo = TopicsFixture();
      TopicResource? opened;
      await mount(
        tester,
        repo,
        open: (item) async {
          opened = item;
        },
      );
      await tester.tap(find.text('资料3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读的意义'));
      await tester.pumpAndSettle();
      expect(opened!.id, 51);
      expect(opened!.targetId, 1);
      final button = find.widgetWithText(TextButton, '评论1').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final page = tester.widget<TopicCommentsPage>(
        find.byType(TopicCommentsPage),
      );
      expect(page.initialTarget!.type, TopicCommentTarget.resource);
      expect(page.initialTarget!.id, 51);
      expect(find.textContaining('这篇笔记和当前问题很相关'), findsOneWidget);
    },
  );
  testWidgets('editing existing AI summary preserves type and ordering', (
    tester,
  ) async {
    final repo = TopicsFixture();
    await mount(tester, repo);
    await tester.scrollUntilVisible(
      find.text('AI小结'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final menu = find.descendant(
      of: find
          .ancestor(of: find.text('AI小结'), matching: find.byType(Card))
          .first,
      matching: find.byTooltip('小结操作'),
    );
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPage), findsOneWidget);
    final field = find.descendant(
      of: find.byType(NoteEditorPage),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '# 修改后的行动\n\n完成原生改写');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.summaries[32]!.type, 'ai');
    expect(repo.summaries[32]!.order, 1);
    expect(repo.summaries[32]!.content, contains('修改后的行动'));
    expect(repo.summaries.length, 3);
  });
  testWidgets(
    'new task editor receives fixed topic and comments refresh real counts',
    (tester) async {
      final repo = TopicsFixture();
      await mount(tester, repo);
      await tester.tap(find.text('任务1'));
      await tester.pumpAndSettle();
      expect(find.text('1条匹配任务'), findsOneWidget);
      await tester.tap(find.byTooltip('添加主题任务'));
      await tester.pumpAndSettle();
      final editor = tester.widget<TaskEditorPage>(find.byType(TaskEditorPage));
      expect(editor.task.topicId, 1);
      expect(editor.task.parentId, 0);
      expect(editor.task.dueDate, '2026-11-11');
      expect(repo.taskRepository.records.length, 4);
    },
  );
}
