import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_repositories.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  });
  late Directory directory;
  late LocalStore store;
  late LocalAssistantCreationReceipts receipts;
  late LocalAssistantDraftLedger ledger;
  late LocalAssistantWriteJournal journal;
  late LocalAssistantEditorDrafts drafts;
  late Map<String, String> values;
  bool failDelete = false, failDraft = false;
  Completer<void>? draftGate, draftEntered, deleteGate, deleteEntered;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-editor-adapter-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    receipts = LocalAssistantCreationReceipts(store);
    values = {};
    failDelete = false;
    failDraft = false;
    draftGate = null;
    draftEntered = null;
    deleteGate = null;
    deleteEntered = null;
    Future<String?> read(String key) async => values[key];
    Future<void> write(String key, String value) async {
      values[key] = value;
    }

    Future<void> delete(String key) async {
      values.remove(key);
    }

    ledger = LocalAssistantDraftLedger(
      namespace: store.path,
      readValue: read,
      writeValue: write,
    );
    journal = LocalAssistantWriteJournal(
      namespace: 'local',
      bindingId: 'b' * 32,
      maintenance: store.maintenance,
      readValue: read,
      writeValue: write,
      deleteValue: (key) async {
        if (failDelete) throw StateError('fixture unavailable');
        if (deleteGate != null) {
          deleteEntered!.complete();
          await deleteGate!.future;
        }
        values.remove(key);
      },
    );
    drafts = LocalAssistantEditorDrafts(
      notes: DraftVault(
        namespace: store.path,
        readValue: read,
        writeValue: (key, value) async {
          if (draftGate != null) {
            draftEntered!.complete();
            await draftGate!.future;
          }
          if (failDraft) throw StateError('fixture draft unavailable');
          await write(key, value);
        },
        deleteValue: delete,
      ),
      tasks: TaskDraftVault(
        namespace: store.path,
        readValue: read,
        writeValue: write,
        deleteValue: delete,
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<int> count(String table) async =>
      (await (await store.database).rawQuery(
            'SELECT COUNT(*) AS n FROM $table',
          )).single['n']
          as int;
  Future<LocalAssistantNotesRepository> notes({
    bool Function()? isCurrent,
  }) async => LocalAssistantNotesRepository(
    underlying: LocalNotesRepository(store),
    isCurrent: isCurrent,
    receipts: receipts,
    ledger: ledger,
    journal: journal,
    draft: await ledger.propose(
      LocalAssistantDraftPayload.note(title: 'Proposal', content: 'Draft'),
    ),
    editorDrafts: drafts,
  );

  test(
    'real edited note persists full draft then creates once; edit updates same ID',
    () async {
      final repository = await notes();
      const original = Note(
        title: ' Actual ',
        content: '\ufeff# 原文😀',
        labels: ['标签', ' spaced '],
      );
      final id = await repository.save(original);
      expect((await drafts.notes.read(null))!.content, original.content);
      expect(
        (await LocalNotesRepository(store).read(id)).labels,
        original.labels,
      );
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER forbid_note_update BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT,'unexpected replay'); END",
      );
      expect(await repository.save(original.copyWith(id: id)), id);
      await db.execute('DROP TRIGGER forbid_note_update');
      expect(
        await repository.save(original.copyWith(id: id, content: 'Changed')),
        id,
      );
      expect((await LocalNotesRepository(store).read(id)).content, 'Changed');
      expect(await count('notes'), 1);
      expect(await count('assistant_creation_receipts'), 1);
    },
  );

  test(
    'known note commit cleanup failure retries only storage; changed edit uses same ID',
    () async {
      final repository = await notes();
      const original = Note(title: 'Known', content: 'Body');
      failDelete = true;
      await expectLater(
        repository.save(original),
        throwsA(
          isA<NoteSaveFailure>().having(
            (e) => e.savedId,
            'actual ID',
            greaterThan(0),
          ),
        ),
      );
      final id = repository.savedId!;
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER forbid_note_update BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT,'unexpected replay'); END",
      );
      failDelete = false;
      expect(await repository.save(original.copyWith(id: id)), id);
      await db.execute('DROP TRIGGER forbid_note_update');
      expect(
        await repository.save(original.copyWith(id: id, title: 'Edited')),
        id,
      );
      expect((await LocalNotesRepository(store).read(id)).title, 'Edited');
      expect(await count('notes'), 1);
    },
  );

  test(
    'edited retry first acknowledges known commit before updating',
    () async {
      final repository = await notes();
      const original = Note(title: 'Known', content: 'Body');
      failDelete = true;
      await expectLater(
        repository.save(original),
        throwsA(isA<NoteSaveFailure>()),
      );
      final id = repository.savedId!;
      await expectLater(
        repository.save(original.copyWith(id: id, content: 'Changed')),
        throwsA(isA<NoteSaveFailure>()),
      );
      expect((await LocalNotesRepository(store).read(id)).content, 'Body');
      failDelete = false;
      expect(
        await repository.save(original.copyWith(id: id, content: 'Changed')),
        id,
      );
      expect((await LocalNotesRepository(store).read(id)).content, 'Changed');
      expect(await count('notes'), 1);
    },
  );

  test(
    'failed full draft persistence never inserts and never silently retries creation',
    () async {
      final repository = await notes();
      failDraft = true;
      const original = Note(title: 'Unknown', content: 'Body');
      await expectLater(repository.save(original), throwsStateError);
      failDraft = false;
      await expectLater(repository.save(original), throwsStateError);
      expect(await count('notes'), 0);
      expect(await count('assistant_creation_receipts'), 0);
      expect(
        values.keys.where(
          (key) => key.startsWith(LocalAssistantWriteMarker.prefix),
        ),
        isEmpty,
      );
    },
  );

  test(
    'retiring drains pending full draft write and prevents late creation',
    () async {
      final repository = await notes();
      draftGate = Completer<void>();
      draftEntered = Completer<void>();
      const original = Note(title: 'Owner', content: 'Original');
      final saving = repository.save(original);
      final failed = expectLater(
        saving,
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      await draftEntered!.future;
      await expectLater(
        repository.save(const Note(title: 'Other', content: 'Overwrite')),
        throwsStateError,
      );
      var drained = false;
      final draining = repository.retireAndDrain().then((_) {
        drained = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      draftGate!.complete();
      await failed;
      await draining;
      expect((await drafts.notes.read(null))!.content, 'Original');
      expect(await count('notes'), 0);
      expect(await count('assistant_creation_receipts'), 0);
    },
  );

  test(
    'scope retirement during delayed acknowledgement cannot update old database',
    () async {
      var current = true;
      final repository = await notes(isCurrent: () => current);
      const original = Note(title: 'Known', content: 'Body');
      failDelete = true;
      await expectLater(
        repository.save(original),
        throwsA(isA<NoteSaveFailure>()),
      );
      final id = repository.savedId!;
      failDelete = false;
      deleteGate = Completer<void>();
      deleteEntered = Completer<void>();
      final saving = repository.save(
        original.copyWith(id: id, content: 'Must not write'),
      );
      final failed = expectLater(
        saving,
        throwsA(
          isA<NoteSaveFailure>().having((e) => e.savedId, 'retained ID', id),
        ),
      );
      await deleteEntered!.future;
      current = false;
      deleteGate!.complete();
      await failed;
      expect((await LocalNotesRepository(store).read(id)).content, 'Body');
      expect(await count('notes'), 1);
      expect(await count('assistant_creation_receipts'), 1);
    },
  );

  test(
    'task known ID failure, storage retry, then real editing only updates same ID',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.task(
          content: 'Proposal',
          dueDate: '2028-02-29',
        ),
      );
      final repository = LocalAssistantTasksRepository(
        underlying: LocalTasksRepository(store),
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        draft: draft,
        editorDrafts: drafts,
      );
      const original = TaskItem(
        content: '  Task😀  ',
        dueDate: '2028-02-29',
        done: true,
      );
      failDelete = true;
      await expectLater(
        repository.save(original),
        throwsA(
          isA<TaskSaveFailure>().having(
            (e) => e.savedId,
            'actual ID',
            greaterThan(0),
          ),
        ),
      );
      final id = repository.savedId!;
      expect(
        (await drafts.tasks.read(null, parentId: 0))!.content,
        original.content,
      );
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER forbid_task_update BEFORE UPDATE ON tasks BEGIN SELECT RAISE(ABORT,'unexpected replay'); END",
      );
      failDelete = false;
      expect(await repository.save(original.copyWith(id: id)), id);
      await db.execute('DROP TRIGGER forbid_task_update');
      expect(
        await repository.save(
          original.copyWith(id: id, done: false, content: 'Changed'),
        ),
        id,
      );
      expect((await LocalTasksRepository(store).read(id)).content, 'Changed');
      expect(await count('tasks'), 1);
      expect(await count('assistant_creation_receipts'), 1);
      await expectLater(
        repository.save(original.copyWith(id: id + 1)),
        throwsStateError,
      );
      await repository.retireAndDrain();
      await expectLater(
        repository.save(original.copyWith(id: id)),
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
    },
  );
}
