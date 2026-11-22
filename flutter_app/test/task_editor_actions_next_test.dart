// Draft only: not run/formatted during shared Native freeze.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/task_action_drafts.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'task_editor_legacy_compat_next_test.dart' show EditorTasks, vaultFor;

const existing = TaskItem(
  id: 42,
  content: 'Original',
  dueDate: '2026-12-04',
  parentId: 11,
  topicId: 9,
  done: true,
  childTotal: 3,
  childDone: 2,
);
TaskEditorActionBindings binding({
  required bool Function() current,
  required Future<TaskTextSuggestion> Function(TaskActionSnapshot) generate,
}) => TaskEditorActionBindings(
  scope: 'owned/server/member7',
  memberId: 7,
  isCurrent: current,
  verifyExistingOwner: (id) async => id == 42,
  generateSuggestion: generate,
);
Future<void> mountEditor(
  WidgetTester tester,
  EditorTasks repo,
  TaskEditorActionBindings? actions, {
  TaskItem task = existing,
  Map<String, String>? values,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TaskEditorPage(
        repository: repo,
        task: task,
        english: true,
        actions: actions,
        vault: values == null ? null : vaultFor(values),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> suggest(WidgetTester tester) async {
  await tester.ensureVisible(find.text('AI suggestions'));
  await tester.tap(find.text('AI suggestions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'actual editor Apply writes draft only; explicit Save keeps same ID and context',
    (tester) async {
      final repo = EditorTasks();
      await mountEditor(
        tester,
        repo,
        binding(
          current: () => true,
          generate: (origin) async => TaskTextSuggestion(
            origin: origin,
            content: 'Rewritten',
            complete: true,
          ),
        ),
      );
      await suggest(tester);
      expect(repo.calls, isEmpty);
      await tester.ensureVisible(find.text('Put into editor'));
      await tester.tap(find.text('Put into editor'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.text('Rewritten'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = repo.calls.single;
      expect(saved.id, 42);
      expect(saved.content, 'Rewritten');
      expect(saved.parentId, 11);
      expect(saved.topicId, 9);
      expect(saved.dueDate, '2026-12-04');
      expect(saved.done, true);
    },
  );
  testWidgets(
    'model return after actual draft change never opens stale preview',
    (tester) async {
      final repo = EditorTasks(), pending = Completer<TaskTextSuggestion>();
      TaskActionSnapshot? requested;
      await mountEditor(
        tester,
        repo,
        binding(
          current: () => true,
          generate: (origin) {
            requested = origin;
            return pending.future;
          },
        ),
      );
      await tester.ensureVisible(find.text('AI suggestions'));
      await tester.tap(find.text('AI suggestions'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).first,
        'Typed while waiting',
      );
      pending.complete(
        TaskTextSuggestion(
          origin: requested!,
          content: 'Stale AI text',
          complete: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Put into editor'), findsNothing);
      expect(find.text('Typed while waiting'), findsOneWidget);
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets(
    'space retirement rejects old AI and explicit Save from that route',
    (tester) async {
      final repo = EditorTasks(), pending = Completer<TaskTextSuggestion>();
      var current = true;
      TaskActionSnapshot? requested;
      await mountEditor(
        tester,
        repo,
        binding(
          current: () => current,
          generate: (origin) {
            requested = origin;
            return pending.future;
          },
        ),
      );
      await tester.ensureVisible(find.text('AI suggestions'));
      await tester.tap(find.text('AI suggestions'));
      await tester.pump();
      current = false;
      pending.complete(
        TaskTextSuggestion(
          origin: requested!,
          content: 'Old space text',
          complete: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Put into editor'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets('legacy no actions call has no new controls or owner callback', (
    tester,
  ) async {
    final repo = EditorTasks();
    await mountEditor(tester, repo, null);
    expect(find.text('AI suggestions'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.calls.single.id, 42);
    expect(repo.calls.single.topicId, 9);
  });
  testWidgets(
    'topic-only retained vault draft restores and saves explicit clear zero',
    (tester) async {
      final repo = EditorTasks(), values = <String, String>{};
      final vault = vaultFor(values);
      await vault.write(
        const TaskItem(
          id: 42,
          content: 'Original',
          dueDate: '2026-12-04',
          parentId: 11,
          topicId: 0,
          done: true,
        ),
      );
      await mountEditor(tester, repo, null, values: values);
      expect(find.text('Unsaved draft found'), findsOneWidget);
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.calls.single.topicId, 0);
      expect(repo.calls.single.parentId, 11);
      expect(repo.calls.single.done, true);
      expect(repo.calls.single.dueDate, '2026-12-04');
    },
  );
  testWidgets(
    'new null-ID task hides existing-task AI and cannot call suggestion backend',
    (tester) async {
      final repo = EditorTasks();
      var calls = 0;
      await mountEditor(
        tester,
        repo,
        binding(
          current: () => true,
          generate: (origin) async {
            calls++;
            return TaskTextSuggestion(
              origin: origin,
              content: 'Wrong create',
              complete: true,
            );
          },
        ),
        task: const TaskItem(content: 'New', dueDate: '2026-12-04'),
      );
      expect(find.text('AI suggestions'), findsNothing);
      expect(calls, 0);
      expect(repo.calls, isEmpty);
    },
  );
}
