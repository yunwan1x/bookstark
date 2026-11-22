import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/local_task_creation_session.dart';
import 'package:bookstark_flutter/core/task_creation_session.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'task_editor_test.dart' show EditorTasks;
import 'task_creation_http_next_test.dart' show taskRow;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  test(
    'normal local ACK clears exact submitted draft and creation slot without recovery UI',
    () async {
      final parent = Directory(
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
      );
      await parent.create(recursive: true);
      final dir = await parent.createTemp('task10-normal-');
      final store = LocalStore(
        path: dir.path + '/tasks.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      final values = <String, String>{};
      final vault = TaskDraftVault(
        namespace: 'local-normal-core',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final owner = LocalTaskCreationSession(
        store: store,
        namespace: 'local-normal-core',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        draftVault: vault,
      );
      const input = TaskItem(
        content: 'Normal acknowledged task',
        dueDate: '2026-11-20',
        done: true,
        topicId: 0,
      );
      try {
        await vault.write(input);
        final repo = owner.wrap(LocalTasksRepository(store));
        final id = await repo.saveWithDraft(input, vault);
        expect(id, greaterThan(0));
        expect(owner.controller, isNull);
        expect(repo.taskCreationRecovery, isNull);
        expect(await owner.hasRetained(), isFalse);
        expect(values, isEmpty);
        final saved = await repo.read(id);
        expect(saved.content, input.content);
        expect(saved.done, true);
        final db = await store.database;
        final before = await db.query('assistant_creation_receipts');
        await repo.save(saved.copyWith(content: 'Same ID edit'));
        expect((await repo.read(id)).content, 'Same ID edit');
        expect(await db.query('tasks'), hasLength(1));
        expect(await db.query('assistant_creation_receipts'), before);
      } finally {
        await owner.retire();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'normal remote ACK verifies fresh ID and ends metadata with exactly one POST',
    () async {
      final values = <String, String>{};
      var posts = 0, gets = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((r) async {
          Map<String, Object?> reply;
          if (r.url.path.endsWith('/profile')) {
            reply = {
              'code': 0,
              'data': {'member_id': 7},
            };
          } else {
            if (r.method == 'POST') {
              posts++;
            } else {
              expect(r.method, 'GET');
              gets++;
            }
            reply = {'code': 0, 'data': taskRow()};
          }
          return http.Response(
            jsonEncode(reply),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      client.restoreSession({
        'token': 'fixture-only',
        'csrf_token': 'fixture-only',
      });
      final vault = TaskDraftVault(
        namespace: 'remote-normal-core',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final owner = TaskCreationSession(
        client: client,
        memberId: 7,
        namespace: 'remote-normal-core',
        isCurrent: () => true,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        draftVault: vault,
      );
      const input = TaskItem(
        content: 'Actual',
        dueDate: '2026-11-20',
        done: true,
        parentId: 3,
        topicId: 9,
      );
      try {
        await vault.write(input);
        final repo = owner.wrap(EditorTasks());
        expect(await repo.saveWithDraft(input, vault), 41);
        expect(posts, 1);
        expect(gets, greaterThanOrEqualTo(2));
        expect(owner.controller, isNull);
        expect(repo.taskCreationRecovery, isNull);
        expect(await owner.hasRetained(), isFalse);
        expect(values, isEmpty);
      } finally {
        await owner.retire();
        client.close();
      }
    },
  );
}
