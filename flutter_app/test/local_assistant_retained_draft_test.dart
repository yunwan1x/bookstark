import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_recovery_resolver.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/assistant/open_local_assistant_recovery.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory directory;
  late LocalStore store;
  late LocalAssistantRecovery recovery;
  final values = <String, String>{};
  bool current = true, loseDelete = false, failRead = false;
  Future<void> Function() drain = () async {};
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    );
    await base.create(recursive: true);
    directory = await base.createTemp('retained-assistant-');
    final paths = LocalDataPaths.legacy(
      databasePath: '${directory.path}/content.db',
      privateSupport: directory,
    );
    store = LocalStore(
      path: paths.databasePath,
      dataPaths: paths,
      factory: databaseFactoryFfiNoIsolate,
    );
    current = true;
    loseDelete = false;
    failRead = false;
    values.clear();
    drain = () async {};
    recovery = LocalAssistantRecovery(
      store: store,
      isCurrent: () => current,
      drainOriginatingSave: (_) => drain(),
      readValue: (key) async {
        if (failRead) throw StateError('read unavailable');
        return values[key];
      },
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
        if (loseDelete) {
          loseDelete = false;
          throw StateError('applied delete, lost flush');
        }
      },
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<LocalRecoveryDestination> cancelled({
    bool task = false,
    int? resourceId,
  }) async {
    final kind = task
        ? LocalAssistantDraftKind.task
        : LocalAssistantDraftKind.note;
    final identity = LocalAssistantWriteMarker(
      namespace: 'local',
      bindingId: 'a' * 32,
      draftId: 'b' * 32,
      kind: kind,
    );
    final ledger = recovery.ledger(identity);
    final record = await ledger.propose(
      task
          ? LocalAssistantDraftPayload.task(content: 'Proposal')
          : LocalAssistantDraftPayload.note(
              title: 'Proposal',
              content: 'Original',
            ),
    );
    await ledger.cancel(record.id);
    final marker = LocalAssistantWriteMarker(
      namespace: 'local',
      bindingId: 'a' * 32,
      draftId: record.id,
      kind: kind,
    );
    return LocalRecoveryDestination(
      kind: 'ai-editor',
      namespace: LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: marker.bindingId,
        draft: marker.draftId,
        kind: kind,
      ),
      title: '',
      assistant: marker,
      assistantResourceId: resourceId,
    );
  }

  test(
    'full BOM note archive clears only current vault; ledger SQL and other drafts exact',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      final content = '\uFEFF## Original\r\n${'Long 😀 body\r\n' * 3000}';
      await archive.notes.write(
        Note(
          title: 'Edited title',
          content: content,
          labels: const ['阅读', '计划'],
        ),
      );
      values['other-owned-draft'] = 'unrelated';
      final ledgerBefore = values[recovery.ledger(destination.assistant!).key];
      final db = await store.database;
      final sqlBefore = await db.query('notes');
      final snapshot = (await archive.inspect())!;
      expect(snapshot.note!.content, content);
      expect(snapshot.note!.labels, ['阅读', '计划']);
      expect(snapshot.raw, contains('updated_at'));
      await archive.clear(snapshot);
      expect(await archive.notes.read(null), isNull);
      expect(values['other-owned-draft'], 'unrelated');
      expect(values[recovery.ledger(destination.assistant!).key], ledgerBefore);
      expect(await db.query('notes'), sqlBefore);
      expect(await db.query('assistant_creation_receipts'), isEmpty);
    },
  );
  test(
    'positive task archive preserves full actual task and other null-ID draft',
    () async {
      final destination = await cancelled(task: true, resourceId: 19);
      final archive = recovery.retained(destination);
      await archive.tasks.write(
        const TaskItem(
          id: 19,
          parentId: 0,
          content: '  Full actual task  ',
          dueDate: '2026-11-20',
          done: true,
        ),
      );
      await archive.tasks.write(
        const TaskItem(parentId: 0, content: 'Other null draft', dueDate: ''),
      );
      final snapshot = (await archive.inspect())!;
      expect(snapshot.task!.id, 19);
      expect(snapshot.content, '  Full actual task  ');
      expect(snapshot.task!.done, true);
      expect(snapshot.task!.dueDate, '2026-11-20');
      await archive.clear(snapshot);
      expect(await archive.tasks.read(19, parentId: 0), isNull);
      expect(
        (await archive.tasks.read(null, parentId: 0))!.content,
        'Other null draft',
      );
    },
  );
  test(
    'fingerprint binds entire raw snapshot including fields not used by preview',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      await archive.notes.write(const Note(title: 'Title', content: 'Content'));
      final snapshot = (await archive.inspect())!;
      final raw = jsonDecode(snapshot.raw) as Map<String, dynamic>;
      raw['unknown-future-field'] = {'keep': 'exact'};
      await archive.notes.writeRecord(null, jsonEncode(raw));
      final before = Map<String, String>.of(values);
      await expectLater(archive.clear(snapshot), throwsStateError);
      expect(values, before);
      expect(
        (await archive.inspect())!.fingerprint,
        isNot(snapshot.fingerprint),
      );
    },
  );
  test(
    'fresh receipt appearing after review blocks deletion without touching vault',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      await archive.notes.write(const Note(title: 'Title', content: 'Content'));
      final snapshot = (await archive.inspect())!;
      final input = LocalAssistantCreationInput.note(
        const Note(title: 'Actually saved', content: 'Body'),
      );
      await LocalAssistantCreationReceipts(store).create(
        destination.assistant!.draftId,
        input,
        preparedHash: input.digest,
      );
      final before = Map<String, String>.of(values);
      await expectLater(archive.clear(snapshot), throwsStateError);
      expect(values, before);
      expect((await (await store.database).query('notes')).length, 1);
    },
  );
  test(
    'marker or changed ledger prevents archive; uncertain writes never enter',
    () async {
      final destination = await cancelled();
      final identity = destination.assistant!;
      final archive = recovery.retained(destination);
      await archive.notes.write(const Note(title: 'Title', content: 'Content'));
      final snapshot = (await archive.inspect())!;
      values[identity.key] = jsonEncode({'format': 1, 'input_hash': 'c' * 64});
      await expectLater(archive.clear(snapshot), throwsStateError);
      values.remove(identity.key);
      final key = recovery.ledger(identity).key;
      final data = jsonDecode(values[key]!) as Map<String, dynamic>;
      final record = (data['drafts'] as List).single as Map<String, dynamic>;
      record['state'] = 'unknown';
      record['input_hash'] = 'c' * 64;
      values[key] = jsonEncode(data);
      await expectLater(archive.inspect(), throwsStateError);
      expect(await archive.notes.read(null), isNotNull);
    },
  );
  test(
    'corrupt or unreadable vault is retained and is not an empty draft',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      await archive.notes.writeRecord(null, 'malformed');
      final before = Map<String, String>.of(values);
      await expectLater(archive.inspect(), throwsFormatException);
      expect(values, before);
      failRead = true;
      await expectLater(archive.inspect(), throwsStateError);
      expect(values, before);
    },
  );
  test(
    'cancelled proposal that never opened an editor has no archive or cleanup',
    () async {
      final destination = await cancelled();
      final before = Map<String, String>.of(values);
      expect(await recovery.retained(destination).inspect(), isNull);
      expect(await recovery.needsReview(destination), false);
      expect(values, before);
    },
  );
  test(
    'lost durability acknowledgement after applied delete restores exact raw and keeps blocking',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      await archive.notes.write(
        const Note(title: 'Title', content: '\uFEFFBody\r\n'),
      );
      final snapshot = (await archive.inspect())!;
      final before = Map<String, String>.of(values);
      loseDelete = true;
      await expectLater(archive.clear(snapshot), throwsStateError);
      expect(values, before);
      expect((await archive.inspect())!.raw, snapshot.raw);
      await archive.clear(await archive.inspect().then((value) => value!));
      expect(await archive.notes.read(null), isNull);
    },
  );
  test(
    'origin retirement and scope guard precede all archive SQL/storage actions',
    () async {
      final destination = await cancelled();
      final archive = recovery.retained(destination);
      await archive.notes.write(const Note(title: 'Title', content: 'Body'));
      final before = Map<String, String>.of(values);
      drain = () async {
        current = false;
      };
      await expectLater(
        archive.inspect(),
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      expect(values, before);
      expect(File(store.path).existsSync(), false);
    },
  );
}
