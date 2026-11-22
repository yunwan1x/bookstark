import 'dart:async';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pending journal commit completes before repository save begins',
    () async {
      final f = _fixture();
      addTearDown(f.controller.dispose);
      final entered = Completer<void>();
      final finish = Completer<void>();
      f.bytes.writeEntered = entered;
      f.bytes.finishWrite = finish;
      f.repository.onSaveStart = () {
        expect(f.bytes.onlyRecord.pending, isTrue);
      };

      final saving = f.controller.save(f.draft);
      await entered.future;
      expect(f.repository.saveCount, 0);
      expect(f.events, ['vault.write.begin']);

      finish.complete();
      final result = await saving;
      expect(result, isNotNull);
      expect(
        f.events.indexOf('vault.write.commit'),
        lessThan(f.events.indexOf('repo.save.begin')),
      );
      expect(f.bytes.records, isEmpty);
      expect(f.controller.phase, ComplexSavePhase.ready);
      expect(f.controller.draftDurable, isFalse);
      expect(f.bytes.removeCount, 1);
    },
  );

  test('journal failure prevents repository writes', () async {
    final f = _fixture()..bytes.failWrites = true;
    addTearDown(f.controller.dispose);

    final result = await f.controller.save(f.draft);
    expect(result, isNull);
    expect(f.repository.saveCount, 0);
    expect(f.events, ['vault.write.begin']);
    expect(f.controller.phase, ComplexSavePhase.draftFailed);
    expect(f.controller.draftDurable, isFalse);
  });

  test(
    'a busy checkpoint rejects concurrent checkpoint and save calls',
    () async {
      final f = _fixture();
      addTearDown(f.controller.dispose);
      final entered = Completer<void>();
      final finish = Completer<void>();
      f.bytes.writeEntered = entered;
      f.bytes.finishWrite = finish;

      final first = f.controller.checkpoint(f.draft);
      await entered.future;
      await expectLater(f.controller.checkpoint(f.draft), throwsStateError);
      await expectLater(f.controller.save(f.draft), throwsStateError);
      expect(f.repository.saveCount, 0);

      finish.complete();
      await first;
      expect(f.controller.phase, ComplexSavePhase.ready);
      expect(f.bytes.onlyRecord.pending, isFalse);
    },
  );

  test(
    'matching commit receipt removes pending journal and returns ready',
    () async {
      final f = _fixture();
      addTearDown(f.controller.dispose);

      final saved = await f.controller.save(f.draft);
      expect(saved, isNotNull);
      expect(f.repository.saveCount, 1);
      expect(
        f.events.indexOf('vault.write.commit'),
        lessThan(f.events.indexOf('repo.save.begin')),
      );
      expect(
        f.events.indexOf('repo.save.commit'),
        lessThan(f.events.indexOf('vault.remove.begin')),
      );
      expect(f.bytes.records, isEmpty);
      expect(f.controller.baseline.same(saved!), isTrue);
      expect(f.controller.phase, ComplexSavePhase.ready);
      expect(f.controller.draftDurable, isFalse);
    },
  );

  test('confirmed save with failed cleanup retries storage only', () async {
    final f = _fixture()..bytes.removeFailures = 1;
    addTearDown(f.controller.dispose);

    final saved = await f.controller.save(f.draft);
    expect(saved, isNotNull);
    expect(f.repository.saveCount, 1);
    expect(f.controller.phase, ComplexSavePhase.committedCleanupFailed);
    expect(f.controller.draftDurable, isTrue);
    expect(f.bytes.onlyRecord.pending, isTrue);

    await f.controller.retryCleanup();
    expect(f.repository.saveCount, 1);
    expect(f.bytes.removeCount, 2);
    expect(f.bytes.records, isEmpty);
    expect(f.controller.phase, ComplexSavePhase.ready);
    expect(f.controller.draftDurable, isFalse);
  });

  test(
    'repository commit followed by lost result is unknown and never auto-resubmitted',
    () async {
      final f = _fixture()..repository.commitThenThrow = true;
      addTearDown(f.controller.dispose);

      expect(await f.controller.save(f.draft), isNull);
      expect(f.repository.saveCount, 1);
      expect(f.controller.phase, ComplexSavePhase.unknown);
      expect(f.bytes.onlyRecord.pending, isTrue);

      final observed = await f.controller.observe();
      expect(observed.same(f.repository.current), isTrue);
      expect(f.repository.saveCount, 1);
      await expectLater(f.controller.checkpoint(f.draft), throwsStateError);
      await expectLater(f.controller.save(f.draft), throwsStateError);
      await expectLater(f.controller.discard(), throwsStateError);
      expect(f.repository.saveCount, 1);
      expect(f.bytes.removeCount, 0);
    },
  );

  test(
    'review adoption requires exact reviewed state and a fresh unchanged read',
    () async {
      final f = _fixture(recoveredPending: true);
      addTearDown(f.controller.dispose);

      final reviewed = await f.controller.observe();
      final alteredReview = _note(
        scope: reviewed.scope,
        id: reviewed.id,
        collection: reviewed.collection,
        kind: reviewed.document.kind,
        version: reviewed.version,
        title: 'forged review',
        source: reviewed.document.source,
      );
      await expectLater(
        f.controller.adoptReviewed(alteredReview, keepDraft: false),
        throwsStateError,
      );
      expect(f.repository.readCount, 1);

      f.repository.current = _note(
        scope: reviewed.scope,
        id: reviewed.id,
        collection: reviewed.collection,
        kind: reviewed.document.kind,
        version: reviewed.version + 1,
        title: 'changed after review',
        source: '<p>newer data</p>',
      );
      await expectLater(
        f.controller.adoptReviewed(reviewed, keepDraft: false),
        throwsA(isA<ComplexNoteConflict>()),
      );
      expect(f.repository.readCount, 2);
      expect(f.repository.saveCount, 0);
      expect(f.controller.phase, ComplexSavePhase.conflict);
      expect(f.controller.observed, same(f.repository.current));
      expect(f.bytes.removeCount, 0);
    },
  );

  test(
    'keeping a reviewed draft writes nonpending recovery without saving',
    () async {
      final f = _fixture(recoveredPending: true);
      addTearDown(f.controller.dispose);

      final reviewed = await f.controller.observe();
      await f.controller.adoptReviewed(reviewed, keepDraft: true);

      expect(f.repository.readCount, 2);
      expect(f.repository.saveCount, 0);
      expect(f.controller.phase, ComplexSavePhase.ready);
      expect(f.controller.draftDurable, isTrue);
      expect(f.bytes.onlyRecord.pending, isFalse);
      expect(f.bytes.onlyRecord.edit.matches(reviewed), isFalse);
    },
  );

  test(
    'disposing during pending journal write prevents repository entry',
    () async {
      final f = _fixture();
      final entered = Completer<void>();
      final finish = Completer<void>();
      f.bytes.writeEntered = entered;
      f.bytes.finishWrite = finish;

      final saving = f.controller.save(f.draft);
      await entered.future;
      f.controller.dispose();
      finish.complete();
      expect(await saving, isNull);

      expect(f.repository.saveCount, 0);
      expect(f.controller.phase, ComplexSavePhase.closed);
      expect(f.bytes.onlyRecord.pending, isTrue);
    },
  );

  test(
    'disposing during in-flight repository commit leaves pending recovery for reconciliation',
    () async {
      final f = _fixture();
      final entered = Completer<void>();
      final finish = Completer<void>();
      f.repository.saveEntered = entered;
      f.repository.finishSave = finish;

      final saving = f.controller.save(f.draft);
      await entered.future;
      expect(f.bytes.onlyRecord.pending, isTrue);
      f.controller.dispose();
      finish.complete();
      expect(await saving, isNull);

      expect(f.repository.saveCount, 1);
      expect(f.repository.current.document.source, f.draft.document.source);
      expect(f.bytes.removeCount, 0);
      expect(f.bytes.onlyRecord.pending, isTrue);
      expect(f.controller.phase, ComplexSavePhase.closed);
    },
  );

  test(
    'checkpoint and save reject wrong document kind, and constructor binds repository and vault identity',
    () async {
      final f = _fixture();
      addTearDown(f.controller.dispose);
      final wrongKind = ComplexNoteEdit(
        title: f.draft.title,
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          '{"elements":[]}',
        ),
        labels: f.draft.labels,
      );
      await expectLater(f.controller.checkpoint(wrongKind), throwsStateError);
      await expectLater(f.controller.save(wrongKind), throwsStateError);
      expect(f.bytes.records, isEmpty);
      expect(f.repository.saveCount, 0);

      final mismatchedVault = ComplexRecoveryVault(
        scope: f.repository.scope,
        collection: f.repository.collection,
        kind: ComplexEditorKind.drawing,
        store: _MemoryRecoveryBytesStore(<String>[]),
      );
      expect(
        () => LocalComplexEditorController(
          repository: f.repository,
          vault: mismatchedVault,
          baseline: f.baseline,
        ),
        throwsStateError,
      );
    },
  );
}

_ControllerFixture _fixture({bool recoveredPending = false}) {
  final baseline = _note(
    scope: 'a' * 64,
    id: 41,
    collection: 'note',
    kind: ComplexEditorKind.html,
    version: 100,
    title: 'Original title',
    source: '<!doctype html><p>before</p>',
  );
  final draft = ComplexNoteEdit(
    title: 'Edited title',
    document: ComplexEditorDocument.parse(
      ComplexEditorKind.html,
      '<!doctype html><p>after😀</p>',
    ),
    labels: const ['changed'],
  );
  final events = <String>[];
  final bytes = _MemoryRecoveryBytesStore(events);
  final repository = _FakeComplexNotesRepository(baseline, events);
  final vault = ComplexRecoveryVault(
    scope: repository.scope,
    collection: repository.collection,
    kind: repository.kind,
    store: bytes,
  );
  final recovery = recoveredPending
      ? ComplexRecoveryRecord.capture(baseline, draft, pending: true)
      : null;
  final controller = LocalComplexEditorController(
    repository: repository,
    vault: vault,
    baseline: baseline,
    recovery: recovery,
  );
  return _ControllerFixture(
    baseline: baseline,
    draft: draft,
    events: events,
    bytes: bytes,
    repository: repository,
    vault: vault,
    controller: controller,
  );
}

ComplexNote _note({
  required String scope,
  required int id,
  required String collection,
  required ComplexEditorKind kind,
  required int version,
  required String title,
  required String source,
}) => ComplexNote(
  scope: scope,
  id: id,
  collection: collection,
  title: title,
  document: ComplexEditorDocument.parse(kind, source),
  version: version,
  labels: const ['baseline'],
);

class _ControllerFixture {
  _ControllerFixture({
    required this.baseline,
    required this.draft,
    required this.events,
    required this.bytes,
    required this.repository,
    required this.vault,
    required this.controller,
  });
  final ComplexNote baseline;
  final ComplexNoteEdit draft;
  final List<String> events;
  final _MemoryRecoveryBytesStore bytes;
  final _FakeComplexNotesRepository repository;
  final ComplexRecoveryVault vault;
  final LocalComplexEditorController controller;
}

class _FakeComplexNotesRepository implements ComplexNotesRepository {
  _FakeComplexNotesRepository(this.current, this.events);
  ComplexNote current;
  final List<String> events;
  int saveCount = 0, readCount = 0;
  bool commitThenThrow = false, disposed = false;
  void Function()? onSaveStart;
  Completer<void>? saveEntered, finishSave;

  @override
  String get scope => current.scope;
  @override
  String get collection => current.collection;
  @override
  ComplexEditorKind get kind => current.document.kind;
  @override
  void dispose() {
    disposed = true;
  }

  @override
  Future<ComplexNote> read(int id) async {
    events.add('repo.read');
    readCount++;
    if (id != current.id) throw StateError('wrong row');
    return current;
  }

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    events.add('repo.save.begin');
    saveCount++;
    onSaveStart?.call();
    if (baseline.id != current.id) throw StateError('wrong baseline');
    saveEntered?.complete();
    await finishSave?.future;
    final committed = ComplexNote(
      scope: current.scope,
      id: current.id,
      collection: current.collection,
      title: edit.title,
      document: edit.document,
      version: current.version + 1,
      labels: edit.labels,
    );
    current = committed;
    events.add('repo.save.commit');
    if (commitThenThrow) throw StateError('commit applied but response lost');
    return committed;
  }
}

class _MemoryRecoveryBytesStore implements ComplexRecoveryBytesStore {
  _MemoryRecoveryBytesStore(this.events);
  final List<String> events;
  final records = <String, Uint8List>{};
  int removeCount = 0;
  int removeFailures = 0;
  bool failWrites = false;
  Completer<void>? writeEntered, finishWrite;
  ComplexRecoveryRecord get onlyRecord {
    if (records.length != 1) throw StateError('expected one recovery record');
    return ComplexRecoveryRecord.decode(records.values.single);
  }

  @override
  Future<Uint8List?> read(String key) async {
    return records[key] == null ? null : Uint8List.fromList(records[key]!);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    events.add('vault.write.begin');
    writeEntered?.complete();
    await finishWrite?.future;
    if (failWrites) throw StateError('recovery write failed');
    records[key] = Uint8List.fromList(bytes);
    events.add('vault.write.commit');
  }

  @override
  Future<void> remove(String key) async {
    events.add('vault.remove.begin');
    removeCount++;
    if (removeFailures > 0) {
      removeFailures--;
      throw StateError('recovery cleanup failed');
    }
    records.remove(key);
    events.add('vault.remove.commit');
  }
}
