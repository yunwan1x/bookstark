import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CleanupStore {
  final values = <String, String>{};
  bool fail = true;
  int deletes = 0;
  late final vault = TaskDraftVault(
    namespace: 'task10-cleanup-fixture',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      deletes++;
      if (fail) throw StateError('Owned metadata deletion unavailable');
      values.remove(key);
    },
  );
}

Future<void> _ready(WidgetTester tester) async {
  final save = find.widgetWithText(TextButton, '保存');
  for (var i = 0; i < 800; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    if (save.evaluate().length == 1 &&
        tester.widget<TextButton>(save).onPressed != null)
      return;
  }
  fail('Actual task editor did not settle');
}

Future<void> _mount(
  WidgetTester tester,
  TasksRepository repository,
  TaskItem task,
  _CleanupStore storage,
) async {
  await storage.vault.write(task);
  await tester.pumpWidget(
    MaterialApp(
      home: TaskEditorPage(
        repository: repository,
        task: task,
        vault: storage.vault,
      ),
    ),
  );
  await _ready(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, '保存'));
  await _ready(tester);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux)
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
  });
  for (final dirtyRetry in [false, true]) {
    testWidgets(
      'real HTTP ACK cleanup retry sends no mutation until metadata resolves, dirty=$dirtyRetry',
      (tester) async {
        final writes = <http.Request>[];
        Map<String, Object?>? stored;
        final client = BookstarkClient(
          'https://tasks.fixture/base',
          transport: MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.path == '/base/api/csrf-token') {
              return http.Response(
                '{"code":0,"data":{}}',
                200,
                headers: {
                  'content-type': 'application/json',
                  'set-cookie': 'csrf_token=fixture-only; Path=/',
                },
              );
            }
            if (request.method == 'GET' &&
                request.url.path == '/base/api/tasks/41') {
              return http.Response(
                jsonEncode({'code': 0, 'data': stored}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(
              request.url.path,
              anyOf('/base/api/tasks', '/base/api/tasks/41'),
            );
            expect(request.method, anyOf('POST', 'PUT'));
            writes.add(request);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            stored = {
              'task_id': 41,
              ...body,
              'child_total': 0,
              'child_done': 0,
              'modify_time': '2026-11-11T12:00:00Z',
              'complete_time': '2026-11-11T12:00:00Z',
            };
            return http.Response(
              jsonEncode({'code': 0, 'data': stored}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        client.restoreSession({'token': 'fixture-only'});
        final repository = RemoteTasksRepository(client, isCurrent: () => true);
        final storage = _CleanupStore();
        const initial = TaskItem(
          content: 'Exact captured content',
          dueDate: '2028-02-29',
          done: true,
          parentId: 7,
          topicId: 9,
        );
        try {
          await _mount(tester, repository, initial, storage);
          await _save(tester);
          expect(writes.map((request) => request.method), ['POST']);
          expect(
            storage.values.containsKey(storage.vault.metadataKey('new:7')),
            isTrue,
          );
          if (dirtyRetry) {
            await tester.enterText(
              find.byKey(const Key('task-content')),
              'Explicit revised content',
            );
            await tester.pump();
          }
          await _save(tester);
          expect(writes, hasLength(1));
          storage.fail = false;
          await _save(tester);
          expect(
            writes.map((request) => request.method),
            dirtyRetry ? ['POST', 'PUT'] : ['POST'],
          );
          if (dirtyRetry) expect(writes.last.url.path, '/base/api/tasks/41');
          final actual = await tester.runAsync(() => repository.read(41));
          expect(
            actual!.content,
            dirtyRetry ? 'Explicit revised content' : initial.content,
          );
          expect(actual.dueDate, initial.dueDate);
          expect(actual.done, initial.done);
          expect(actual.parentId, 7);
          expect(actual.topicId, 9);
          expect(
            storage.values.containsKey(storage.vault.metadataKey('new:7')),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          client.close();
        }
      },
    );
  }
  testWidgets(
    'real SQLite acknowledged creation retries storage only and preserves full rows/sequence/timestamps',
    (tester) async {
      final parent = Directory(
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
      );
      await parent.create(recursive: true);
      final root = await parent.createTemp('task10-cleanup-');
      final store = LocalStore(
        path: root.path + '/tasks.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      final repository = LocalTasksRepository(store);
      final storage = _CleanupStore();
      try {
        await tester.runAsync(() async {
          final db = await store.database;
          await db.execute(
            'CREATE TEMP TABLE task10_audit(kind TEXT,id INTEGER)',
          );
          await db.execute(
            "CREATE TEMP TRIGGER task10_insert AFTER INSERT ON tasks BEGIN INSERT INTO task10_audit VALUES('insert',new.task_id); END",
          );
          await db.execute(
            "CREATE TEMP TRIGGER task10_update AFTER UPDATE ON tasks BEGIN INSERT INTO task10_audit VALUES('update',new.task_id); END",
          );
        });
        const initial = TaskItem(
          content: 'Local exact completed task',
          dueDate: '2028-02-29',
          done: true,
        );
        await _mount(tester, repository, initial, storage);
        await _save(tester);
        final before = await tester.runAsync(() async {
          final db = await store.database;
          return (
            await db.query('tasks'),
            await db.query('sqlite_sequence'),
            await db.rawQuery('SELECT * FROM task10_audit'),
          );
        });
        expect(before!.$1, hasLength(1));
        expect(before.$3.map((row) => row['kind']), ['insert']);
        storage.fail = false;
        await _save(tester);
        final after = await tester.runAsync(() async {
          final db = await store.database;
          return (
            await db.query('tasks'),
            await db.query('sqlite_sequence'),
            await db.rawQuery('SELECT * FROM task10_audit'),
          );
        });
        expect(
          after,
          before,
          reason:
              'Cleanup retry must execute zero extra INSERT/UPDATE and preserve complete/modify time',
        );
        expect(
          storage.values.containsKey(storage.vault.metadataKey('new:0')),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await store.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
