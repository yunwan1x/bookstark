import 'dart:convert';
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';

class CountFactory implements DatabaseFactory {
  CountFactory(this.actual);
  final String actual;
  int writes = 0;
  String? expectedLocale;
  @override
  Future<Database> openDatabase(
    String p, {
    OpenDatabaseOptions? options,
  }) async {
    if (p == actual && options?.readOnly != true) writes++;
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      p,
      options: options,
    );
    if (p.contains('/owned15-template-') && expectedLocale != null) {
      await db.execute('CREATE TABLE android_metadata (locale TEXT)');
      await db.insert('android_metadata', {'locale': expectedLocale});
    }
    return db;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-capability-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root, work;
  late LocalDataPaths generation;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  late CountFactory factory;
  late NativeLocalDataControl control;
  bool current = true;
  String? intentRaw, sourceRetentionRaw;
  Future<Object?> Function(MethodCall)? cryptoHandler;
  Future<Database> raw() => databaseFactoryFfiNoIsolate.openDatabase(
    generation.databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  Future<OwnedWritableGeneration15> owner() =>
      OwnedWritableGeneration15.openActive(
        privateSupport: root,
        workspace: work,
        expectedPointer: pointer,
        isCurrentScope: () => current,
        control: control,
        factory: factory,
        crypto: NativeLocalContentCrypto(channel: channel),
      );
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
    root = await parent.createTemp('owned15-');
    work = await Directory('${root.path}/verify').create();
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 7,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    pointerRaw = pointer.encode();
    intentRaw = null;
    sourceRetentionRaw = null;
    current = true;
    generation = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: root,
    );
    await File(generation.databasePath).parent.create(recursive: true);
    await generation.attachments.create();
    await generation.driveBlobs.create();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      generation.databasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 15,
        onCreate: (db, _) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.insert('notes', {
      'id': 9,
      'title': 'Original',
      'content': '\ufeff# Original\r\n',
      'labels': '["unchanged"]',
      'updated_at': 123,
      'collection': 'article',
      'editor_type': 'markdown',
      'is_pinned': 1,
      'pin_order': 8,
      'visibility': 3,
      'legacy_version': 9223372036854775807,
    });
    await db.insert('tasks', {
      'task_id': 15,
      'content': 'Retain NULL',
      'due_date': '',
      'create_time': 'x',
      'modify_time': 'x',
      'complete_time': null,
    });
    await db.close();
    factory = CountFactory(generation.databasePath);
    control = NativeLocalDataControl(
      invoke: (name, args) async {
        if (name != 'readState') {
          throw StateError('Factory must not mutate control');
        }
        return {
          'format': 1,
          'pointerRaw': pointerRaw,
          'intentRaw': intentRaw,
          'currentRetentionRaw': null,
          'sourceRetentionRaw': sourceRetentionRaw,
          'metadataOnly': true,
        };
      },
    );
    cryptoHandler = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (cryptoHandler != null) return cryptoHandler!(call);
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('Unexpected crypto operation');
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  test(
    'fresh owned15 opens without row NULL metadata sequence or source changes',
    () async {
      final db = await raw(), gate = OwnedGeneration15SchemaGate();
      final before = await gate.rowDigests(db);
      await db.close();
      final live = await owner();
      try {
        final handle = await live.content.open(9, collection: 'article');
        expect(handle.source, '\ufeff# Original\r\n');
        expect(handle.metadata.isPinned, isTrue);
        expect(handle.metadata.visibility, 3);
        expect(factory.writes, 1);
      } finally {
        await live.retire();
      }
      final after = await raw();
      expect(await gate.rowDigests(after), before);
      expect((await after.query('tasks')).single['complete_time'], isNull);
      await after.close();
    },
  );
  test(
    'fresh native epoch after handle open blocks SQL write and seals old owner',
    () async {
      final live = await owner();
      final handle = await live.content.open(9, collection: 'article');
      pointerRaw = LocalGenerationPointer(
        generation: pointer.generation,
        epoch: 8,
        activationId: 'd' * 32,
        sourceSHA256: 'c' * 64,
      ).encode();
      try {
        await expectLater(
          live.content.save(
            handle,
            title: 'Changed',
            source: 'Changed',
            labels: [],
          ),
          throwsA(isA<GenerationContentFailure>()),
        );
        expect(live.current, isFalse);
        expect(handle.isCurrent, isFalse);
      } finally {
        await live.retire();
      }
      final db = await raw();
      expect((await db.query('notes')).single['revision'], 1);
      final exact = (await db.rawQuery(
        'SELECT CAST(content AS BLOB) AS exact FROM notes',
      )).single['exact'];
      expect(exact, utf8.encode('\ufeff# Original\r\n'));
      await db.close();
    },
  );
  test('pending activation cannot open writable capability', () async {
    final old = LocalGenerationPointer(
      generation: '1' * 32,
      epoch: 6,
      activationId: '2' * 32,
      sourceSHA256: '3' * 64,
    );
    final intent = LocalRestoreIntent(
      operationId: pointer.activationId,
      sourcePointerRaw: old.encode(),
      retainedId: 'e' * 32,
      retainedManifestSHA256: 'f' * 64,
      targetPointerRaw: pointer.encode(),
    );
    intentRaw = intent.encode();
    sourceRetentionRaw = LocalRetention(
      id: 'e' * 32,
      sourcePointerSHA256: localPointerSHA256(old.encode()),
      sourceGeneration: old.generation,
      manifestSHA256: 'f' * 64,
    ).encode();
    await expectLater(owner(), throwsA(anything));
    expect(factory.writes, 0);
  });
  for (final version in [14, 16]) {
    test(
      'active schema $version is refused with zero RW opens and exact bytes',
      () async {
        await File(generation.databasePath).delete();
        final db = await databaseFactoryFfiNoIsolate.openDatabase(
          generation.databasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: version,
            onCreate: (db, _) => version == 14
                ? createLocalSchema14(db)
                : createLocalSchema16(db),
          ),
        );
        await db.close();
        final before = await File(generation.databasePath).readAsBytes();
        await expectLater(owner(), throwsA(anything));
        expect(factory.writes, 0);
        expect(await File(generation.databasePath).readAsBytes(), before);
      },
    );
  }
  test(
    'directory symlink refuses before RW and never touches target',
    () async {
      final folder = File(generation.databasePath).parent;
      final moved = '${folder.path}-original';
      await folder.rename(moved);
      await Link(folder.path).create(moved);
      final before = await File('$moved/content.db').readAsBytes();
      await expectLater(owner(), throwsA(anything));
      expect(factory.writes, 0);
      expect(await File('$moved/content.db').readAsBytes(), before);
    },
  );
  test(
    'Android metadata mismatch fails read-only before RW; no locale rewrite',
    () async {
      final db = await raw();
      await db.execute('CREATE TABLE android_metadata (locale TEXT)');
      await db.insert('android_metadata', {'locale': 'old_LOCALE'});
      await db.close();
      factory.expectedLocale = 'new_LOCALE';
      final before = await File(generation.databasePath).readAsBytes();
      await expectLater(owner(), throwsA(anything));
      expect(factory.writes, 0);
      expect(await File(generation.databasePath).readAsBytes(), before);
    },
  );
  test(
    'retirement waits real native drain after fast crypto cancellation',
    () async {
      final db = await raw();
      await db.update('notes', {
        'password_hash': r'$2a$04$' + ('A' * 53),
        'content':
            'ENC:v1:AAAAAAAAAAAAAAAAAAAAAA==:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA==',
      });
      await db.close();
      final started = Completer<void>(), workerDone = Completer<void>();
      final response = Completer<Object?>();
      cryptoHandler = (call) async {
        if (call.method == 'unlock') {
          started.complete();
          return response.future;
        }
        if (call.method == 'cancel') {
          if (!response.isCompleted) {
            response.completeError(PlatformException(code: 'CANCELLED'));
          }
          return {
            'format': 1,
            'id': (call.arguments as Map)['id'],
            'cancelled': true,
          };
        }
        if (call.method == 'drain') {
          await workerDone.future;
          return {'format': 1, 'drained': true};
        }
        throw StateError('Unexpected crypto request');
      };
      final live = await owner();
      final opening = live.content.open(
        9,
        collection: 'article',
        password: 'fixture',
      );
      final rejected = expectLater(opening, throwsA(anything));
      await started.future;
      var closed = false;
      final closing = live.retire().then((_) {
        closed = true;
      });
      await rejected;
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      expect(live.current, isFalse);
      workerDone.complete();
      await closing;
      expect(closed, isTrue);
    },
  );
  test(
    'unconfirmed real crypto drain retains lease; explicit barrier retry only',
    () async {
      var drains = 0;
      cryptoHandler = (call) async {
        if (call.method != 'drain') throw StateError('unexpected crypto');
        drains++;
        if (drains == 1) throw PlatformException(code: 'UNAVAILABLE');
        return {'format': 1, 'drained': true};
      };
      final live = await owner();
      await expectLater(
        live.retire(),
        throwsA(isA<LocalContentCryptoFailure>()),
      );
      await expectLater(owner(), throwsStateError);
      await live.retire();
      expect(drains, 2);
      final reopened = await owner();
      await reopened.retire();
      expect(drains, 3);
    },
  );
}
