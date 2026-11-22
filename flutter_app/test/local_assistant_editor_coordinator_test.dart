import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'package:bookstark_flutter/features/assistant/local_assistant_editor_coordinator.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';

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
  late LocalAssistantDraftLedger ledger;
  late LocalAssistantWriteJournal journal;
  late LocalAssistantCreationReceipts receipts;
  late Map<String, String> values;
  bool failDelete = false;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-editor-ui-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    receipts = LocalAssistantCreationReceipts(store);
    values = {};
    failDelete = false;
    ledger = LocalAssistantDraftLedger(
      namespace: store.path,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
    );
    journal = LocalAssistantWriteJournal(
      namespace: 'local',
      bindingId: 'b' * 32,
      maintenance: store.maintenance,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        if (failDelete) throw StateError('fixture cleanup unavailable');
        values.remove(key);
      },
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  LocalAssistantEditorDrafts vaults(LocalAssistantDraftRecord draft) {
    final namespace = LocalAssistantEditorDrafts.editorNamespace(
      base: 'local',
      binding: 'b' * 32,
      draft: draft.id,
      kind: draft.payload.kind,
    );
    return LocalAssistantEditorDrafts(
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
  }

  LocalAssistantEditorCoordinator coordinator(
    LocalAssistantEditorDrafts drafts,
  ) => LocalAssistantEditorCoordinator(
    receipts: receipts,
    ledger: ledger,
    journal: journal,
    editorDrafts: drafts,
    notes: LocalNotesRepository(store),
    tasks: LocalTasksRepository(store),
  );
  Future<void> noReview(
    LocalAssistantDraftRecord _,
    LocalAssistantWriteMarker? marker,
  ) async {
    fail('Unexpected review');
  }

  test(
    'opens exact recovered note, uses same vault, only explicit save creates',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'Proposal', content: 'Proposed'),
      );
      final drafts = vaults(draft);
      await drafts.notes.write(
        const Note(
          title: 'Edited',
          content: '\ufeff# Actual',
          labels: ['kept'],
        ),
      );
      int? saved;
      await coordinator(drafts).open(
        draftId: draft.id,
        onReview: noReview,
        onSaved: (kind, id) {
          expect(kind, LocalAssistantDraftKind.note);
          saved = id;
        },
        presentPage: (page) async {
          final editor = page as NoteEditorPage;
          expect(identical(editor.drafts, drafts.notes), isTrue);
          expect(editor.note.title, 'Edited');
          expect(await (await store.database).query('notes'), isEmpty);
          await editor.repository.save(editor.note);
        },
      );
      expect(saved, isNotNull);
      final actual = await LocalNotesRepository(store).read(saved!);
      expect(actual.content, '\ufeff# Actual');
      expect(actual.labels, ['kept']);
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.created,
      );
    },
  );
  test('opens task original snapshot and saves real task ID', () async {
    final draft = await ledger.propose(
      LocalAssistantDraftPayload.task(content: 'Proposed'),
    );
    final drafts = vaults(draft);
    await drafts.tasks.write(
      const TaskItem(content: '  Actual  ', dueDate: '2026-11-11'),
    );
    int? saved;
    await coordinator(drafts).open(
      draftId: draft.id,
      onReview: noReview,
      onSaved: (_, id) {
        saved = id;
      },
      presentPage: (page) async {
        final editor = page as TaskEditorPage;
        expect(identical(editor.vault, drafts.tasks), isTrue);
        expect(editor.task.content, '  Actual  ');
        await editor.repository.save(editor.task);
      },
    );
    expect((await LocalTasksRepository(store).read(saved!)).content, 'Actual');
  });
  test('pending marker routes review without opening or replay', () async {
    final draft = await ledger.propose(
      LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
    );
    await journal.prepare(draft, 'a' * 64);
    var reviewed = false;
    await coordinator(vaults(draft)).open(
      draftId: draft.id,
      presentPage: (_) async {
        fail('Must not open editor');
      },
      onReview: (record, marker) async {
        reviewed = true;
        expect(record.state, LocalAssistantDraftState.pending);
        expect(marker!.inputHash, 'a' * 64);
      },
    );
    expect(reviewed, isTrue);
    expect(await receipts.lookup(draft.id), isNull);
  });
  test('committing without marker still requires readonly review', () async {
    final draft = await ledger.propose(
      LocalAssistantDraftPayload.task(content: 'T'),
    );
    await ledger.prepare(draft.id, 'a' * 64);
    await coordinator(vaults(draft)).open(
      draftId: draft.id,
      presentPage: (_) async {
        fail('Must not open editor');
      },
      onReview: (record, marker) async {
        expect(record.state, LocalAssistantDraftState.committing);
        expect(marker, isNull);
      },
    );
  });
  test(
    'same identity cannot open concurrently across coordinator instances',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.task(content: 'T'),
      );
      final drafts = vaults(draft),
          entered = Completer<void>(),
          exit = Completer<void>();
      final first = coordinator(drafts).open(
        draftId: draft.id,
        onReview: noReview,
        presentPage: (_) async {
          entered.complete();
          await exit.future;
        },
      );
      await entered.future;
      expect(
        await coordinator(drafts).open(
          draftId: draft.id,
          onReview: noReview,
          presentPage: (_) async {
            fail('Second owner');
          },
        ),
        isFalse,
      );
      exit.complete();
      await first;
      expect(
        await coordinator(drafts).open(
          draftId: draft.id,
          onReview: noReview,
          presentPage: (_) async {},
        ),
        isTrue,
      );
    },
  );
  test('recovery retires save owner without waiting for page close', () async {
    final draft = await ledger.propose(
      LocalAssistantDraftPayload.task(content: 'T'),
    );
    final entered = Completer<TaskEditorPage>(), exit = Completer<void>();
    final opened = coordinator(vaults(draft)).open(
      draftId: draft.id,
      onReview: noReview,
      presentPage: (page) async {
        entered.complete(page as TaskEditorPage);
        await exit.future;
      },
    );
    final page = await entered.future;
    await LocalAssistantEditorCoordinator.retireAndDrainDraft(
      ledgerKey: ledger.key,
      draftId: draft.id,
    );
    await expectLater(
      page.repository.save(page.task),
      throwsA(isA<LocalAssistantDraftOwnerRetired>()),
    );
    expect(await receipts.lookup(draft.id), isNull);
    exit.complete();
    await opened;
  });
  test(
    'known SQL commit notifies root even when encrypted cleanup fails',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.task(content: 'T'),
      );
      failDelete = true;
      int? saved;
      await coordinator(vaults(draft)).open(
        draftId: draft.id,
        onReview: noReview,
        onSaved: (_, id) {
          saved = id;
        },
        presentPage: (page) async {
          final editor = page as TaskEditorPage;
          await expectLater(
            editor.repository.save(editor.task.copyWith(dueDate: '2026-11-11')),
            throwsA(isA<TaskSaveFailure>()),
          );
        },
      );
      expect(saved, isNotNull);
      expect((await receipts.lookup(draft.id))!.resourceId, saved);
      expect((await (await store.database).query('tasks')).length, 1);
    },
  );
  test('corrupt full editor snapshot is retained and blocks opening', () async {
    final draft = await ledger.propose(
      LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
    );
    final drafts = vaults(draft);
    final key = drafts.notes.metadataKey(null);
    values[key] = 'broken encrypted payload fixture';
    await expectLater(
      coordinator(drafts).open(
        draftId: draft.id,
        onReview: noReview,
        presentPage: (_) async {
          fail('Must not replace corrupt draft');
        },
      ),
      throwsFormatException,
    );
    expect(values[key], 'broken encrypted payload fixture');
    expect(await receipts.lookup(draft.id), isNull);
  });
  Future<LocalAssistantCreationReceipt> saved(
    LocalAssistantDraftRecord draft,
    LocalAssistantCreationInput input,
  ) async {
    await ledger.prepare(draft.id, input.digest);
    final receipt = await receipts.create(
      draft.id,
      input,
      preparedHash: input.digest,
    );
    await ledger.acknowledge(draft.id, receipt);
    return receipt;
  }

  test(
    'positive-ID note draft resumes existing ID and cannot create another note',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(const Note(title: 'N', content: 'B')),
      );
      final drafts = vaults(draft);
      await drafts.notes.write(
        const Note(title: 'older null', content: 'older'),
      );
      await drafts.notes.write(
        Note(
          id: receipt.resourceId,
          title: 'Actual edit',
          content: '\ufeffEdited after commit',
          labels: ['retained'],
        ),
      );
      await coordinator(drafts).resumeSaved(
        draftId: draft.id,
        expectedResourceId: receipt.resourceId,
        onReview: noReview,
        presentPage: (page) async {
          final editor = page as NoteEditorPage;
          expect(editor.note.id, receipt.resourceId);
          expect(editor.note.title, 'N');
          expect(editor.note.content, 'B');
          final recovered = await drafts.notes.read(receipt.resourceId);
          expect(recovered!.title, 'Actual edit');
          expect(recovered.content, '\ufeffEdited after commit');
          expect(recovered.labels, ['retained']);
          await expectLater(
            editor.repository.save(const Note(title: 'Wrong', content: 'X')),
            throwsStateError,
          );
          await editor.repository.save(recovered);
        },
      );
      expect((await (await store.database).query('notes')).length, 1);
      expect(
        (await LocalNotesRepository(store).read(receipt.resourceId)).title,
        'Actual edit',
      );
      expect((await drafts.notes.read(null))!.title, 'older null');
    },
  );
  test(
    'created task with only null draft resumes the acknowledged ID',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.task(content: 'T', dueDate: '2026-11-11'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.task(
          const TaskItem(content: 'T', dueDate: '2026-11-11'),
        ),
      );
      final drafts = vaults(draft);
      await drafts.tasks.write(
        const TaskItem(content: '  New edited text  ', dueDate: '2026-11-12'),
      );
      await coordinator(drafts).resumeSaved(
        draftId: draft.id,
        onReview: noReview,
        presentPage: (page) async {
          final editor = page as TaskEditorPage;
          expect(editor.task.id, receipt.resourceId);
          expect(editor.task.content, 'T');
          final recovered = await drafts.tasks.read(
            receipt.resourceId,
            parentId: 0,
          );
          expect(recovered!.content, '  New edited text  ');
          expect(await drafts.tasks.read(null, parentId: 0), isNull);
          await editor.repository.save(recovered);
        },
      );
      expect((await (await store.database).query('tasks')).length, 1);
      expect(
        (await LocalTasksRepository(store).read(receipt.resourceId)).content,
        'New edited text',
      );
    },
  );
  test(
    'saved resume rejects a vault destination bound to a different actual ID',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(const Note(title: 'N', content: 'B')),
      );
      await expectLater(
        coordinator(vaults(draft)).resumeSaved(
          draftId: draft.id,
          expectedResourceId: receipt.resourceId + 1,
          onReview: noReview,
          presentPage: (_) async {
            fail('Wrong destination must never open');
          },
        ),
        throwsStateError,
      );
    },
  );
  test(
    'changed saved resource needs explicit fresh review fingerprint before same-ID edit',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(const Note(title: 'N', content: 'B')),
      );
      await LocalNotesRepository(
        store,
      ).save(Note(id: receipt.resourceId, title: 'Changed', content: 'New'));
      var reviewed = false;
      final owner = coordinator(vaults(draft));
      await owner.resumeSaved(
        draftId: draft.id,
        presentPage: (_) async {
          fail('Review first');
        },
        onReview: (_, marker) async {
          reviewed = true;
          expect(marker, isNull);
        },
      );
      expect(reviewed, isTrue);
      final inspected = await receipts.inspect(draft.id);
      await owner.resumeSaved(
        draftId: draft.id,
        reviewedFingerprint: inspected.fingerprint,
        onReview: noReview,
        presentPage: (page) async {
          final editor = page as NoteEditorPage;
          expect(editor.note.id, receipt.resourceId);
          expect(editor.note.title, 'Changed');
        },
      );
    },
  );
  test(
    'deleted saved resource requires review and cannot be resurrected',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(const Note(title: 'N', content: 'B')),
      );
      await (await store.database).delete(
        'notes',
        where: 'id=?',
        whereArgs: [receipt.resourceId],
      );
      var reviewed = false;
      await coordinator(vaults(draft)).resumeSaved(
        draftId: draft.id,
        onReview: (_, marker) async {
          reviewed = true;
        },
        presentPage: (_) async {
          fail('Must not recreate missing note');
        },
      );
      expect(reviewed, isTrue);
      expect(await (await store.database).query('notes'), isEmpty);
      expect((await receipts.lookup(draft.id))!.resourceId, receipt.resourceId);
    },
  );
  test(
    'bridge failure retains full copies and successful retry updates same ID once',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(const Note(title: 'N', content: 'B')),
      );
      final namespace = LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: 'b' * 32,
        draft: draft.id,
        kind: draft.payload.kind,
      );
      var cleanupFails = false;
      final drafts = LocalAssistantEditorDrafts(
        notes: DraftVault(
          namespace: namespace,
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            if (cleanupFails) throw StateError('fixture cleanup unavailable');
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
      await drafts.notes.write(
        const Note(title: 'Edited', content: 'Edited body'),
      );
      final db = await store.database;
      await db.execute('CREATE TEMP TABLE ai_update_counts(n INTEGER)');
      await db.execute('INSERT INTO ai_update_counts VALUES(0)');
      await db.execute(
        'CREATE TEMP TRIGGER ai_count_updates AFTER UPDATE ON notes '
        'BEGIN UPDATE ai_update_counts SET n=n+1; END',
      );
      cleanupFails = true;
      await expectLater(
        coordinator(drafts).resumeSaved(
          draftId: draft.id,
          onReview: noReview,
          presentPage: (_) async {
            fail('Failed bridge must not present editor');
          },
        ),
        throwsStateError,
      );
      expect((await drafts.notes.read(null))!.content, 'Edited body');
      expect(
        (await drafts.notes.read(receipt.resourceId))!.content,
        'Edited body',
      );
      expect(
        (await db.rawQuery('SELECT n FROM ai_update_counts')).single['n'],
        0,
      );
      cleanupFails = false;
      await coordinator(drafts).resumeSaved(
        draftId: draft.id,
        onReview: noReview,
        presentPage: (page) async {
          final editor = page as NoteEditorPage;
          expect(editor.note.content, 'B');
          final recovered = (await drafts.notes.read(receipt.resourceId))!;
          expect(await drafts.notes.read(null), isNull);
          await editor.repository.save(recovered);
          await editor.repository.save(recovered);
          expect(
            (await db.rawQuery('SELECT n FROM ai_update_counts')).single['n'],
            1,
          );
        },
      );
      expect((await db.query('notes')).length, 1);
    },
  );
  test(
    'review handoff releases the draft lock before same-ID editor resume',
    () async {
      final draft = await ledger.propose(
        LocalAssistantDraftPayload.note(title: 'Saved', content: 'Original'),
      );
      final receipt = await saved(
        draft,
        LocalAssistantCreationInput.note(
          const Note(title: 'Saved', content: 'Original'),
        ),
      );
      await LocalNotesRepository(store).save(
        Note(
          id: receipt.resourceId,
          title: 'Saved',
          content: 'Changed elsewhere',
        ),
      );
      final drafts = vaults(draft);
      var presented = 0;
      await coordinator(drafts).resumeSaved(
        draftId: draft.id,
        presentPage: (_) async {
          fail('Changed content requires review');
        },
        onReview: (record, marker) async {
          expect(marker, isNull);
          final inspected = await receipts.inspect(record.id);
          final opened = await coordinator(drafts).resumeSaved(
            draftId: record.id,
            expectedResourceId: receipt.resourceId,
            reviewedFingerprint: inspected.fingerprint,
            onReview: noReview,
            presentPage: (page) async {
              presented++;
              expect((page as NoteEditorPage).note.id, receipt.resourceId);
            },
          );
          expect(opened, true);
        },
      );
      expect(presented, 1);
      expect((await (await store.database).query('notes')).length, 1);
      expect(
        (await LocalNotesRepository(store).read(receipt.resourceId)).content,
        'Changed elsewhere',
      );
    },
  );
  for (final kind in LocalAssistantDraftKind.values) {
    for (final choice in ['restore', 'saved', 'keep']) {
      testWidgets(
        'real ${kind.name} resume baseline and $choice recovery choice',
        (tester) async {
          await tester.runAsync(() async {
            final payload = kind == LocalAssistantDraftKind.note
                ? LocalAssistantDraftPayload.note(
                    title: 'Original title',
                    content: 'Original',
                  )
                : LocalAssistantDraftPayload.task(
                    content: 'Original',
                    dueDate: '2026-11-11',
                  );
            final draft = await ledger.propose(payload);
            final input = kind == LocalAssistantDraftKind.note
                ? LocalAssistantCreationInput.note(
                    const Note(title: 'Original title', content: 'Original'),
                  )
                : LocalAssistantCreationInput.task(
                    const TaskItem(content: 'Original', dueDate: '2026-11-11'),
                  );
            final receipt = await saved(draft, input);
            final drafts = vaults(draft);
            if (kind == LocalAssistantDraftKind.note) {
              await drafts.notes.write(
                Note(
                  id: receipt.resourceId,
                  title: 'Unsaved title',
                  content: '\ufeffUnsaved body',
                  labels: ['actual draft'],
                ),
              );
            } else {
              await drafts.tasks.write(
                const TaskItem(
                  content: 'Unsaved task',
                  dueDate: '2026-11-12',
                  done: true,
                ),
              );
            }
            final db = await store.database;
            await db.execute('CREATE TEMP TABLE ai_update_counts(n INTEGER)');
            await db.execute('INSERT INTO ai_update_counts VALUES(0)');
            final table = kind == LocalAssistantDraftKind.note
                ? 'notes'
                : 'tasks';
            await db.execute(
              'CREATE TEMP TRIGGER ai_count_updates AFTER UPDATE ON $table '
              'BEGIN UPDATE ai_update_counts SET n=n+1; END',
            );
            await coordinator(drafts).resumeSaved(
              draftId: draft.id,
              onReview: noReview,
              presentPage: (page) async {
                if (page is NoteEditorPage) {
                  expect(page.note.content, 'Original');
                  expect(page.note.title, 'Original title');
                } else {
                  expect((page as TaskEditorPage).task.content, 'Original');
                  expect(page.task.dueDate, '2026-11-11');
                }
                await tester.pumpWidget(MaterialApp(home: page));
                await tester.pumpAndSettle();
                expect(find.text('发现未保存草稿'), findsOneWidget);
                expect(
                  (await db.rawQuery(
                    'SELECT n FROM ai_update_counts',
                  )).single['n'],
                  0,
                );
                if (choice == 'saved') {
                  await tester.tap(find.text('使用已保存内容'));
                  await tester.pumpAndSettle();
                  if (kind == LocalAssistantDraftKind.note) {
                    expect(await drafts.notes.read(receipt.resourceId), isNull);
                  } else {
                    expect(
                      await drafts.tasks.read(receipt.resourceId, parentId: 0),
                      isNull,
                    );
                    expect(await drafts.tasks.read(null, parentId: 0), isNull);
                  }
                } else {
                  await tester.tap(find.text('恢复草稿'));
                  await tester.pumpAndSettle();
                  expect(
                    find.text(
                      kind == LocalAssistantDraftKind.note ? '未保存' : '有未保存的修改',
                    ),
                    findsOneWidget,
                  );
                  if (choice == 'restore') {
                    await tester.tap(find.text('保存'));
                    await tester.pumpAndSettle();
                    expect(
                      (await db.rawQuery(
                        'SELECT n FROM ai_update_counts',
                      )).single['n'],
                      1,
                    );
                  }
                }
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              },
            );
            expect((await db.query(table)).length, 1);
            if (kind == LocalAssistantDraftKind.note) {
              final actual = await LocalNotesRepository(
                store,
              ).read(receipt.resourceId);
              expect(
                actual.content,
                choice == 'restore' ? '\ufeffUnsaved body' : 'Original',
              );
              if (choice == 'keep') {
                expect(
                  (await drafts.notes.read(receipt.resourceId))!.content,
                  '\ufeffUnsaved body',
                );
              }
              expect(await drafts.notes.read(null), isNull);
            } else {
              final actual = await LocalTasksRepository(
                store,
              ).read(receipt.resourceId);
              expect(
                actual.content,
                choice == 'restore' ? 'Unsaved task' : 'Original',
              );
              expect(
                actual.dueDate,
                choice == 'restore' ? '2026-11-12' : '2026-11-11',
              );
              expect(actual.done, choice == 'restore');
              if (choice == 'keep') {
                expect(
                  (await drafts.tasks.read(
                    receipt.resourceId,
                    parentId: 0,
                  ))!.content,
                  'Unsaved task',
                );
              }
              expect(await drafts.tasks.read(null, parentId: 0), isNull);
            }
            expect(
              (await db.rawQuery('SELECT n FROM ai_update_counts')).single['n'],
              choice == 'restore' ? 1 : 0,
            );
          });
        },
      );
    }
  }
  for (final failure in ['write', 'readback']) {
    test(
      'legacy bridge $failure failure retains original full null draft',
      () async {
        final draft = await ledger.propose(
          LocalAssistantDraftPayload.note(title: 'N', content: 'B'),
        );
        final receipt = await saved(
          draft,
          LocalAssistantCreationInput.note(
            const Note(title: 'N', content: 'B'),
          ),
        );
        final base = vaults(draft);
        final positiveKey = base.notes.metadataKey(receipt.resourceId);
        final notes = DraftVault(
          namespace: base.notes.namespace,
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            if (key == positiveKey) {
              if (failure == 'write') {
                throw StateError('fixture write unavailable');
              }
              values[key] = 'invalid readback fixture';
            } else {
              values[key] = value;
            }
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        );
        final drafts = LocalAssistantEditorDrafts(
          notes: notes,
          tasks: base.tasks,
        );
        await notes.write(
          const Note(
            title: 'Full original',
            content: '\ufeffFull edited body',
            labels: ['kept'],
          ),
        );
        await expectLater(
          coordinator(drafts).resumeSaved(
            draftId: draft.id,
            onReview: noReview,
            presentPage: (_) async {
              fail('Unverified copy must not open');
            },
          ),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
        final original = await notes.read(null);
        expect(original!.title, 'Full original');
        expect(original.content, '\ufeffFull edited body');
        expect(original.labels, ['kept']);
        expect(
          (await LocalNotesRepository(store).read(receipt.resourceId)).content,
          'B',
        );
        expect((await (await store.database).query('notes')).length, 1);
      },
    );
  }
}
