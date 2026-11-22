import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_controller.dart';
import 'package:bookstark_flutter/core/task_draft_save_context.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/tasks_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'task_editor_test.dart' show EditorTasks;

class RetainedTasks extends EditorTasks implements TaskDraftSaveRepository {
  bool fail = false;
  @override
  TaskCreationRecoveryController? get taskCreationRecovery => null;
  @override
  Future<bool> hasRetainedTaskCreation() async {
    if (fail) throw StateError('metadata unavailable');
    return true;
  }

  @override
  Future<int> saveWithDraft(TaskItem input, TaskDraftVault? vault) =>
      save(input);
}

void main() {
  testWidgets(
    'cold retained creation opens actual readonly recovery before editable form',
    (tester) async {
      final repo = RetainedTasks();
      var recovered = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TasksPage(
            repository: repo,
            recoverCreation: () async {
              recovered++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建待办'));
      await tester.pumpAndSettle();
      expect(recovered, 1);
      expect(find.byType(TaskEditorPage), findsNothing);
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets('unknown metadata read cannot authorize a new editor or save', (
    tester,
  ) async {
    final repo = RetainedTasks()..fail = true;
    var recovered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksPage(
          repository: repo,
          recoverCreation: () async {
            recovered++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建待办'));
    await tester.pumpAndSettle();
    expect(recovered, 0);
    expect(find.byType(TaskEditorPage), findsNothing);
    expect(repo.calls, isEmpty);
  });
}
