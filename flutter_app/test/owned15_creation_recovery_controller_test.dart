import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';

import 'package:bookstark_flutter/core/owned15_creation_journal.dart';
import 'package:bookstark_flutter/core/owned15_creation_recovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-creation-recovery-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late LocalDataPaths layout;
  late LocalGenerationPointer pointer;
  late NativeLocalDataControl control;
  OwnedWritableGeneration15? owner;
  final creators = <Owned15GenerationCreator>[];
  var reads = 0;
  int? failReadAt;
  Map<String, dynamic>? vector;
  final samples = <ComplexEditorKind, String>{
    ComplexEditorKind.markdown: '\ufeff# New 😀\r\n',
    ComplexEditorKind.html: '\ufeff<!doctype html>\r\n<h1>New</h1>\r\n',
    ComplexEditorKind.spreadsheet: SpreadsheetDocument.empty(
      workbookId: 'w',
      sheetId: 's',
    ).source,
    ComplexEditorKind.drawing: ' {"elements":[],"appState":{},"future":true} ',
    ComplexEditorKind.mindmap:
        '{"nodeData":{"id":"r","topic":"New","children":[]}}',
    ComplexEditorKind.richdoc:
        '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"New"}]}}',
    ComplexEditorKind.presentation:
        '{"width":1000,"height":562.5,"slides":[{"id":"s","elements":[]}]}',
  };
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  Future<OwnedWritableGeneration15> openOwner() =>
      OwnedWritableGeneration15.openActive(
        privateSupport: root,
        workspace: Directory('${root.path}/verification'),
        expectedPointer: pointer,
        isCurrentScope: () => true,
        factory: databaseFactoryFfiNoIsolate,
        control: control,
        crypto: NativeLocalContentCrypto(channel: channel),
      );
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-create-');
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 3,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    layout = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: root,
    );
    await File(layout.databasePath).parent.create(recursive: true);
    await layout.attachments.create();
    await layout.driveBlobs.create();
    await Directory('${root.path}/verification').create();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        singleInstance: false,
        onCreate: (db, _) => createLegacyCandidateSchema15(db),
      ),
    );
    try {
      await db.insert('notes', {
        'id': 9,
        'title': 'Historical BLOB',
        'content': Uint8List.fromList([255, 0, 239]),
        'labels': '[]',
        'updated_at': 1,
      });
      await db.insert('tasks', {
        'task_id': 8,
        'content': 'History',
        'due_date': '',
        'create_time': 'old',
        'modify_time': 'old',
        'complete_time': null,
      });
    } finally {
      await db.close();
    }
    reads = 0;
    failReadAt = null;
    vector = null;
    creators.clear();
    owner = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      if (call.method == 'protectNew' && vector != null) {
        final args = call.arguments as Map;
        expect(
          BoundedNoteTextReader.decodeUtf8PreservingBom(
            args['body'] as Uint8List,
          ),
          vector!['plain'],
        );
        return {
          'format': 1,
          'id': args['id'],
          'hash': vector!['hash'],
          'body': Uint8List.fromList(utf8.encode(vector!['body'] as String)),
        };
      }
      throw StateError('No undeclared crypto or password operation');
    });
    control = NativeLocalDataControl(
      invoke: (method, args) async {
        if (method != 'readState') {
          throw StateError('No native activation mutation');
        }
        reads++;
        if (reads == failReadAt) throw StateError('Lost fresh pointer receipt');
        return {
          'format': 1,
          'pointerRaw': pointer.encode(),
          'intentRaw': null,
          'currentRetentionRaw': null,
          'sourceRetentionRaw': null,
          'metadataOnly': true,
        };
      },
    );
    owner = await openOwner();
  });
  tearDown(() async {
    for (final creator in creators) {
      await creator.retire();
    }
    await owner?.retire();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Owned15GenerationCreator creator() {
    final result = Owned15GenerationCreator(
      owner!,
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
    creators.add(result);
    return result;
  }

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

  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? args]) =>
      owner!.exclusiveSnapshot((db) => db.rawQuery(sql, args));
  Future<Owned15PreparedCreation> prepare(
    Owned15GenerationCreator c, {
    String key = 'dddddddddddddddddddddddddddddddd',
    String collection = 'note',
    ComplexEditorKind kind = ComplexEditorKind.markdown,
    String? source,
    String? password,
  }) => c.prepare(
    creationKey: key,
    collection: collection,
    title: '\ufeffCreated $collection ${kind.name}',
    labels: ['first', 'second'],
    document: ComplexEditorDocument.parse(kind, source ?? samples[kind]!),
    password: password,
  );

  late Map<String, String> records;
  var failStorage = false;
  final controllers = <Owned15CreationRecoveryController>[];
  setUp(() {
    records = {};
    failStorage = false;
    controllers.clear();
  });
  tearDown(() async {
    for (final controller in controllers) {
      await controller.retire();
    }
  });
  Owned15CreationRecoveryController binding() {
    final journal = Owned15CreationJournal(
      owner: 'a' * 64,
      isCurrent: () => true,
      readValue: (key) async => records[key],
      writeValue: (key, value) async {
        records[key] = value;
      },
      deleteValue: (key) async {
        records.remove(key);
      },
      flush: () async {
        if (failStorage) throw StateError('Storage receipt lost');
      },
    );
    final result = Owned15CreationRecoveryController(
      creator: creator(),
      journal: journal,
      isCurrent: () => true,
    );
    controllers.add(result);
    return result;
  }

  test(
    'actual INSERT receipt fresh confirmation only removes opaque marker',
    () async {
      final c = binding(), input = await prepare(controllers.single.creator);
      final receipt = await c.submit(input);
      expect(receipt.id, greaterThan(9));
      final review = await c.inspect(), committed = await rows();
      expect(review.matching, true);
      expect(review.marker.knownId, receipt.id);
      await c.confirmSaved(review);
      expect(records, isEmpty);
      expect(await rows(), committed);
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        1,
      );
    },
  );
  test(
    'actual transactional failure keeps unknown, no receipt, explicit cancel cannot replay',
    () async {
      final c = binding(), input = await prepare(controllers.single.creator);
      await owner!.exclusiveSnapshot(
        (db) => db.execute(
          "CREATE TRIGGER fail_create BEFORE INSERT ON html_creation_receipts BEGIN SELECT RAISE(ABORT,'owned fixture'); END",
        ),
      );
      final before = await rows();
      await expectLater(
        c.submit(input),
        throwsA(isA<Owned15CreationSubmissionUncertain>()),
      );
      expect(await rows(), before);
      final review = await c.inspect();
      expect(review.noReceipt, true);
      expect(records.length, 1);
      await c.cancelUnsubmitted(review);
      expect(records, isEmpty);
      expect(await rows(), before);
      expect(() => c.submit(input), throwsStateError);
    },
  );
  test(
    'postcommit acknowledgement failure and cleanup failure retry only storage',
    () async {
      final c = binding(), input = await prepare(controllers.single.creator);
      var flushes = 0;
      // First flush is the durable unknown claim; second is known ack.
      // Use a separate journal binding to fail exactly after actual SQL commit.
      await c.retire();
      expect(() => input.document, throwsA(isA<GenerationContentFailure>()));
      final journal = Owned15CreationJournal(
        owner: 'a' * 64,
        isCurrent: () => true,
        readValue: (key) async => records[key],
        writeValue: (key, value) async {
          records[key] = value;
        },
        deleteValue: (key) async {
          records.remove(key);
        },
        flush: () async {
          flushes++;
          if (flushes == 2 || failStorage) {
            throw StateError('Owned storage failure');
          }
        },
      );
      final next = Owned15CreationRecoveryController(
        creator: creator(),
        journal: journal,
        isCurrent: () => true,
      );
      controllers.add(next);
      final prepared = await prepare(next.creator);
      await expectLater(next.submit(prepared), throwsStateError);
      final review = await next.inspect(), committed = await rows();
      expect(review.matching, true);
      failStorage = true;
      await expectLater(next.confirmSaved(review), throwsStateError);
      expect(records, isEmpty);
      expect(await rows(), committed);
      failStorage = false;
      await next.confirmSaved(review);
      expect(records, isEmpty);
      expect(await rows(), committed);
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        1,
      );
    },
  );
  test(
    'fresh tuple change rejects previous confirmation and retains record',
    () async {
      final c = binding(), input = await prepare(controllers.single.creator);
      final receipt = await c.submit(input), review = await c.inspect();
      await owner!.exclusiveSnapshot(
        (db) => db.rawUpdate('UPDATE notes SET title=? WHERE id=?', [
          'Actual changed',
          receipt.id,
        ]),
      );
      final changed = await rows();
      await expectLater(c.confirmSaved(review), throwsStateError);
      expect(records.length, 1);
      expect(await rows(), changed);
      expect((await c.inspect()).matching, false);
    },
  );
}
