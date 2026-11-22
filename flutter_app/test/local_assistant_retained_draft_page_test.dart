import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_assistant_retained_draft.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/assistant/local_assistant_retained_draft_page.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

void main() {
  LocalAssistantRetainedDraftSnapshot snapshot({
    String content = '## Weekly reading\n\n- Essays\n- Notes',
  }) => LocalAssistantRetainedDraftSnapshot(
    fingerprint: 'a' * 64,
    note: Note(
      title: 'Weekly reading',
      content: content,
      labels: const ['Reading', 'Plan'],
    ),
    task: null,
    raw: 'full actual original',
  );
  Future<void> mount(
    WidgetTester tester, {
    required LocalAssistantRetainedDraftSnapshot initial,
    required Future<void> Function(LocalAssistantRetainedDraftSnapshot) clear,
    bool english = false,
    bool large = false,
    Future<LocalAssistantRetainedDraftSnapshot?> Function()? inspect,
  }) async {
    tester.view.physicalSize = large
        ? const Size(320, 640)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 2 : 1),
            viewInsets: EdgeInsets.only(bottom: large ? 180 : 0),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => LocalAssistantRetainedDraftPage(
                    initialSnapshot: initial,
                    inspect: inspect ?? () async => initial,
                    clear: clear,
                    english: english,
                  ),
                ),
              ),
              child: const Text('Open archive'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open archive'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'prototype readonly Markdown labels and Return retain the complete draft',
    (tester) async {
      var cleared = 0;
      await mount(
        tester,
        initial: snapshot(),
        clear: (_) async {
          cleared++;
        },
      );
      expect(find.text('这次保存已放弃'), findsOneWidget);
      expect(find.text('Weekly reading'), findsNWidgets(2));
      expect(find.text('Reading'), findsOneWidget);
      expect(find.byType(BookstarkMarkdown), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.ensureVisible(find.text('返回并保留'));
      await tester.tap(find.text('返回并保留'));
      await tester.pumpAndSettle();
      expect(find.text('Open archive'), findsOneWidget);
      expect(cleared, 0);
    },
  );
  testWidgets(
    'clear requires explicit red dialog confirmation and binds reviewed snapshot',
    (tester) async {
      final initial = snapshot();
      var cleared = 0;
      await mount(
        tester,
        initial: initial,
        clear: (reviewed) async {
          expect(identical(reviewed, initial), true);
          cleared++;
        },
      );
      await tester.ensureVisible(find.text('清除此草稿'));
      await tester.tap(find.text('清除此草稿'));
      await tester.pumpAndSettle();
      expect(cleared, 0);
      await tester.tap(find.text('返回并保留').last);
      await tester.pumpAndSettle();
      expect(cleared, 0);
      await tester.tap(find.text('清除此草稿'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, '确认清除此草稿');
      expect(
        tester
            .widget<FilledButton>(confirm)
            .style!
            .backgroundColor!
            .resolve({}),
        Colors.red.shade700,
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(cleared, 1);
      expect(find.text('Open archive'), findsOneWidget);
    },
  );
  testWidgets('read failure shows retained error rather than empty draft', (
    tester,
  ) async {
    await mount(
      tester,
      initial: snapshot(),
      clear: (_) async {},
      inspect: () async => throw StateError('private diagnostic'),
    );
    await tester.ensureVisible(find.text('重新核对'));
    await tester.tap(find.text('重新核对'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时无法完整读取草稿'), findsOneWidget);
    expect(find.textContaining('未找到实际编辑草稿'), findsNothing);
    expect(find.textContaining('private diagnostic'), findsNothing);
    final clear = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '清除此草稿'),
    );
    expect(clear.onPressed, isNull);
  });
  testWidgets(
    'English320dp200 keyboard can scroll to confirmation and honest cleanup failure',
    (tester) async {
      await mount(
        tester,
        initial: snapshot(),
        english: true,
        large: true,
        clear: (_) async => throw StateError('private failure'),
      );
      await tester.scrollUntilVisible(
        find.text('Clear this draft'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Clear this draft'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Clear this draft'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Clear this draft'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Cleanup was not confirmed'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Cleanup was not confirmed'), findsOneWidget);
      expect(find.textContaining('private failure'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'bounded preview and complete readonly sections preserve surrogate boundary and final text',
    (tester) async {
      final body = '${('a ' * 12000).substring(0, 23999)}😀FINAL_TAIL';
      final initial = snapshot(content: body);
      await mount(tester, initial: initial, clear: (_) async {});
      final preview = tester.widget<BookstarkMarkdown>(
        find.byType(BookstarkMarkdown),
      );
      expect(preview.data.length, 23999);
      final mainScrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      mainScrollable.position.jumpTo(mainScrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看完整草稿（分段只读）'));
      await tester.pumpAndSettle();
      final fullScrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      fullScrollable.position.jumpTo(fullScrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final pieces = tester.widgetList<BookstarkMarkdown>(
        find.byType(BookstarkMarkdown),
      );
      final last = pieces.last.data;
      expect(last, '😀FINAL_TAIL');
      expect(utf8.decode(utf8.encode(last)), last);
      expect(initial.content, body);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'retained task exposes body due date and completion separately to accessibility',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final initial = LocalAssistantRetainedDraftSnapshot(
          fingerprint: 'b' * 64,
          note: null,
          task: const TaskItem(
            content: 'Native assistant task_ANDROID_EDIT',
            dueDate: '2026-11-20',
          ),
          raw: 'complete actual task draft',
        );
        await mount(tester, initial: initial, clear: (_) async {});
        final bodyNode = tester.getSemantics(find.byType(SelectableText));
        expect(
          bodyNode.getSemanticsData().value,
          'Native assistant task_ANDROID_EDIT',
        );
        expect(find.bySemanticsLabel('截止日期: 2026-11-20'), findsOneWidget);
        expect(find.bySemanticsLabel('未完成'), findsOneWidget);
        for (final label in ['截止日期: 2026-11-20', '未完成']) {
          final node = tester.getSemantics(find.text(label));
          expect(node.isMergedIntoParent, isFalse);
          expect(node.getSemanticsData().label, label);
        }
        expect(find.bySemanticsLabel('原编辑草稿'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
