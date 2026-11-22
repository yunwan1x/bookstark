import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_guarded_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'task_editor_test.dart' show EditorTasks;

void main() {
  testWidgets(
    'ambiguous creation becomes actual readonly full editor; no fallback INSERT',
    (tester) async {
      final existing = EditorTasks();
      var attempts = 0, reviews = 0;
      final repository = TaskCreationGuardedRepository(
        existing: existing,
        isCurrent: () => true,
        begin: (_) async {
          attempts++;
          throw const TaskCreationNeedsReview();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TaskEditorPage(
            repository: repository,
            task: const TaskItem(
              content: 'Actual full body',
              dueDate: '2026-11-20',
              parentId: 7,
              topicId: 9,
              done: true,
            ),
            onCreationRecovery: () async {
              reviews++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(TextButton, '保存'), findsNothing);
      expect(find.text('Actual full body'), findsOneWidget);
      expect(find.textContaining('2026-11-20'), findsOneWidget);
      expect(find.textContaining('父待办 ID：7'), findsOneWidget);
      expect(find.textContaining('专题 ID：9'), findsOneWidget);
      expect(existing.calls, isEmpty);
      expect(attempts, 1);
      final review = find.widgetWithText(FilledButton, '只读核对恢复记录');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(reviews, 1);
    },
  );
}
