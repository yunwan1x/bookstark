import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_restore_coordinator.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_restore_coordinator.dart';
import 'package:bookstark_flutter/core/owned_generation15_staging.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';

class _LinkedCandidateFactory extends Fake implements DatabaseFactory {
  _LinkedCandidateFactory(this.inner, this.database, this.folder, this.outside);
  final DatabaseFactory inner;
  final String database, folder, outside;
  bool injected = false;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    if (path == database && !injected) {
      injected = true;
      expect(
        await FileSystemEntity.type(folder, followLinks: false),
        FileSystemEntityType.notFound,
      );
      await Link(folder).create(outside);
    }
    return inner.openDatabase(path, options: options);
  }

  @override
  Future<void> deleteDatabase(String path) => inner.deleteDatabase(path);
  @override
  Future<bool> databaseExists(String path) => inner.databaseExists(path);
  @override
  Future<String> getDatabasesPath() => inner.getDatabasesPath();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cryptoChannel = MethodChannel('bookstark/owned15-restore-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final factory = databaseFactoryFfiNoIsolate;
  late Directory root, support, cache;
  late OwnedGeneration15Staging stage;
  late OwnedWritableGeneration15 owner;
  bool ownerOpened = false;
  late LocalBackupCandidate candidate;
  late NativeLocalDataControl control;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  String? intentRaw, currentRetention, sourceRetention;
  bool failPrepare = false;
  final mutations = <String>[];
  Map<String, Object?> state() => {
    'format': 1,
    'pointerRaw': pointerRaw,
    'intentRaw': intentRaw,
    'currentRetentionRaw': currentRetention,
    'sourceRetentionRaw': sourceRetention,
    'metadataOnly': true,
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
  setUp(() async {
    ownerOpened = false;
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-transition-');
    support = await Directory('${root.path}/support').create();
    cache = await Directory('${root.path}/cache').create();
    final input = File(
      'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
    );
    final zip = await LegacyZipStage.inspect(
      input,
      privateParent: root,
      expectedSha256: (await sha256.bind(input.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(zip);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'e' * 32,
    );
    final choices = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    stage = await OwnedGeneration15Staging.build(
      stage: zip,
      selection: choices,
      privateParent: root,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
      isCurrentScope: () => true,
      factory: factory,
    );
    final archive = await StagedGeneration15BackupExporter(
      stage: stage,
      factory: factory,
      workspace: Directory('${root.path}/fresh-archive'),
      checkPendingRecovery: () async {},
    ).create();
    try {
      final inbox = await Directory(
        '${cache.path}/local-backup-inbox-v1',
      ).create();
      await archive.file.copy('${inbox.path}/${'f' * 32}.bsbackup');
      var next = 'a' * 32;
      final importer = LocalBackupCandidateImporter(
        privateSupport: support,
        privateCache: cache,
        factory: factory,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
        identity: () => next,
        discardCandidate: (id) async {
          await Directory(
            '${support.path}/local-data-v1/generations/$id',
          ).delete(recursive: true);
        },
      );
      final initial = await importer.inspectPicked('f' * 32);
      next = 'b' * 32;
      candidate = await importer.inspectPicked('f' * 32);
      pointer = LocalGenerationPointer(
        generation: initial.id,
        epoch: 3,
        activationId: 'c' * 32,
        sourceSHA256: initial.sourceSHA256,
      );
    } finally {
      await archive.dispose();
    }
    pointerRaw = pointer.encode();
    intentRaw = null;
    currentRetention = null;
    sourceRetention = null;
    mutations.clear();
    failPrepare = false;
    control = NativeLocalDataControl(
      invoke: (name, args) async {
        if (name == 'readState') return state();
        if (name == 'space') {
          return {'format': 1, 'availableBytes': 4 * 1024 * 1024 * 1024};
        }
        mutations.add(name);
        if (name == 'prepareRestore') {
          expect(
            owner.current,
            isFalse,
            reason: 'No native prepare before real source close',
          );
          expect(
            await File(
              '${support.path}/local-data-v1/retained/${'d' * 32}/content.bsbackup',
            ).exists(),
            isTrue,
          );
          if (failPrepare) {
            throw StateError('Dropped native preparation receipt');
          }
          intentRaw = args!['intentRaw'] as String;
          final intent = LocalRestoreIntent.parse(intentRaw!);
          currentRetention = await File(
            '${support.path}/local-data-v1/retained/${intent.retainedId}/_ready.json',
          ).readAsString();
          sourceRetention = currentRetention;
          return {
            'format': 1,
            'action': 'prepared',
            'id': intent.operationId,
            'durable': true,
            'state': state(),
          };
        }
        if (name == 'commitRestore') {
          final intent = LocalRestoreIntent.parse(intentRaw!);
          pointerRaw = intent.targetPointerRaw;
          currentRetention = null;
          return {
            'format': 1,
            'action': 'switched',
            'id': intent.operationId,
            'durable': true,
            'state': state(),
          };
        }
        throw StateError('No implicit acknowledge/retry/cleanup');
      },
    );
    messenger.setMockMethodCallHandler(cryptoChannel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('No unlocking for source backup');
    });
    final activeLayout = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: support,
    );
    for (final folder in [activeLayout.attachments, activeLayout.driveBlobs]) {
      expect(
        await FileSystemEntity.type(folder.path, followLinks: false),
        FileSystemEntityType.directory,
      );
    }
    owner = await OwnedWritableGeneration15.openActive(
      privateSupport: support,
      workspace: await Directory(
        '${support.path}/owned15-verification',
      ).create(),
      expectedPointer: pointer,
      isCurrentScope: () => true,
      factory: factory,
      control: control,
      crypto: NativeLocalContentCrypto(channel: cryptoChannel),
    );
    ownerOpened = true;
  });
  tearDown(() async {
    if (ownerOpened) await owner.retire();
    await stage.retire();
    messenger.setMockMethodCallHandler(cryptoChannel, null);
    await root.delete(recursive: true);
  });
  OwnedGeneration15RestoreCoordinator coordinator({
    Future<void> Function()? beforeSeal,
  }) {
    var call = 0;
    return OwnedGeneration15RestoreCoordinator(
      owner: owner,
      control: control,
      exporter: OwnedGeneration15BackupExporter(
        owner: owner,
        factory: factory,
        workspace: Directory('${root.path}/retention-exports'),
        checkPendingRecovery: () async {},
      ),
      beforeSeal:
          beforeSeal ??
          () async {
            expect(owner.current, isTrue);
          },
      identity: () => (++call == 1 ? 'd' : 'e') * 32,
    );
  }

  test(
    'fresh candidate rejects raced resource-root symlink without touching target',
    () async {
      final outside = await Directory('${root.path}/outside').create();
      final sentinel = File('${outside.path}/sentinel');
      await sentinel.writeAsString('unchanged');
      final layout = LocalDataPaths.generation(
        id: '9' * 32,
        privateSupport: support,
      );
      final linked = _LinkedCandidateFactory(
        factory,
        layout.databasePath,
        layout.driveBlobs.path,
        outside.path,
      );
      final importer = LocalBackupCandidateImporter(
        privateSupport: support,
        privateCache: cache,
        factory: linked,
        identity: () => '9' * 32,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
        discardCandidate: (id) async {
          await Directory(
            '${support.path}/local-data-v1/generations/$id',
          ).delete(recursive: true);
        },
      );
      await expectLater(
        importer.inspectPicked('f' * 32),
        throwsFormatException,
      );
      expect(linked.injected, isTrue);
      expect(await sentinel.readAsString(), 'unchanged');
      expect(await outside.exists(), isTrue);
      expect(
        await Directory(
          '${support.path}/local-data-v1/generations/${'9' * 32}',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'complete15 source retained before close and single native prepare/commit without acknowledge',
    () async {
      final before = await owner.exclusiveSnapshot(
        (db) => OwnedGeneration15SchemaGate().rowDigests(db),
      );
      final receipt = await coordinator().apply(candidate);
      expect(receipt.action, 'switched');
      expect(receipt.state.observation.canAcknowledgeApplied, isTrue);
      expect(mutations, ['prepareRestore', 'commitRestore']);
      expect(owner.current, isFalse);
      final retained = File(
        '${support.path}/local-data-v1/retained/${'d' * 32}/content.bsbackup',
      );
      final snapshot = File('${root.path}/retained-check.db');
      final manifest = await LocalBackupCodec.decode(retained.openRead(), (
        entry,
        stream,
      ) async {
        if (entry.path == 'database/content.db') {
          final sink = snapshot.openWrite();
          try {
            await sink.addStream(stream);
            await sink.flush();
          } finally {
            await sink.close();
          }
        } else {
          await stream.drain<void>();
        }
      });
      expect(manifest.databaseSchema, 15);
      final retainedDb = await factory.openDatabase(
        snapshot.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(
          await OwnedGeneration15SchemaGate().rowDigests(retainedDb),
          before,
        );
      } finally {
        await retainedDb.close();
      }
      await owner.retire(); // Already sealed must remain safely idempotent.
      await expectLater(candidate.discardUnprepared(), throwsStateError);
      expect(
        await File(
          '${support.path}/local-data-v1/retained/${'d' * 32}/content.bsbackup',
        ).exists(),
        isTrue,
      );
    },
  );
  test(
    'preview drain failure leaves source writable and never invokes native mutation',
    () async {
      await expectLater(
        coordinator(
          beforeSeal: () async {
            throw StateError('Preview did not drain');
          },
        ).apply(candidate),
        throwsA(isA<LocalRestoreNotStarted>()),
      );
      expect(owner.current, isTrue);
      expect(mutations, isEmpty);
      final entry = (await owner.content.list(collection: 'all')).first;
      final handle = await owner.content.open(
        entry.metadata.id,
        collection: entry.metadata.collection,
      );
      expect(handle.isCurrent, isTrue);
      await candidate.discardUnprepared();
    },
  );
  test(
    'uncertain native prepare retains source and candidate without automatic replay',
    () async {
      failPrepare = true;
      await expectLater(
        coordinator().apply(candidate),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(mutations, ['prepareRestore']);
      expect(owner.current, isFalse);
      await expectLater(candidate.discardUnprepared(), throwsStateError);
      expect(
        await File(
          '${support.path}/local-data-v1/retained/${'d' * 32}/content.bsbackup',
        ).exists(),
        isTrue,
      );
    },
  );
  test(
    'sealing outside fully-drained snapshot cannot close or grant authority',
    () async {
      await expectLater(
        owner.sealForActivationWithinSnapshot(),
        throwsStateError,
      );
      expect(owner.current, isTrue);
      expect(mutations, isEmpty);
    },
  );
}
