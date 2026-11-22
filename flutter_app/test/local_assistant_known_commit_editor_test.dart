import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';

class _Notes extends Fake implements NotesRepository {
  _Notes(this.vault);
  final DraftVault vault;
  final snapshots = <Note>[];
  @override
  Future<int> save(Note note) async {
    snapshots.add(note);
    // The creator has persisted the actual full snapshot before SQL and then
    // received a real ID, but encrypted acknowledgement subsequently failed.
    await vault.write(note);
    throw const NoteSaveFailure(19, 'Saved; acknowledgement incomplete');
  }
}

class _Tasks extends Fake implements TasksRepository {
  _Tasks(this.vault);
  final TaskDraftVault vault;
  final snapshots = <TaskItem>[];
  @override
  Future<int> save(TaskItem task) async {
    snapshots.add(task);
    await vault.write(task);
    throw const TaskSaveFailure(23, 'Saved; acknowledgement incomplete');
  }
}

void main() {
  testWidgets(
    'real note page moves known failure edited snapshot to positive ID vault',
    (tester) async {
      final storage = <String, String>{};
      final vault = DraftVault(
        namespace: 'assistant-note-fixture',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      final repository = _Notes(vault);
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            repository: repository,
            note: const Note(title: 'Proposal', content: 'Initial'),
            drafts: vault,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '笔记标题',
        ),
        'Edited title',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == 'Markdown…',
        ),
        '\ufeff# Actual edited body',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repository.snapshots.single.id, isNull);
      expect(await vault.read(null), isNull);
      final recovered = await vault.read(19);
      expect(recovered!.id, 19);
      expect(recovered.title, 'Edited title');
      expect(recovered.content, '\ufeff# Actual edited body');
      // Subsequent Save must retain the known SQL identity, never become new.
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repository.snapshots.last.id, 19);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real task page can retain original null draft after known failure',
    (tester) async {
      final storage = <String, String>{};
      final vault = TaskDraftVault(
        namespace: 'assistant-task-fixture',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      final repository = _Tasks(vault);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskEditorPage(
            repository: repository,
            task: const TaskItem(content: 'Proposal', dueDate: '2026-11-11'),
            vault: vault,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-content')),
        'Actual task edit',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repository.snapshots.single.id, isNull);
      final recovered = await vault.read(null, parentId: 0);
      expect(recovered!.content, 'Actual task edit');
      expect(await vault.read(23, parentId: 0), isNull);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repository.snapshots.last.id, 23);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
