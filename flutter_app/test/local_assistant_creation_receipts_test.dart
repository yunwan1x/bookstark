import 'support/frozen_schema14_store.dart';
import 'dart:async';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_creator.dart';
import 'package:bookstark_flutter/core/local_assistant_save_review.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

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
  late Directory directory;
  late LocalStore store;
  late LocalAssistantCreationReceipts receipts;
  const key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final input = LocalAssistantCreationInput.note(
    const Note(
      title: '编辑后的标题😀',
      content: '\ufeff## 原文\n\n正文😀',
      labels: ['本地,标签', ' 保留 '],
    ),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookstark-ai-receipt-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    receipts = LocalAssistantCreationReceipts(
      store,
      now: () => DateTime.utc(2026, 11, 10),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<int> count(String table) async {
    final rows = await (await store.database).rawQuery(
      'SELECT count(*) AS n FROM $table',
    );
    return rows.single['n'] as int;
  }

  test(
    'new note and body-free receipt commit together with exact Unicode BOM and labels',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      final note = await LocalNotesRepository(store).read(receipt.resourceId);
      expect(note.title, input.values['title']);
      expect(note.content, input.values['content']);
      expect(note.labels, input.values['labels']);
      expect((await receipts.lookup(key))!.inputHash, input.digest);
      final columns = await (await store.database).rawQuery(
        'PRAGMA table_info(assistant_creation_receipts)',
      );
      expect(columns.map((row) => row['name']).toList(), [
        'creation_key',
        'resource_type',
        'resource_id',
        'input_hash',
        'created_at',
      ]);
    },
  );
  test(
    'receipt failure rolls back both note insertion and sequence movement',
    () async {
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER fail_ai_receipt BEFORE INSERT ON assistant_creation_receipts BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await expectLater(
        receipts.create(key, input, preparedHash: input.digest),
        throwsA(
          isA<DatabaseException>().having(
            (error) => error.toString(),
            'trigger reason',
            contains('fixture'),
          ),
        ),
      );
      expect(await count('notes'), 0);
      expect(await count('assistant_creation_receipts'), 0);
      expect(
        await db.query(
          'sqlite_sequence',
          where: 'name=?',
          whereArgs: ['notes'],
        ),
        isEmpty,
      );
    },
  );
  test(
    'repeated key is read-only even when original resource was permanently deleted',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      await (await store.database).delete(
        'notes',
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      await expectLater(
        receipts.create(key, input, preparedHash: input.digest),
        throwsA(isA<LocalAssistantCreationAlreadyRecorded>()),
      );
      expect(await count('notes'), 0);
      expect((await receipts.lookup(key))!.resourceId, receipt.resourceId);
    },
  );
  test(
    'lost acknowledgement can be inspected without replaying the insert',
    () async {
      await expectLater(
        receipts
            .create(key, input, preparedHash: input.digest)
            .then<void>((_) => throw StateError('lost return')),
        throwsStateError,
      );
      final reopened = LocalAssistantCreationReceipts(store);
      final observed = await reopened.lookup(key);
      expect(observed, isNotNull);
      await expectLater(
        reopened.create(key, input, preparedHash: input.digest),
        throwsA(isA<LocalAssistantCreationAlreadyRecorded>()),
      );
      expect(await count('notes'), 1);
    },
  );
  test(
    'edited digest mismatch and retired owner perform no content write',
    () async {
      expect(
        () => receipts.create(key, input, preparedHash: '0' * 64),
        throwsFormatException,
      );
      final retired = LocalAssistantCreationReceipts(
        store,
        isCurrent: () => false,
      );
      expect(
        () => retired.create(key, input, preparedHash: input.digest),
        throwsA(isA<LocalAssistantCreationOwnerRetired>()),
      );
      expect(await count('notes'), 0);
      expect(await count('assistant_creation_receipts'), 0);
    },
  );
  test(
    'concurrent creation owners cannot create duplicate resources for one key',
    () async {
      final results = await Future.wait([
        receipts
            .create(key, input, preparedHash: input.digest)
            .then<Object>((value) => value, onError: (Object error) => error),
        LocalAssistantCreationReceipts(store)
            .create(key, input, preparedHash: input.digest)
            .then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(results.whereType<LocalAssistantCreationReceipt>().length, 1);
      expect(
        results.whereType<LocalAssistantCreationAlreadyRecorded>().length,
        1,
      );
      expect(await count('notes'), 1);
      expect(await count('assistant_creation_receipts'), 1);
    },
  );
  test(
    'task uses reviewed fields and shares the same no-replay key space',
    () async {
      final task = LocalAssistantCreationInput.task(
        const TaskItem(content: ' 完成阅读😀 ', dueDate: '2028-02-29', done: true),
      );
      final receipt = await receipts.create(
        key,
        task,
        preparedHash: task.digest,
      );
      final row = (await (await store.database).query('tasks')).single;
      expect(row['task_id'], receipt.resourceId);
      expect(row['content'], '完成阅读😀');
      expect(row['due_date'], '2028-02-29');
      expect(row['done'], 1);
      expect(row['parent_id'], 0);
      expect(row['topic_id'], 0);
      expect(row['complete_time'], isNotNull);
      await expectLater(
        receipts.create(key, input, preparedHash: input.digest),
        throwsA(isA<LocalAssistantCreationAlreadyRecorded>()),
      );
      expect(await count('notes'), 0);
      expect(
        () => LocalAssistantCreationInput.task(
          const TaskItem(content: 'child', dueDate: '2028-01-01', parentId: 3),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'durable intent plus read-only receipt recovery adopts the actual saved ID',
    () async {
      final encryptedValues = <String, String>{};
      LocalAssistantDraftLedger ledger() => LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => encryptedValues[key],
        writeValue: (key, value) async {
          encryptedValues[key] = value;
        },
      );
      final draft = await ledger().propose(
        LocalAssistantDraftPayload.note(
          title: 'Original proposal',
          content: 'Original text',
        ),
      );
      await ledger().prepare(draft.id, input.digest);
      await expectLater(
        receipts
            .create(draft.id, input, preparedHash: input.digest)
            .then<void>((_) => throw StateError('lost return')),
        throwsStateError,
      );
      expect(
        (await ledger().load()).single.state,
        LocalAssistantDraftState.committing,
      );
      final actual = (await receipts.lookup(draft.id))!;
      final wrong = LocalAssistantCreationReceipt(
        key: draft.id,
        kind: actual.kind,
        resourceId: actual.resourceId,
        inputHash: '0' * 64,
        createdAt: actual.createdAt,
      );
      await expectLater(
        ledger().acknowledge(draft.id, wrong),
        throwsStateError,
      );
      expect((await ledger().load()).single.resourceId, isNull);
      await ledger().acknowledge(draft.id, actual);
      final recovered = (await ledger().load()).single;
      expect(recovered.state, LocalAssistantDraftState.created);
      expect(recovered.resourceId, actual.resourceId);
      expect(
        (await LocalNotesRepository(store).read(actual.resourceId)).title,
        input.values['title'],
      );
      expect(await count('notes'), 1);
    },
  );
  test(
    'unmigrated active14 never lazily creates a receipt table or content',
    () async {
      final old = FrozenSchema14Store(
        path: '${directory.path}/unmigrated.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await old.database;
        final service = LocalAssistantCreationReceipts(old);
        await expectLater(
          service.create(key, input, preparedHash: input.digest),
          throwsFormatException,
        );
        await expectLater(service.lookup(key), throwsFormatException);
        expect(await db.query('notes'), isEmpty);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name='assistant_creation_receipts'",
          ),
          isEmpty,
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          14,
        );
      } finally {
        await old.close();
      }
    },
  );
  test(
    'inspection preserves exact BOM and detects changed content without writes',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      final db = await store.database;
      final before = await db.query('notes');
      final first = await receipts.inspect(key);
      expect(first.state, LocalAssistantCreationResourceState.matching);
      expect(first.note!.content, input.values['content']);
      expect(await db.query('notes'), before);
      await db.update(
        'notes',
        {'content': 'changed'},
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      final changed = await receipts.inspect(key);
      expect(changed.state, LocalAssistantCreationResourceState.changed);
      expect(changed.note!.content, 'changed');
      expect(changed.fingerprint, isNot(first.fingerprint));
    },
  );
  test(
    'inspection never exposes protected or complex bodies and retains deleted receipt',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      final db = await store.database;
      await db.update(
        'notes',
        {'content': 'ENC:v1:secret'},
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      final protected = await receipts.inspect(key);
      expect(protected.state, LocalAssistantCreationResourceState.protected);
      expect(protected.note, isNull);
      await db.update(
        'notes',
        {'editor_type': 'html', 'content': '<script>private</script>'},
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      final html = await receipts.inspect(key);
      expect(html.state, LocalAssistantCreationResourceState.formatChanged);
      expect(html.note, isNull);
      await db.delete('notes', where: 'id=?', whereArgs: [receipt.resourceId]);
      expect(
        (await receipts.inspect(key)).state,
        LocalAssistantCreationResourceState.missing,
      );
      expect((await receipts.lookup(key))!.resourceId, receipt.resourceId);
      expect(await count('notes'), 0);
    },
  );
  test(
    'invalid UTF8 stays unreadable rather than becoming empty text',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      final db = await store.database;
      await db.rawUpdate(
        "UPDATE notes SET content=CAST(X'FF' AS TEXT) WHERE id=?",
        [receipt.resourceId],
      );
      final result = await receipts.inspect(key);
      expect(result.state, LocalAssistantCreationResourceState.unreadable);
      expect(result.note, isNull);
      expect(
        (await db.rawQuery('SELECT hex(content) AS h FROM notes')).single['h'],
        'FF',
      );
    },
  );
  test(
    'task inspection tracks completion hierarchy and absent identities',
    () async {
      final task = LocalAssistantCreationInput.task(
        const TaskItem(content: 'Read', dueDate: '2028-02-29'),
      );
      final receipt = await receipts.create(
        key,
        task,
        preparedHash: task.digest,
      );
      expect(
        (await receipts.inspect(key)).state,
        LocalAssistantCreationResourceState.matching,
      );
      await (await store.database).update(
        'tasks',
        {'done': 1, 'parent_id': 42},
        where: 'task_id=?',
        whereArgs: [receipt.resourceId],
      );
      final result = await receipts.inspect(key);
      expect(result.state, LocalAssistantCreationResourceState.changed);
      expect(result.task!.parentId, 42);
      final a = await receipts.inspect('b' * 32),
          b = await receipts.inspect('c' * 32);
      expect(a.state, LocalAssistantCreationResourceState.absent);
      expect(a.fingerprint, isNot(b.fingerprint));
    },
  );
  test(
    'review coordinator drains save and adopts receipt with cleanup-only retry',
    () async {
      final values = <String, String>{};
      var failDelete = true, drains = 0;
      final ledger = LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'Proposal', content: 'Draft'),
      );
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: 'b' * 32,
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          if (failDelete) throw StateError('storage unavailable');
          values.remove(key);
        },
      );
      final marker = await journal.prepare(draft, input.digest);
      await ledger.prepare(draft.id, input.digest);
      final receipt = await receipts.create(
        draft.id,
        input,
        preparedHash: input.digest,
      );
      final service = LocalAssistantSaveReview(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        identity: LocalAssistantWriteMarker.fromKey(marker.key),
        drainOriginatingSave: () async {
          drains++;
        },
      );
      final reviewed = await service.inspect();
      await expectLater(
        service.resolve(reviewed),
        throwsA(isA<LocalAssistantWriteMarkerUnknown>()),
      );
      expect((await ledger.load()).single.resourceId, receipt.resourceId);
      expect(await count('notes'), 1);
      failDelete = false;
      await service.resolve(await service.inspect());
      expect(values.containsKey(marker.key), false);
      expect(await count('notes'), 1);
      expect(drains, 1);
    },
  );
  test(
    'review rejects stale content and cancels absent writes without deleting drafts',
    () async {
      final values = <String, String>{};
      final ledger = LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(
          title: 'Keep',
          content: 'Original draft',
        ),
      );
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: 'b' * 32,
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final marker = await journal.prepare(draft, input.digest);
      await ledger.prepare(draft.id, input.digest);
      final service = LocalAssistantSaveReview(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        identity: marker,
        drainOriginatingSave: () async {},
      );
      final absent = await service.inspect();
      final receipt = await receipts.create(
        draft.id,
        input,
        preparedHash: input.digest,
      );
      await expectLater(service.resolve(absent), throwsStateError);
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.committing,
      );
      await (await store.database).delete(
        'assistant_creation_receipts',
        where: 'creation_key=?',
        whereArgs: [draft.id],
      );
      // Fixture simulates an absent transaction; coordinator must not touch the existing note.
      await service.resolve(await service.inspect());
      final record = (await ledger.load()).single;
      expect(record.state, LocalAssistantDraftState.cancelled);
      expect(record.payload.content, 'Original draft');
      expect(
        (await LocalNotesRepository(store).read(receipt.resourceId)).content,
        input.values['content'],
      );
      expect(values.containsKey(marker.key), false);
    },
  );
  test(
    'creator persists full edited snapshot before SQL and never repeats known commit',
    () async {
      final values = <String, String>{};
      var failCleanup = true;
      final vault = DraftVault(
        namespace: 'isolated-ai-editor',
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final ledger = LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'Proposal', content: 'Old'),
      );
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: 'b' * 32,
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          if (failCleanup) throw StateError('cleanup unavailable');
          values.remove(key);
        },
      );
      final creator = LocalAssistantDraftCreator(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        draft: draft,
        persistAndReadEditorSnapshot: (actual) async {
          expect(await count('notes'), 0);
          expect(
            values.keys.where(
              (key) => key.startsWith(LocalAssistantWriteMarker.prefix),
            ),
            isEmpty,
          );
          await vault.write(
            Note(
              title: actual.values['title'] as String,
              content: actual.values['content'] as String,
              labels: (actual.values['labels'] as List).cast<String>(),
            ),
          );
          return LocalAssistantCreationInput.note((await vault.read(null))!);
        },
      );
      await expectLater(
        creator.create(input),
        throwsA(
          isA<LocalAssistantCreationCommitted>().having(
            (e) => e.receipt.resourceId,
            'known ID',
            greaterThan(0),
          ),
        ),
      );
      expect((await vault.read(null))!.content, input.values['content']);
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.created,
      );
      expect(await count('notes'), 1);
      expect(() => creator.create(input), throwsStateError);
      failCleanup = false;
      final acknowledged = await creator.retryKnownAcknowledgement();
      expect(acknowledged.resourceId, (await ledger.load()).single.resourceId);
      expect(
        values.keys.where(
          (key) => key.startsWith(LocalAssistantWriteMarker.prefix),
        ),
        isEmpty,
      );

      expect(await count('notes'), 1);
    },
  );
  test(
    'retiring editor drains pending persistence and prevents a late SQL create',
    () async {
      final values = <String, String>{};
      final ledger = LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'Keep', content: 'Draft'),
      );
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: 'b' * 32,
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final persistence = Completer<LocalAssistantCreationInput>();
      final creator = LocalAssistantDraftCreator(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        draft: draft,
        persistAndReadEditorSnapshot: (_) => persistence.future,
      );
      final saving = creator.create(input);
      final failed = expectLater(
        saving,
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      var drained = false;
      final draining = creator.retireAndDrain().then((_) {
        drained = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      persistence.complete(input);
      await failed;
      await draining;
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
    'oversized current content is bounded and never replaced with an empty preview',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      final db = await store.database;
      const size = 20 * 1024 * 1024 + 1;
      await db.rawUpdate(
        'UPDATE notes SET content=CAST(zeroblob(?) AS TEXT) WHERE id=?',
        [size, receipt.resourceId],
      );
      final result = await receipts.inspect(key);
      expect(result.state, LocalAssistantCreationResourceState.unreadable);
      expect(result.note, isNull);
      expect(
        (await db.rawQuery(
          'SELECT length(CAST(content AS BLOB)) AS n FROM notes',
        )).single['n'],
        size,
      );
      expect(await count('assistant_creation_receipts'), 1);
    },
  );
  test(
    'AI actual editor input cannot create pseudo encrypted note envelopes',
    () async {
      for (final prefix in [
        'ENC:v1:payload',
        '﻿ENC:v2:payload',
        'ENC:unknown:payload',
      ]) {
        expect(
          () => LocalAssistantCreationInput.note(
            Note(title: 'Draft', content: prefix),
          ),
          throwsFormatException,
        );
      }
      expect(await count('notes'), 0);
      expect(await count('assistant_creation_receipts'), 0);
    },
  );
  test(
    'review never exposes a saved note later changed to v2 BOM envelope',
    () async {
      final receipt = await receipts.create(
        key,
        input,
        preparedHash: input.digest,
      );
      await (await store.database).update(
        'notes',
        {'content': '﻿ENC:v2:payload'},
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      final inspected = await receipts.inspect(key);
      expect(inspected.state, LocalAssistantCreationResourceState.protected);
      expect(inspected.note, isNull);
      expect((await receipts.lookup(key))!.resourceId, receipt.resourceId);
    },
  );
}
