import 'dart:async';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-creation-unit');
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

  test(
    'all seven kinds and both collections INSERT exact source plus one atomic receipt without changing historical data',
    () async {
      final before = await rows();
      final old = await query(
        'SELECT typeof(content) AS type,hex(content) AS bytes FROM notes WHERE id=9',
      );
      var index = 0;
      for (final collection in ['note', 'article']) {
        for (final kind in ComplexEditorKind.values) {
          final c = creator();
          final input = await prepare(
            c,
            key: (++index).toRadixString(16).padLeft(32, '0'),
            collection: collection,
            kind: kind,
          );
          final receipt = await c.submit(
            input,
            beforeInsert: (hash) async {
              expect(hash, input.inputHash);
            },
          );
          final observation = await c.inspect(receipt.creationKey);
          expect(observation!.state, Owned15CreationResourceState.matching);
          expect(observation.kind, kind);
          expect(observation.receipt.id, receipt.id);
          final opened = await owner!.content.open(
            receipt.id,
            collection: collection,
          );
          try {
            expect(opened.source, samples[kind]);
            expect(
              opened.metadata.title,
              '\ufeffCreated $collection ${kind.name}',
            );
            expect(opened.metadata.labels, ['first', 'second']);
          } finally {
            opened.close();
          }
          await c.retire();
        }
      }
      final after = await rows();
      for (final name in before.keys.where(
        (name) => !{
          'notes',
          'html_creation_receipts',
          'sqlite_sequence',
        }.contains(name),
      )) {
        expect(after[name], before[name], reason: 'Unrelated table $name');
      }
      expect(
        await query(
          'SELECT typeof(content) AS type,hex(content) AS bytes FROM notes WHERE id=9',
        ),
        old,
      );
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        14,
      );
      expect(
        (await query(
          'SELECT user_version FROM pragma_user_version',
        )).single['user_version'],
        15,
      );
    },
  );

  test(
    'durable claim failure performs zero SQL and cannot reuse consumed prepared input',
    () async {
      final c = creator(), before = await rows();
      final input = await prepare(c);
      await expectLater(
        c.submit(
          input,
          beforeInsert: (_) async {
            expect(await rows(), before);
            throw StateError('Storage flush failed');
          },
        ),
        throwsA(isA<Owned15CreationSubmissionUncertain>()),
      );
      expect(await rows(), before);
      await expectLater(
        c.submit(input, beforeInsert: (_) async {}),
        throwsA(isA<Owned15CreationAlreadySubmitted>()),
      );
      expect(await rows(), before);
    },
  );
  test(
    'receipt INSERT failure rolls back note and every sequence exactly',
    () async {
      final c = creator();
      await owner!.exclusiveSnapshot(
        (db) => db.execute(
          "CREATE TRIGGER reject_creation_receipt BEFORE INSERT ON html_creation_receipts "
          "BEGIN SELECT RAISE(FAIL,'fixture failure'); END",
        ),
      );
      final before = await rows(), input = await prepare(c);
      await expectLater(
        c.submit(input, beforeInsert: (_) async {}),
        throwsA(isA<Owned15CreationSubmissionUncertain>()),
      );
      expect(await rows(), before);
      expect(await c.inspect(input.creationKey), isNull);
    },
  );
  test(
    'two controllers with same operation can cause at most one actual INSERT',
    () async {
      final first = creator(), second = creator();
      final a = await prepare(first), b = await prepare(second);
      final results = await Future.wait<Object>([
        first
            .submit(a, beforeInsert: (_) async {})
            .then<Object>((value) => value, onError: (Object error) => error),
        second
            .submit(b, beforeInsert: (_) async {})
            .then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(results.whereType<Owned15CreationReceipt>().length, 1);
      expect(results.whereType<Owned15CreationAlreadySubmitted>().length, 1);
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        1,
      );
      expect(
        (await query('SELECT COUNT(*) AS n FROM notes WHERE id>9')).single['n'],
        1,
      );
    },
  );
  test(
    'existing historical HTML receipt key is never overwritten or reused for another format',
    () async {
      const key = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      await owner!.exclusiveSnapshot((db) async {
        await db.insert('notes', {
          'id': 20,
          'title': 'Original HTML',
          'content': '<p>Original</p>',
          'labels': '[]',
          'updated_at': 1,
          'editor_type': 'html',
        });
        await db.insert('html_creation_receipts', {
          'creation_key': key,
          'note_id': 20,
          'collection': 'note',
          'input_hash': 'f' * 64,
          'created_at': 1,
        });
      });
      final before = await rows(), c = creator();
      final input = await prepare(c, key: key, kind: ComplexEditorKind.drawing);
      await expectLater(
        c.submit(input, beforeInsert: (_) async {}),
        throwsA(isA<Owned15CreationAlreadySubmitted>()),
      );
      expect(await rows(), before);
    },
  );
  test(
    'retirement cancels before SQL but joins the real held durable callback',
    () async {
      final c = creator(), input = await prepare(c), before = await rows();
      final entered = Completer<void>(), release = Completer<void>();
      final submitting = c.submit(
        input,
        beforeInsert: (_) async {
          entered.complete();
          await release.future;
        },
      );
      final failure = expectLater(
        submitting,
        throwsA(isA<GenerationContentFailure>()),
      );
      await entered.future;
      var drained = false;
      final closing = c.retire().then((_) {
        drained = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      release.complete();
      await failure;
      await closing;
      expect(await rows(), before);
    },
  );
  test(
    'postcommit pointer receipt loss reopens by actual SQL receipt with no replay or UPDATE',
    () async {
      final c = creator(), input = await prepare(c);
      failReadAt =
          reads + 2; // beforeSQL fresh succeeds, postcommit fresh fails
      Owned15CreationSubmissionUncertain? uncertain;
      try {
        await c.submit(input, beforeInsert: (_) async {});
      } on Owned15CreationSubmissionUncertain catch (error) {
        uncertain = error;
      }
      expect(uncertain?.knownReceipt, isNotNull);
      final committed = await rows();
      failReadAt = null;
      await c.retire();
      await owner!.retire();
      owner = await openOwner();
      final reopened = creator();
      final actual = await reopened.inspect(input.creationKey);
      expect(actual!.state, Owned15CreationResourceState.matching);
      expect(actual.receipt.id, uncertain!.knownReceipt!.id);
      expect(await rows(), committed);
    },
  );
  test(
    'fresh receipt review reports changed, deleted and missing without mutating receipt',
    () async {
      final c = creator(), input = await prepare(c);
      final receipt = await c.submit(input, beforeInsert: (_) async {});
      await owner!.exclusiveSnapshot(
        (db) => db.rawUpdate('UPDATE notes SET title=? WHERE id=?', [
          'Changed',
          receipt.id,
        ]),
      );
      expect(
        (await c.inspect(input.creationKey))!.state,
        Owned15CreationResourceState.changed,
      );
      await owner!.exclusiveSnapshot(
        (db) =>
            db.rawUpdate('UPDATE notes SET deleted=1 WHERE id=?', [receipt.id]),
      );
      expect(
        (await c.inspect(input.creationKey))!.state,
        Owned15CreationResourceState.deleted,
      );
      await owner!.exclusiveSnapshot(
        (db) => db.delete('notes', where: 'id=?', whereArgs: [receipt.id]),
      );
      expect(
        (await c.inspect(input.creationKey))!.state,
        Owned15CreationResourceState.missing,
      );
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        1,
      );
    },
  );
  test(
    'new protected body uses actual Native protocol and stores only existing Go wire/hash, not password/plaintext',
    () async {
      vector =
          ((jsonDecode(
                            await File(
                              'tool/legacy_crypto_test/go-vectors.json',
                            ).readAsString(),
                          )
                          as List)
                      .first
                  as Map)
              .cast<String, dynamic>();
      final c = creator();
      final input = await prepare(
        c,
        source: vector!['plain'] as String,
        password: vector!['password'] as String,
      );
      final receipt = await c.submit(input, beforeInsert: (_) async {});
      final stored = await query(
        'SELECT hex(CAST(content AS BLOB)) AS body,password_hash FROM notes WHERE id=?',
        [receipt.id],
      );
      expect(
        stored.single['body'],
        utf8
            .encode(vector!['body'] as String)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase(),
      );
      expect(stored.single['password_hash'], vector!['hash']);
      expect(
        (await c.inspect(input.creationKey))!.state,
        Owned15CreationResourceState.matching,
      );
      // This is transport protocol evidence; real Native crypto is separately required.
    },
  );
  test(
    'concurrent preparation owns slot before pointer or crypto await',
    () async {
      final c = creator();
      final first = prepare(c);
      expect(
        () => prepare(c, key: 'e' * 32),
        throwsA(isA<GenerationContentFailure>()),
      );
      final input = await first;
      input.dispose();
      final next = await prepare(c, key: 'e' * 32);
      next.dispose();
      expect(
        (await query(
          'SELECT COUNT(*) AS n FROM html_creation_receipts',
        )).single['n'],
        0,
      );
    },
  );
  test(
    'existing receipt target rejects oversized metadata without SQL changes',
    () async {
      final c = creator(), input = await prepare(c);
      final receipt = await c.submit(input, beforeInsert: (_) async {});
      final committed = await rows();
      for (final column in [
        'title',
        'labels',
        'password_hash',
        'create_time',
        'collection',
        'editor_type',
      ]) {
        final original = (await query(
          'SELECT CAST($column AS BLOB) AS v FROM notes WHERE id=?',
          [receipt.id],
        )).single['v'];
        await owner!.exclusiveSnapshot(
          (db) => db.rawUpdate('UPDATE notes SET $column=? WHERE id=?', [
            'x' * 70000,
            receipt.id,
          ]),
        );
        final before = await rows();
        await expectLater(
          c.inspect(input.creationKey),
          throwsA(isA<FormatException>()),
        );
        expect(await rows(), before);
        await owner!.exclusiveSnapshot(
          (db) => db.rawUpdate(
            'UPDATE notes SET $column=CAST(? AS TEXT) WHERE id=?',
            [original, receipt.id],
          ),
        );
      }
      expect(await rows(), committed);
      expect(
        (await c.inspect(input.creationKey))!.state,
        Owned15CreationResourceState.matching,
      );
    },
  );
}
