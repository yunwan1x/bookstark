import 'dart:convert';
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned15_complex_repository.dart';
import 'package:bookstark_flutter/core/owned15_save_journal.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';
import 'package:bookstark_flutter/core/protected_complex_memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-adapter-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late LocalDataPaths layout;
  late OwnedWritableGeneration15 owner;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  final values = <String, String>{};
  bool failFlush = false,
      failKnown = false,
      retargetOnClaim = false,
      holdNextRead = false;
  Completer<void>? readEntered, releaseRead;
  Owned15SaveJournal? journal;
  Owned15ComplexRepository? repository;
  ProtectedComplexMemoryStore? memory;
  LocalComplexEditorController? editor;
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-adapter-');
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 7,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    pointerRaw = pointer.encode();
    values.clear();
    failFlush = false;
    failKnown = false;
    retargetOnClaim = false;
    journal = null;
    repository = null;
    memory = null;
    editor = null;
    holdNextRead = false;
    readEntered = null;
    releaseRead = null;
    layout = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: root,
    );
    await File(layout.databasePath).parent.create(recursive: true);
    await layout.attachments.create();
    await layout.driveBlobs.create();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        singleInstance: false,
        onCreate: (db, _) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.insert('notes', {
      'id': 9,
      'title': 'Original',
      'content': '\ufeff# Original\r\n',
      'labels': '["original"]',
      'updated_at': 11,
      'collection': 'article',
      'editor_type': 'markdown',
      'visibility': 3,
      'is_pinned': 1,
      'pin_order': -2,
      'legacy_version': 9223372036854775807,
    });
    await db.close();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('Unprotected adapter must not transform source');
    });
    owner = await OwnedWritableGeneration15.openActive(
      privateSupport: root,
      workspace: await Directory('${root.path}/verify').create(),
      expectedPointer: pointer,
      isCurrentScope: () => true,
      factory: databaseFactoryFfiNoIsolate,
      crypto: NativeLocalContentCrypto(channel: channel),
      control: NativeLocalDataControl(
        invoke: (name, args) async {
          if (name != 'readState') {
            throw StateError('No native mutation for existing-ID save');
          }
          if (holdNextRead) {
            holdNextRead = false;
            readEntered!.complete();
            await releaseRead!.future;
          }
          return {
            'format': 1,
            'pointerRaw': pointerRaw,
            'intentRaw': null,
            'currentRetentionRaw': null,
            'sourceRetentionRaw': null,
            'metadataOnly': true,
          };
        },
      ),
    );
  });
  tearDown(() async {
    editor?.dispose();
    memory?.close();
    repository?.dispose();
    await repository?.drain();
    await journal?.drain();
    journal?.retire();
    await owner.retire();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<Map<String, String>> rows() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      return await OwnedGeneration15SchemaGate().rowDigests(db);
    } finally {
      await db.close();
    }
  }

  Future<void> openEditor({int journalID = 9}) async {
    journal = Owned15SaveJournal(
      draftNamespace: layout.draftNamespace,
      collection: 'article',
      resourceId: journalID,
      isCurrent: () => owner.current,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
        final state = (jsonDecode(value) as Map)['state'];
        if (state == 'known' && failKnown) failFlush = true;
        if (state == 'unknown' && retargetOnClaim) {
          pointerRaw = LocalGenerationPointer(
            generation: pointer.generation,
            epoch: 8,
            activationId: 'd' * 32,
            sourceSHA256: 'c' * 64,
          ).encode();
        }
      },
      deleteValue: (key) async {
        values.remove(key);
      },
      flush: () async {
        if (failFlush) throw StateError('Storage barrier failed');
      },
    );
    repository = await Owned15ComplexRepository.open(
      owner: owner,
      journal: journal!,
      collection: 'article',
      resourceId: 9,
      isCurrentScope: () => owner.current,
      cancellation: AttachmentCancellation(),
    );
    memory = ProtectedComplexMemoryStore(journal!);
    editor = LocalComplexEditorController(
      repository: repository!,
      vault: ComplexRecoveryVault(
        scope: repository!.scope,
        collection: 'article',
        kind: ComplexEditorKind.markdown,
        store: memory!,
      ),
      baseline: repository!.baseline,
      ephemeralDrafts: true,
      beforeAdoptReviewed: repository!.endWarmReview,
    );
  }

  ComplexNoteEdit edit() => ComplexNoteEdit(
    title: 'Original',
    labels: ['original'],
    document: ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      '\ufeff# Changed\r\n',
    ),
  );

  test(
    'actual existing-ID SQL CAS preserves metadata and cleanup retry never UPDATEs again',
    () async {
      await openEditor();
      failKnown = true;
      final result = await editor!.save(edit());
      expect(result, isNotNull);
      expect(editor!.phase, ComplexSavePhase.committedCleanupFailed);
      final committed = await rows();
      expect(values.values.join(), isNot(contains('# Changed')));
      expect(values.values.join(), isNot(contains('# Original')));
      failFlush = false;
      failKnown = false;
      await editor!.retryCleanup();
      expect(editor!.phase, ComplexSavePhase.ready);
      expect(
        await rows(),
        committed,
        reason: 'Storage-only cleanup must not touch any SQL row or sequence',
      );
      expect(values, isEmpty);
      final actual = await repository!.read(9);
      expect(actual.document.source, '\ufeff# Changed\r\n');
    },
  );
  test('failed durable marker barrier performs zero SQL mutation', () async {
    await openEditor();
    final before = await rows();
    failFlush = true;
    expect(await editor!.save(edit()), isNull);
    expect(editor!.phase, ComplexSavePhase.unknown);
    expect(await rows(), before);
  });
  test(
    'native epoch changes after durable marker claim block UPDATE and retain unknown',
    () async {
      await openEditor();
      final before = await rows();
      retargetOnClaim = true;
      expect(await editor!.save(edit()), isNull);
      expect(owner.current, isFalse);
      expect(editor!.phase, ComplexSavePhase.unknown);
      expect(await rows(), before);
      expect(values, isNotEmpty);
    },
  );
  test(
    'external fulltuple change requires fresh readonly review and never overwrites',
    () async {
      await openEditor();
      await owner.exclusiveSnapshot(
        (db) => db.rawUpdate(
          'UPDATE notes SET content=?,updated_at=? WHERE id=9',
          ['External change', 42],
        ),
      );
      final external = await rows();
      expect(await editor!.save(edit()), isNull);
      expect(editor!.requiresReview, isTrue);
      expect(await rows(), external);
      final actual = await editor!.observe();
      expect(actual.document.source, 'External change');
      await editor!.adoptReviewed(actual, keepDraft: false);
      expect(values, isEmpty);
      expect(await rows(), external);
    },
  );
  test(
    'dispose during actual pre-SQL native pointer await cancels UPDATE and drain joins it',
    () async {
      await openEditor();
      final before = await rows();
      readEntered = Completer<void>();
      releaseRead = Completer<void>();
      holdNextRead = true;
      final saving = editor!.save(edit());
      await readEntered!.future;
      repository!.dispose();
      var drained = false;
      final closing = repository!.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      releaseRead!.complete();
      expect(await saving, isNull);
      await closing;
      expect(drained, isTrue);
      expect(await rows(), before);
      expect(values, isNotEmpty);
    },
  );
  test(
    'another resource journal cannot authorize reading or saving this resource',
    () async {
      await expectLater(openEditor(journalID: 10), throwsStateError);
      expect(values, isEmpty);
    },
  );
}
