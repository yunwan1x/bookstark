import 'dart:convert';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'task drafts isolate new roots/parents and preserve date/status while rejecting changed parent',
    () async {
      final values = <String, String>{};
      final vault = TaskDraftVault(
        namespace: 'space/member',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      await vault.write(const TaskItem(content: '根草稿', dueDate: '2026-11-08'));
      await vault.write(
        const TaskItem(
          content: '子草稿',
          dueDate: '2026-11-15',
          done: true,
          parentId: 3,
        ),
      );
      await vault.write(
        const TaskItem(
          id: 7,
          content: '已有任务修改',
          dueDate: '2026-11-09',
          parentId: 3,
          topicId: 9,
        ),
      );
      expect((await vault.read(null, parentId: 0))!.content, '根草稿');
      final child = (await vault.read(null, parentId: 3))!;
      expect(child.content, '子草稿');
      expect(child.dueDate, '2026-11-15');
      expect(child.done, isTrue);
      expect((await vault.read(7, parentId: 3))!.topicId, 9);
      await expectLater(vault.read(7, parentId: 4), throwsFormatException);
      expect((await vault.read(7, parentId: 3))!.content, '已有任务修改');
      await vault.remove(null, parentId: 3);
      expect(await vault.read(null, parentId: 3), isNull);
      expect((await vault.read(null, parentId: 0))!.content, '根草稿');
      expect(
        values.values.every(
          (value) => (jsonDecode(value) as Map)['version'] == 1,
        ),
        isTrue,
      );
    },
  );
}
