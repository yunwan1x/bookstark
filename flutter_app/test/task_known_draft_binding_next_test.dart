import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/task_creation_session.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'task_editor_test.dart' show EditorTasks;
import 'task_creation_http_next_test.dart' show taskRow;

void main() {
  TaskDraftVault vault(
    Map<String, String> values, {
    Future<void> Function(String)? remove,
    Future<String?> Function(String)? read,
    void Function()? onWrite,
  }) => TaskDraftVault(
    namespace: 'bound-task',
    readValue: read ?? (k) async => values[k],
    writeValue: (k, v) async {
      onWrite?.call();
      values[k] = v;
    },
    deleteValue:
        remove ??
        (k) async {
          values.remove(k);
        },
  );
  const draft = TaskItem(
    content: 'Unsubmitted full differences',
    dueDate: '2026-11-21',
    done: false,
    parentId: 3,
    topicId: 8,
  );
  test(
    'failed old null deletion retries storage only and retains full differences at same ID',
    () async {
      final values = <String, String>{};
      var fail = true, writes = 0;
      final v = vault(
        values,
        remove: (k) async {
          if (fail) throw StateError('delete failed');
          values.remove(k);
        },
        onWrite: () => writes++,
      );
      await v.write(draft);
      writes = 0;
      await expectLater(
        v.bindCreatedDraftToId(
          41,
          parentId: 3,
          flush: () async {},
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect((await v.read(41, parentId: 3))!.content, draft.content);
      expect(await v.read(null, parentId: 3), isNotNull);
      fail = false;
      await v.bindCreatedDraftToId(
        41,
        parentId: 3,
        flush: () async {},
        isCurrent: () => true,
      );
      expect(writes, 1);
      expect(await v.read(null, parentId: 3), isNull);
      final bound = (await v.read(41, parentId: 3))!;
      expect(bound.id, 41);
      expect(bound.content, draft.content);
      expect(bound.done, false);
      expect(bound.dueDate, '2026-11-21');
      expect(bound.topicId, 8);
    },
  );
  test(
    'different destination draft refuses overwrite and retains original new draft',
    () async {
      final values = <String, String>{};
      final v = vault(values);
      await v.write(draft);
      await v.write(draft.copyWith(id: 41, content: 'Other retained editor'));
      final before = Map.of(values);
      await expectLater(
        v.bindCreatedDraftToId(
          41,
          parentId: 3,
          flush: () async {},
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(values, before);
    },
  );
  test(
    'retirement while raw source read is held writes and deletes nothing',
    () async {
      final values = <String, String>{};
      final seed = vault(values);
      await seed.write(draft);
      final before = Map.of(values);
      var current = true;
      final entered = Completer<void>(), release = Completer<void>();
      final v = vault(
        values,
        read: (k) async {
          entered.complete();
          await release.future;
          return values[k];
        },
      );
      final work = v.bindCreatedDraftToId(
        41,
        parentId: 3,
        flush: () async {},
        isCurrent: () => current,
      );
      final rejected = expectLater(work, throwsStateError);
      await entered.future;
      current = false;
      release.complete();
      await rejected;
      expect(values, before);
    },
  );
  test(
    'actual POST known record cannot end leaving a null draft that could create again',
    () async {
      final values = <String, String>{};
      var posts = 0, updates = 0;
      http.Response reply(Object x) => http.Response(
        jsonEncode(x),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile'))
            return reply({
              'code': 0,
              'data': {'member_id': 7},
            });
          if (r.method == 'POST') posts++;
          if (r.method == 'PUT') updates++;
          return reply({'code': 0, 'data': taskRow()});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final v = vault(values);
      await v.write(draft);
      final owner = TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'bound-task',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, x) async {
          values[k] = x;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        draftVault: v,
      );
      try {
        final repo = owner.wrap(EditorTasks());
        expect(
          await repo.save(
            const TaskItem(
              content: 'Actual',
              dueDate: '2026-11-20',
              done: true,
              parentId: 3,
              topicId: 9,
            ),
          ),
          41,
        );
        final c = owner.controller!;
        await c.end(c.record!);
        await owner.clearEndedSlot();
        expect(posts, 1);
        expect(updates, 0);
        expect(await v.read(null, parentId: 3), isNull);
        final bound = (await v.read(41, parentId: 3))!;
        expect(bound.content, draft.content);
        expect(bound.dueDate, draft.dueDate);
        expect(bound.done, draft.done);
        expect(bound.topicId, draft.topicId);
        expect(
          values.length,
          1,
        ); // Only bound same-ID editor draft, no creation markers.
      } finally {
        await owner.retire();
        client.close();
      }
    },
  );
}
