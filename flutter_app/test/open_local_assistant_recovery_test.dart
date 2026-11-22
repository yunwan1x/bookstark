import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_save_review.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_recovery_resolver.dart';
import 'package:bookstark_flutter/core/local_store.dart';
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
  bool current = true;
  Future<void> Function() drain = () async {};
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    );
    await base.create(recursive: true);
    directory = await base.createTemp('assistant-recovery-');
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
    values.clear();
    drain = () async {};
    recovery = LocalAssistantRecovery(
      store: store,
      isCurrent: () => current,
      drainOriginatingSave: (_) => drain(),
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<LocalRecoveryDestination> pending() async {
    final identity = LocalAssistantWriteMarker(
      namespace: 'local',
      bindingId: 'a' * 32,
      draftId: 'b' * 32,
      kind: LocalAssistantDraftKind.note,
    );
    final record = await recovery
        .ledger(identity)
        .propose(
          LocalAssistantDraftPayload.note(title: 'Review', content: 'Body'),
        );
    final marker = LocalAssistantWriteMarker(
      namespace: 'local',
      bindingId: 'a' * 32,
      draftId: record.id,
      kind: LocalAssistantDraftKind.note,
    );
    return LocalRecoveryDestination(
      kind: 'ai-editor',
      namespace: LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: marker.bindingId,
        draft: marker.draftId,
        kind: marker.kind,
      ),
      title: '',
      assistant: marker,
    );
  }

  test(
    'pending editor resumes only after originating save drains; no SQL opened',
    () async {
      final destination = await pending();
      final barrier = Completer<void>();
      drain = () => barrier.future;
      var finished = false;
      final result = recovery.needsReview(destination).then((value) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      barrier.complete();
      expect(await result, false);
      expect(File(store.path).existsSync(), false);
    },
  );
  test(
    'marker routes editor to read-only review without SQL even on old schema',
    () async {
      final destination = await pending();
      final identity = destination.assistant!;
      final record = (await recovery.ledger(identity).load()).single;
      await recovery.journal(identity).prepare(record, 'c' * 64);
      expect(await recovery.needsReview(destination), true);
      expect(File(store.path).existsSync(), false);
    },
  );
  test(
    'missing creation marker and damaged marker remain blocking unchanged',
    () async {
      final destination = await pending();
      final identity = destination.assistant!;
      final creation = LocalRecoveryDestination(
        kind: 'ai-create',
        namespace: 'local',
        title: '',
        assistant: identity,
      );
      await expectLater(recovery.needsReview(creation), throwsStateError);
      values[identity.key] = 'broken';
      final before = Map<String, String>.of(values);
      await expectLater(recovery.needsReview(destination), throwsA(anything));
      expect(values, before);
      expect(File(store.path).existsSync(), false);
    },
  );
  test(
    'retirement during drain blocks storage reads and editor resume',
    () async {
      final destination = await pending();
      drain = () async {
        current = false;
      };
      await expectLater(recovery.needsReview(destination), throwsA(anything));
      expect(File(store.path).existsSync(), false);
    },
  );
  test(
    'identity rejects cross generation namespace and ordinary resource IDs',
    () async {
      final destination = await pending();
      expect(
        () => recovery.identity(
          LocalRecoveryDestination(
            kind: 'ai-editor',
            namespace: 'wrong',
            title: '',
            assistant: destination.assistant,
          ),
        ),
        throwsStateError,
      );
      expect(
        () => recovery.identity(
          LocalRecoveryDestination(
            kind: 'ai-create',
            namespace: 'local',
            title: '',
            id: 1,
            assistant: destination.assistant,
          ),
        ),
        throwsStateError,
      );
    },
  );
  Future<LocalRecoveryDestination> committed() async {
    final destination = await pending();
    final identity = destination.assistant!;
    final input = LocalAssistantCreationInput.note(
      const Note(title: 'Saved actual', content: 'Actual editor content'),
    );
    final ledger = recovery.ledger(identity);
    await ledger.prepare(identity.draftId, input.digest);
    final receipt = await LocalAssistantCreationReceipts(
      store,
    ).create(identity.draftId, input, preparedHash: input.digest);
    await ledger.acknowledge(identity.draftId, receipt);
    return destination;
  }

  test(
    'markerless committed editor verifies receipt and resumes same ID',
    () async {
      final destination = await committed();
      final receipt = await recovery.createdReceipt(destination);
      final positive = LocalRecoveryDestination(
        kind: 'ai-editor',
        namespace: destination.namespace,
        title: '',
        assistant: destination.assistant,
        assistantResourceId: receipt.resourceId,
      );
      final before = Map<String, String>.of(values);
      expect(await recovery.needsReview(positive), false);
      expect(
        (await recovery.createdReceipt(positive)).resourceId,
        receipt.resourceId,
      );
      expect(values, before);
      final creation = LocalRecoveryDestination(
        kind: 'ai-create',
        namespace: 'local',
        title: '',
        assistant: destination.assistant,
      );
      expect(await recovery.needsReview(creation), true);
    },
  );
  test('positive vault identity must match exact committed receipt', () async {
    final destination = await committed();
    final receipt = await recovery.createdReceipt(destination);
    final wrong = LocalRecoveryDestination(
      kind: 'ai-editor',
      namespace: destination.namespace,
      title: '',
      assistant: destination.assistant,
      assistantResourceId: receipt.resourceId + 1,
    );
    await expectLater(recovery.needsReview(wrong), throwsStateError);
    final db = await store.database;
    expect((await db.query('notes')).length, 1);
  });
  test(
    'positive ID cannot promote pending draft and missing marker cannot retry unknown',
    () async {
      final destination = await pending();
      final identity = destination.assistant!;
      final positive = LocalRecoveryDestination(
        kind: 'ai-editor',
        namespace: destination.namespace,
        title: '',
        assistant: identity,
        assistantResourceId: 100,
      );
      await expectLater(recovery.needsReview(positive), throwsStateError);
      expect(File(store.path).existsSync(), false);
      await recovery.ledger(identity).prepare(identity.draftId, 'c' * 64);
      await recovery.ledger(identity).markUnknown(identity.draftId);
      final before = Map<String, String>.of(values);
      await expectLater(recovery.needsReview(destination), throwsStateError);
      expect(values, before);
      expect(File(store.path).existsSync(), false);
    },
  );
  test(
    'markerless acknowledged review preserves edited vault without cleanup',
    () async {
      final destination = await committed();
      final identity = destination.assistant!;
      values['owned-edited-vault'] = 'newer unsaved editor content';
      final service = LocalAssistantSaveReview(
        receipts: LocalAssistantCreationReceipts(store),
        ledger: recovery.ledger(identity),
        journal: recovery.journal(identity),
        identity: identity,
        drainOriginatingSave: () async {},
      );
      final before = Map<String, String>.of(values);
      await service.resolve(await service.inspect());
      expect(values, before);
      expect((await (await store.database).query('notes')).length, 1);
    },
  );
  test(
    'markerless unacknowledged receipt remains blocking rather than auto-adopted',
    () async {
      final destination = await pending();
      final identity = destination.assistant!;
      final input = LocalAssistantCreationInput.note(
        const Note(title: 'Uncertain', content: 'Body'),
      );
      await recovery.ledger(identity).prepare(identity.draftId, input.digest);
      await LocalAssistantCreationReceipts(
        store,
      ).create(identity.draftId, input, preparedHash: input.digest);
      final service = LocalAssistantSaveReview(
        receipts: LocalAssistantCreationReceipts(store),
        ledger: recovery.ledger(identity),
        journal: recovery.journal(identity),
        identity: identity,
        drainOriginatingSave: () async {},
      );
      final before = Map<String, String>.of(values);
      await expectLater(service.inspect(), throwsStateError);
      expect(values, before);
      expect((await (await store.database).query('notes')).length, 1);
    },
  );
  test(
    'applied marker deletion with lost flush is safely reviewed without replay',
    () async {
      final destination = await pending();
      final identity = destination.assistant!;
      final input = LocalAssistantCreationInput.note(
        const Note(title: 'Known commit', content: 'Edited body'),
      );
      final ledger = recovery.ledger(identity);
      final record = (await ledger.load()).single;
      final journal = LocalAssistantWriteJournal(
        namespace: identity.namespace,
        bindingId: identity.bindingId,
        maintenance: store.maintenance,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
          throw StateError('lost flush');
        },
      );
      await journal.prepare(record, input.digest);
      await ledger.prepare(identity.draftId, input.digest);
      await LocalAssistantCreationReceipts(
        store,
      ).create(identity.draftId, input, preparedHash: input.digest);
      values['edited-vault'] = 'Unsent later edits';
      final service = LocalAssistantSaveReview(
        receipts: LocalAssistantCreationReceipts(store),
        ledger: ledger,
        journal: journal,
        identity: identity,
        drainOriginatingSave: () async {},
      );
      await expectLater(
        service.resolve(await service.inspect()),
        throwsA(isA<LocalAssistantWriteMarkerUnknown>()),
      );
      expect(values.containsKey(identity.key), false);
      final before = Map<String, String>.of(values);
      await service.resolve(await service.inspect());
      expect(values, before);
      expect(values['edited-vault'], 'Unsent later edits');
      expect((await (await store.database).query('notes')).length, 1);
    },
  );
  test(
    'saved-review routing uses native editor only for readable matching or changed states',
    () async {
      final destination = await committed();
      final identity = destination.assistant!;
      final receipts = LocalAssistantCreationReceipts(store);
      expect(
        canResumeSavedAssistantReview(await receipts.inspect(identity.draftId)),
        true,
      );
      final id = (await receipts.lookup(identity.draftId))!.resourceId;
      final db = await store.database;
      await db.update(
        'notes',
        {'content': 'Changed content'},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        canResumeSavedAssistantReview(await receipts.inspect(identity.draftId)),
        true,
      );
      await db.update(
        'notes',
        {'collection': 'article'},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        canResumeSavedAssistantReview(await receipts.inspect(identity.draftId)),
        false,
      );
      await db.update(
        'notes',
        {'collection': 'note', 'content': 'ENC:v2:protected'},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        canResumeSavedAssistantReview(await receipts.inspect(identity.draftId)),
        false,
      );
      await db.update(
        'notes',
        {'deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        canResumeSavedAssistantReview(await receipts.inspect(identity.draftId)),
        false,
      );
    },
  );
  testWidgets(
    'cancelled actual editor draft opens retained archive and explicit clear removes only that vault',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final destination = await pending();
      final identity = destination.assistant!;
      await recovery.ledger(identity).cancel(identity.draftId);
      final archive = recovery.retained(destination);
      await archive.notes.write(
        const Note(
          title: 'Actual retained note',
          content: '## Original edited body',
        ),
      );
      // Open the real FFI database outside FakeAsync before UI callbacks.
      await tester.runAsync(() async {
        await archive.inspect();
      });
      var forbidden = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => recovery.open(
                  context,
                  destination,
                  onResumeEditor: (_, _) async {
                    forbidden++;
                  },
                  onOpenResource: (_, _) async {
                    forbidden++;
                  },
                ),
                child: const Text('Open recovery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open recovery'));
      for (
        var attempt = 0;
        attempt < 20 && find.text('保留的助手草稿').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('保留的助手草稿'), findsOneWidget);
      expect(find.text('Actual retained note'), findsOneWidget);
      await tester.ensureVisible(find.text('清除此草稿'));
      await tester.tap(find.text('清除此草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清除此草稿'));
      await tester.pumpAndSettle();
      expect(await archive.notes.read(null), isNull);
      expect(
        (await recovery.ledger(identity).load()).single.state,
        LocalAssistantDraftState.cancelled,
      );
      expect((await (await store.database).query('notes')), isEmpty);
      expect(forbidden, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
