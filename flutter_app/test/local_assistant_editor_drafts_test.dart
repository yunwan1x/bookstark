import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';

void main() {
  late Map<String, String> values;
  late LocalAssistantEditorDrafts drafts;
  setUp(() {
    values = {};
    final namespace = LocalAssistantEditorDrafts.editorNamespace(
      base: 'local',
      binding: 'b' * 32,
      draft: 'd' * 32,
      kind: LocalAssistantDraftKind.note,
    );
    drafts = LocalAssistantEditorDrafts(
      notes: DraftVault(
        namespace: namespace,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      ),
      tasks: TaskDraftVault(
        namespace: namespace,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      ),
    );
  });
  test(
    'actual edited note snapshot preserves BOM labels and Unicode',
    () async {
      const snapshot = Note(
        title: '  实际编辑😀 ',
        content: '\ufeff# 阅读\r\n正文',
        labels: ['原标签', ' spaced '],
      );
      final expected = LocalAssistantCreationInput.note(snapshot);
      expect(
        (await drafts.persistNote(snapshot, expected)).digest,
        expected.digest,
      );
      final actual = (await drafts.notes.read(null))!;
      expect(actual.content, snapshot.content);
      expect(actual.title, snapshot.title);
      expect(actual.labels, snapshot.labels);
    },
  );
  test(
    'task snapshot keeps original whitespace while canonical SQL input is verified',
    () async {
      const snapshot = TaskItem(
        content: '  实际任务😀  ',
        dueDate: '2028-02-29',
        done: true,
      );
      final expected = LocalAssistantCreationInput.task(snapshot);
      expect(
        (await drafts.persistTask(snapshot, expected)).digest,
        expected.digest,
      );
      expect(
        (await drafts.tasks.read(null, parentId: 0))!.content,
        snapshot.content,
      );
      expect(expected.values['content'], '实际任务😀');
    },
  );
  test(
    'mismatched editor input writes nothing and scopes cannot cross generations',
    () async {
      const actual = Note(title: 'Actual', content: 'Keep');
      final other = LocalAssistantCreationInput.note(
        const Note(title: 'Other', content: 'Changed'),
      );
      await expectLater(drafts.persistNote(actual, other), throwsStateError);
      expect(values, isEmpty);
      String namespace(String base) =>
          LocalAssistantEditorDrafts.editorNamespace(
            base: base,
            binding: 'b' * 32,
            draft: 'd' * 32,
            kind: LocalAssistantDraftKind.note,
          );
      expect(
        namespace('local'),
        isNot(namespace('local-generation:${'a' * 32}')),
      );
      expect(() => namespace('https://model.test'), throwsFormatException);
    },
  );
}
