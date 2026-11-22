import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_applied_backup_review.dart';
import 'package:bookstark_flutter/core/local_restore_coordinator.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_retained_backup.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory root;
  late LocalDataPaths layout;
  late LocalStore store;
  late NativeLocalDataControl control;
  String? pointer;
  var available = 1 << 40;
  var reads = 0;
  var changeOnSecondRead = false;
  var dropPrepare = false, dropCommit = false;
  String? intentRaw, retentionRaw;
  final mutations = <String>[];
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    root = await base.createTemp('retained-');
    root = Directory(await root.resolveSymbolicLinks());
    layout = LocalDataPaths.legacy(
      databasePath: '${root.path}/source.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: layout.databasePath,
      factory: databaseFactoryFfiNoIsolate,
      dataPaths: layout,
    );
    await store.database;
    await store.createNote('原始', '\uFEFF# 内容\r\n');
    await layout.attachments.create();
    await layout.driveBlobs.create();
    await File(
      '${layout.attachments.path}/${'a' * 32}',
    ).writeAsBytes([0, 255, 2]);
    pointer = null;
    intentRaw = null;
    retentionRaw = null;
    mutations.clear();
    dropPrepare = false;
    dropCommit = false;
    available = 1 << 40;
    reads = 0;
    changeOnSecondRead = false;
    control = NativeLocalDataControl(
      invoke: (method, arguments) async {
        if (method == 'space') {
          return {'format': 1, 'availableBytes': available};
        }
        if (method == 'reviewApplied') {
          final intent = LocalRestoreIntent.parse(intentRaw!);
          final target = LocalGenerationPointer.parse(intent.targetPointerRaw);
          final manifest = await File(
            '${layout.controlRoot.path}/generations/${target.generation}/_manifest.json',
          ).readAsString();
          return {
            'format': 1,
            'operationId': intent.operationId,
            'pointerSHA256': localPointerSHA256(intent.targetPointerRaw),
            'intentSHA256': localPointerSHA256(intent.encode()),
            'manifestRaw': manifest,
            'metadataOnly': true,
          };
        }
        if (method == 'prepareRestore') {
          mutations.add(method);
          intentRaw = arguments!['intentRaw'] as String;
          final intent = LocalRestoreIntent.parse(intentRaw!);
          retentionRaw = LocalRetention(
            id: intent.retainedId,
            sourcePointerSHA256: intent.sourcePointerSHA256,
            sourceGeneration: 'legacy',
            manifestSHA256: intent.retainedManifestSHA256,
          ).encode();
          if (dropPrepare) throw StateError('Applied prepare response lost');
        } else if (method == 'commitRestore') {
          mutations.add(method);
          pointer = LocalRestoreIntent.parse(intentRaw!).targetPointerRaw;
          if (dropCommit) throw StateError('Applied commit response lost');
        } else if (method != 'readState') {
          throw StateError('Unexpected mutation');
        }
        reads++;
        if (changeOnSecondRead && reads == 2) {
          pointer = LocalGenerationPointer(
            generation: 'f' * 32,
            epoch: 1,
            activationId: 'e' * 32,
            sourceSHA256: 'd' * 64,
          ).encode();
        }
        final state = <String, Object?>{
          'format': 1,
          'pointerRaw': pointer,
          'intentRaw': intentRaw,
          'currentRetentionRaw': pointer == null ? retentionRaw : null,
          'sourceRetentionRaw': intentRaw == null ? null : retentionRaw,
          'metadataOnly': true,
        };
        if (method != 'readState') {
          return {
            'format': 1,
            'action': method == 'prepareRestore' ? 'prepared' : 'switched',
            'id': LocalRestoreIntent.parse(intentRaw!).operationId,
            'durable': true,
            'state': state,
          };
        }
        return state;
      },
    );
  });
  tearDown(() async {
    if (!store.maintenance.retired) await store.close();
    await root.delete(recursive: true);
  });
  LocalRetainedBackupBuilder builder({Future<void> Function()? preflight}) =>
      LocalRetainedBackupBuilder(
        exporter: LocalBackupExporter(
          store: store,
          attachments: layout.attachments,
          driveBlobs: layout.driveBlobs,
          workspace: Directory('${root.path}/cache'),
          checkPendingRecovery: preflight ?? () async {},
        ),
        control: control,
        identity: () => 'b' * 32,
      );

  Future<LocalBackupCandidate> candidate() async {
    final exporter = builder().exporter;
    final exported = await exporter.create();
    final inbox = Directory('${root.path}/local-backup-inbox-v1');
    await inbox.create();
    await exported.file.copy('${inbox.path}/${'c' * 32}.bsbackup');
    await exported.dispose();
    return LocalBackupCandidateImporter(
      privateSupport: root,
      privateCache: root,
      factory: databaseFactoryFfiNoIsolate,
      availableBytes: () async => 1 << 40,
      identity: () => 'd' * 32,
      discardCandidate: (id) async {
        await Directory(
          '${layout.controlRoot.path}/generations/$id',
        ).delete(recursive: true);
      },
    ).inspectPicked('c' * 32);
  }

  LocalRestoreCoordinator coordinator({Future<void> Function()? preflight}) =>
      LocalRestoreCoordinator(
        retainedBuilder: builder(preflight: preflight),
        identity: () => 'e' * 32,
      );

  test(
    'successful prepare/commit seals old store and requires separate acknowledgement',
    () async {
      final imported = await candidate();
      final result = await coordinator().apply(imported);
      expect(result.action, 'switched');
      expect(result.state.observation.canAcknowledgeApplied, isTrue);
      expect(mutations, ['prepareRestore', 'commitRestore']);
      expect(store.maintenance.retired, isTrue);
      await expectLater(store.database, throwsA(isA<LocalStorageRetired>()));
      await expectLater(imported.discardUnprepared(), throwsStateError);
      expect(
        await File(
          '${layout.controlRoot.path}/retained/${'b' * 32}/content.bsbackup',
        ).exists(),
        isTrue,
      );
    },
  );
  test(
    'lost prepare receipt retains both copies, seals old store, never commits',
    () async {
      final imported = await candidate();
      dropPrepare = true;
      await expectLater(
        coordinator().apply(imported),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(mutations, ['prepareRestore']);
      expect(store.maintenance.retired, isTrue);
      expect(
        (await control.readState()).observation.canFinishUnapplied,
        isTrue,
      );
      await expectLater(imported.discardUnprepared(), throwsStateError);
      expect(await File(imported.layout.databasePath).exists(), isTrue);
      expect(await File(layout.databasePath).exists(), isTrue);
    },
  );
  test(
    'lost commit response never acknowledges/replays and keeps switched review',
    () async {
      final imported = await candidate();
      dropCommit = true;
      await expectLater(
        coordinator().apply(imported),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(mutations, ['prepareRestore', 'commitRestore']);
      expect(store.maintenance.retired, isTrue);
      expect(
        (await control.readState()).observation.canAcknowledgeApplied,
        isTrue,
      );
      await expectLater(imported.discardUnprepared(), throwsStateError);
    },
  );
  test(
    'pending draft fails before sealing and leaves candidate discardable',
    () async {
      final imported = await candidate();
      await expectLater(
        coordinator(
          preflight: () async => throw StateError('Pending'),
        ).apply(imported),
        throwsStateError,
      );
      expect(mutations, isEmpty);
      expect(store.maintenance.retired, isFalse);
      await store.createNote('继续', '仍可保存');
      await imported.discardUnprepared();
      expect(await File(imported.layout.databasePath).exists(), isFalse);
    },
  );
  test(
    'nested exclusive restore refused without sealing caller session',
    () async {
      final imported = await candidate();
      await store.maintenance.exclusive(() async {
        await expectLater(coordinator().apply(imported), throwsStateError);
      });
      expect(mutations, isEmpty);
      expect(store.maintenance.retired, isFalse);
      await imported.discardUnprepared();
    },
  );
  test(
    'applied review verifies real SQLite/content without writing or acknowledging',
    () async {
      final imported = await candidate();
      final applied = await coordinator().apply(imported);
      final before = await File(imported.layout.databasePath).readAsBytes();
      final review = await LocalAppliedBackupReviewer(
        control: control,
        privateSupport: root,
        privateCache: root,
        factory: databaseFactoryFfiNoIsolate,
      ).read(applied.state);
      expect(review.manifest.tables['notes'], 1);
      expect(review.manifest.tables['books'], 0);
      expect(review.bytes, imported.sourceBytes);
      expect(await File(imported.layout.databasePath).readAsBytes(), before);
      expect(mutations, ['prepareRestore', 'commitRestore']);
      expect(
        (await control.readState()).observation.canAcknowledgeApplied,
        isTrue,
      );
    },
  );
  test(
    'applied review refuses changed declared row counts without acknowledgement',
    () async {
      final imported = await candidate();
      final applied = await coordinator().apply(imported);
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        imported.layout.databasePath,
      );
      await db.delete('notes');
      await db.close();
      await expectLater(
        LocalAppliedBackupReviewer(
          control: control,
          privateSupport: root,
          privateCache: root,
          factory: databaseFactoryFfiNoIsolate,
        ).read(applied.state),
        throwsFormatException,
      );
      expect(mutations, ['prepareRestore', 'commitRestore']);
      expect(
        (await control.readState()).observation.canAcknowledgeApplied,
        isTrue,
      );
    },
  );
}
