import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/local_html_creation_controller.dart';

class CreationMemory {
  final values = <String, String>{};
  bool failWrite = false, failRemove = false;
  int writes = 0;
  int? failAtWrite;
  Future<void>? holdWrite;
  HtmlCreationVault vault({String collection = 'note'}) => HtmlCreationVault(
    server: Uri.parse('https://local.invalid/database'),
    memberId: 1,
    collection: collection,
    localDatabase: true,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      writes++;
      if (failWrite || writes == failAtWrite) {
        throw StateError('injected journal write failure');
      }
      await holdWrite;
      values[k] = v;
    },
    deleteValue: (k) async {
      if (failRemove) throw StateError('injected cleanup failure');
      values.remove(k);
    },
  );
}

class LostCreationRepository extends LocalHtmlNotesRepository {
  LostCreationRepository(super.store);
  int creates = 0;
  @override
  Future<LocalHtmlCreationOutcome> createOnce(
    HtmlNoteEdit edit, {
    required String creationKey,
  }) async {
    creates++;
    await super.createOnce(edit, creationKey: creationKey);
    throw StateError('injected lost result after actual SQLite commit');
  }
}

void main() {
  late Directory directory;
  late LocalStore store;
  late CreationMemory memory;
  setUp(() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    directory = await Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    ).createTemp('html-create-controller-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    memory = CreationMemory();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  HtmlNoteEdit draft({
    String title = 'New HTML',
    String source = '<p>正文🧪</p>\r\n',
  }) =>
      HtmlNoteEdit(title: title, source: source, labels: ['one,literal,label']);
  LocalHtmlCreationController controller({
    LocalHtmlNotesRepository? repository,
    HtmlCreationRecord? record,
  }) => LocalHtmlCreationController(
    repository ?? LocalHtmlNotesRepository(store),
    memory.vault(),
    record: record,
  );
  Future<int> rows() async =>
      (await (await store.database).query('notes')).length;

  test(
    'definite article title rejection stays editable and creates no partial row',
    () async {
      final repo = LocalHtmlNotesRepository(store, collection: 'article');
      await repo.create(draft(title: 'Existing article'));
      final c = LocalHtmlCreationController(
        repo,
        memory.vault(collection: 'article'),
      );
      c.edit(draft(title: 'Existing article'));
      await c.save();
      expect(c.phase, HtmlCreationPhase.editing);
      expect(c.failure, isA<HtmlCreationNameConflict>());
      expect(c.record.pending, false);
      expect(await rows(), 1);
      c.edit(draft(title: 'Different article'));
      await c.save();
      expect(c.phase, HtmlCreationPhase.finished);
      expect(await rows(), 2);
      c.dispose();
    },
  );
  test('intent journal finishes before any actual SQLite creation', () async {
    final gate = Completer<void>();
    memory.holdWrite = gate.future;
    final c = controller();
    c.edit(draft());
    final saving = c.save();
    await Future<void>.delayed(Duration.zero);
    expect(await rows(), 0);
    expect(c.busy, true);
    gate.complete();
    await saving;
    expect(await rows(), 1);
    expect(c.phase, HtmlCreationPhase.finished);
    expect(c.receiptKnown, true);
    expect(memory.values, isEmpty);
    c.dispose();
  });
  test(
    'failed journal write prevents creation and explicit retry uses the same key',
    () async {
      memory.failWrite = true;
      final c = controller();
      c.edit(draft());
      final key = c.record.key;
      await c.save();
      expect(await rows(), 0);
      expect(c.phase, HtmlCreationPhase.editing);
      expect(c.recoveryFailure, isNotNull);
      memory.failWrite = false;
      await c.save();
      expect(c.record.key, key);
      expect(await rows(), 1);
      expect(c.phase, HtmlCreationPhase.finished);
      c.dispose();
    },
  );
  test(
    'lost committed result restores unknown then requires full review and never inserts again',
    () async {
      final lost = LostCreationRepository(store),
          c = controller(repository: lost);
      c.edit(draft());
      await c.save();
      expect(c.phase, HtmlCreationPhase.unknown);
      expect(await rows(), 1);
      expect(lost.creates, 1);
      final record = (await memory.vault().read())!;
      expect(record.pending, true);
      expect(record.createdId, isNull);
      c.dispose();
      final restored = controller(record: record);
      await expectLater(restored.save(), throwsStateError);
      await restored.verify();
      expect(restored.phase, HtmlCreationPhase.review);
      await expectLater(restored.adoptObserved(), throwsStateError);
      final snapshot = restored.observed!;
      restored.markReviewed(snapshot);
      await restored.adoptObserved();
      expect(restored.phase, HtmlCreationPhase.finished);
      expect(restored.receiptKnown, false);
      expect(restored.created!.metadata.id, snapshot.metadata.id);
      expect(await rows(), 1);
      expect(memory.values, isEmpty);
      restored.dispose();
    },
  );
  test(
    'known creation with cleanup failure retries only secure storage',
    () async {
      memory.failRemove = true;
      final c = controller();
      c.edit(draft());
      await c.save();
      expect(c.phase, HtmlCreationPhase.cleanup);
      expect(c.created, isNotNull);
      expect(c.receiptKnown, true);
      expect(await rows(), 1);
      final id = c.created!.metadata.id;
      expect((await memory.vault().read())!.createdId, id);
      await expectLater(c.save(), throwsStateError);
      memory.failRemove = false;
      await c.retryCleanup();
      expect(c.phase, HtmlCreationPhase.finished);
      expect(c.created!.metadata.id, id);
      expect(await rows(), 1);
      expect(memory.values, isEmpty);
      c.dispose();
    },
  );
  test(
    'failure recording the known ID after commit preserves intent and cleanup never replays SQL',
    () async {
      memory.failAtWrite = 2;
      final c = controller();
      c.edit(draft());
      await c.save();
      expect(c.phase, HtmlCreationPhase.cleanup);
      expect(await rows(), 1);
      expect((await memory.vault().read())!.createdId, isNull);
      await c.retryCleanup();
      expect(await rows(), 1);
      expect(memory.values, isEmpty);
      expect(c.phase, HtmlCreationPhase.finished);
      c.dispose();
    },
  );
  test(
    'absent ledger is verified read-only before an explicit same-key retry',
    () async {
      final initial = controller();
      initial.edit(draft());
      final pending = initial.record.copy(pending: true);
      await memory.vault().write(pending);
      initial.dispose();
      final c = controller(record: pending);
      await expectLater(c.allowRetryAfterAbsent(), throwsStateError);
      await c.verify();
      expect(c.confirmedAbsent, true);
      expect(await rows(), 0);
      await c.allowRetryAfterAbsent();
      expect(c.phase, HtmlCreationPhase.editing);
      expect(await rows(), 0);
      await c.save();
      expect(c.record.key, pending.key);
      expect(await rows(), 1);
      c.dispose();
    },
  );
  test(
    'a known missing result cannot be retried and ending its review tolerates cleanup failure',
    () async {
      final record = HtmlCreationRecord(
        key: newHtmlCreationKey(),
        memberId: 1,
        collection: 'note',
        edit: draft(),
        pending: true,
        createdId: 99,
      );
      await memory.vault().write(record);
      final c = controller(record: record);
      await c.verify();
      expect(c.failure, isA<HtmlCreationTargetUnavailable>());
      expect(c.confirmedAbsent, false);
      await expectLater(c.allowRetryAfterAbsent(), throwsStateError);
      memory.failRemove = true;
      await c.endUnavailable();
      expect(c.phase, HtmlCreationPhase.cleanup);
      expect(c.created, isNull);
      memory.failRemove = false;
      await c.retryCleanup();
      expect(c.phase, HtmlCreationPhase.finished);
      expect(await rows(), 0);
      expect(memory.values, isEmpty);
      c.dispose();
    },
  );
  test(
    'changed content after full review requires a fresh review and never overwrites the newer note',
    () async {
      final key = newHtmlCreationKey(),
          repo = LocalHtmlNotesRepository(store),
          input = draft();
      final created = (await repo.createOnce(input, creationKey: key)).note;
      final record = HtmlCreationRecord(
        key: key,
        memberId: 1,
        collection: 'note',
        edit: input,
        pending: true,
      );
      await memory.vault().write(record);
      final c = controller(record: record);
      await c.verify();
      c.markReviewed(c.observed!);
      final changed = (await repo.save(
        created,
        draft(title: 'Newer title', source: '<p>newer</p>'),
      )).note;
      await c.adoptObserved();
      expect(c.phase, HtmlCreationPhase.review);
      expect(c.reviewed, false);
      expect(c.failure, isA<HtmlNoteChanged>());
      expect(memory.values, isNotEmpty);
      expect(c.observed!.source, changed.source);
      c.markReviewed(c.observed!);
      await c.adoptObserved();
      expect(c.created!.source, changed.source);
      expect(c.receiptKnown, false);
      expect(await rows(), 1);
      c.dispose();
      repo.dispose();
    },
  );
  test('disposing while intent is pending starts no SQLite mutation', () async {
    final gate = Completer<void>();
    memory.holdWrite = gate.future;
    final c = controller();
    c.edit(draft());
    final saving = c.save();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    gate.complete();
    await saving;
    expect(await rows(), 0);
    expect((await memory.vault().read())!.pending, true);
  });
  test(
    'incomplete ordinary drafts preserve source and can be discarded without creating a note',
    () async {
      final c = controller();
      c.edit(draft(title: ''));
      expect(await c.flush(), true);
      expect((await memory.vault().read())!.edit.source, c.draft.source);
      expect((await memory.vault().read())!.pending, false);
      await c.save();
      expect(c.failure, isA<FormatException>());
      expect(await rows(), 0);
      expect(await c.discardDraft(), true);
      expect(memory.values, isEmpty);
      c.dispose();
    },
  );
}
