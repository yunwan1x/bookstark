import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/resolved_local_storage.dart';

class _Factory implements DatabaseFactory {
  _Factory(this.target);
  final String target;
  int writes = 0, reads = 0;
  @override
  Future<Database> openDatabase(String name, {OpenDatabaseOptions? options}) {
    if (name == target) {
      if (options?.readOnly == true) {
        reads++;
      } else {
        writes++;
      }
    }
    return databaseFactoryFfiNoIsolate.openDatabase(name, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/resolved-storage-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root, work;
  late LocalDataPaths layout;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  late _Factory factory;
  late LocalStorageSession session;
  bool current = true;
  int nativeReads = 0;
  void Function(int)? onRead;
  ResolvedLocalStorage? live;
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
    root = await parent.createTemp('resolved-storage-');
    work = await Directory('${root.path}/verify').create();
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 7,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    pointerRaw = pointer.encode();
    current = true;
    nativeReads = 0;
    onRead = null;
    live = null;
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
      'title': 'Exact',
      'content': '\ufeffOriginal\r\n',
      'labels': '[]',
      'updated_at': 1,
    });
    await db.close();
    factory = _Factory(layout.databasePath);
    session = LocalStorageSession(
      privateSupport: root,
      legacyDatabasePath: '${root.path}/legacy.db',
      factory: factory,
      control: NativeLocalDataControl(
        invoke: (name, args) async {
          expect(name, 'readState');
          onRead?.call(++nativeReads);
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
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('No password operations during dispatch');
    });
  });
  tearDown(() async {
    await live?.retire();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<ResolvedLocalStorage> resolve() => ResolvedLocalStorage.open(
    session: session,
    verificationWorkspace: work,
    isCurrentScope: () => current,
    crypto: NativeLocalContentCrypto(channel: channel),
  );

  test(
    'schema15 selects sealed owned writer without ordinary LocalStore upgrade',
    () async {
      live = await resolve();
      expect(live, isA<Owned15ResolvedLocalStorage>());
      expect(factory.reads, greaterThanOrEqualTo(2));
      expect(factory.writes, 1);
      final owner = (live! as Owned15ResolvedLocalStorage).owner;
      final handle = await owner.content.open(9, collection: 'note');
      expect(handle.source, '\ufeffOriginal\r\n');
      await owner.exclusiveSnapshot((db) async {
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          15,
        );
      });
    },
  );
  test('schema16 keeps ordinary complete module path', () async {
    await File(layout.databasePath).delete();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(
        version: 16,
        singleInstance: false,
        onCreate: (db, _) => createLocalSchema16(db),
      ),
    );
    await db.close();
    live = await resolve();
    expect(live, isA<OrdinaryResolvedLocalStorage>());
    final ordinary = (live! as OrdinaryResolvedLocalStorage).store;
    expect(
      (await (await ordinary.database).rawQuery(
        'PRAGMA user_version',
      )).single.values.single,
      16,
    );
  });
  test('future unsupported schema never receives any writable open', () async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA user_version=17');
    await db.close();
    await expectLater(resolve(), throwsFormatException);
    expect(factory.writes, 0);
  });
  test(
    'native epoch changes during read-only classification never authorize writer',
    () async {
      onRead = (n) {
        if (n == 2) {
          pointerRaw = LocalGenerationPointer(
            generation: pointer.generation,
            epoch: 8,
            activationId: 'd' * 32,
            sourceSHA256: 'c' * 64,
          ).encode();
        }
      };
      await expectLater(resolve(), throwsStateError);
      expect(factory.writes, 0);
    },
  );
  test(
    'stale caller before resolution makes no native or SQL request',
    () async {
      current = false;
      await expectLater(resolve(), throwsStateError);
      expect(nativeReads, 0);
      expect(factory.reads, 0);
      expect(factory.writes, 0);
    },
  );
  test(
    'symlinked intermediate generation directory is rejected before SQL probe',
    () async {
      final folder = File(layout.databasePath).parent;
      final moved = await folder.rename('${root.path}/moved-database');
      await Link(folder.path).create(moved.path);
      await expectLater(resolve(), throwsFormatException);
      expect(factory.reads, 0);
      expect(factory.writes, 0);
    },
  );
}
