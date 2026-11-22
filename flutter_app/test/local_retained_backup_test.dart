import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
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
    available = 1 << 40;
    reads = 0;
    changeOnSecondRead = false;
    control = NativeLocalDataControl(
      invoke: (method, arguments) async {
        if (method == 'space') {
          return {'format': 1, 'availableBytes': available};
        }
        if (method != 'readState') throw StateError('Unexpected mutation');
        reads++;
        if (changeOnSecondRead && reads == 2) {
          pointer = LocalGenerationPointer(
            generation: 'f' * 32,
            epoch: 1,
            activationId: 'e' * 32,
            sourceSHA256: 'd' * 64,
          ).encode();
        }
        return {
          'format': 1,
          'pointerRaw': pointer,
          'intentRaw': null,
          'currentRetentionRaw': null,
          'sourceRetentionRaw': null,
          'metadataOnly': true,
        };
      },
    );
  });
  tearDown(() async {
    await store.close();
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

  test(
    'independent archive remains exact after source changes and token expires',
    () async {
      late FreshLocalRetention retained;
      late File archive;
      await store.maintenance.exclusive(() async {
        retained = await builder().capture();
        retained.requireFresh(await control.readState());
        archive = File(
          '${layout.controlRoot.path}/retained/${retained.metadata.id}/content.bsbackup',
        );
        expect(
          LocalRetention.parse(
            await File('${archive.parent.path}/_ready.json').readAsString(),
          ).encode(),
          retained.metadata.encode(),
        );
      });
      final baseline = await control.readState();
      expect(() => retained.requireFresh(baseline), throwsStateError);
      await store.updateNote(1, '后来', '新正文');
      await File('${layout.attachments.path}/${'a' * 32}').writeAsBytes([8]);
      final bytes = <String, List<int>>{};
      await LocalBackupCodec.decode(archive.openRead(), (entry, stream) async {
        bytes[entry.path] = await stream.expand((chunk) => chunk).toList();
      });
      expect(bytes['attachments/${'a' * 32}'], [0, 255, 2]);
      await store.maintenance.exclusive(() {
        expect(() => retained.requireFresh(baseline), throwsStateError);
      });
      expect(await archive.exists(), isTrue);
    },
  );

  test(
    'capture without existing exclusive operation never creates archive',
    () async {
      await expectLater(builder().capture(), throwsStateError);
      expect(await layout.controlRoot.exists(), isFalse);
    },
  );
  test('insufficient capacity refuses before export', () async {
    available = 0;
    await expectLater(
      store.maintenance.exclusive(() => builder().capture()),
      throwsA(isA<FileSystemException>()),
    );
    expect(await layout.controlRoot.exists(), isFalse);
    expect(await Directory('${root.path}/cache').exists(), isFalse);
  });
  test(
    'pending recovery refuses snapshot without deleting original data',
    () async {
      await expectLater(
        store.maintenance.exclusive(
          () => builder(
            preflight: () async => throw StateError('Pending'),
          ).capture(),
        ),
        throwsStateError,
      );
      expect(await layout.controlRoot.exists(), isFalse);
      expect(
        await File('${layout.attachments.path}/${'a' * 32}').readAsBytes(),
        [0, 255, 2],
      );
    },
  );
  test('changed native pointer refuses publication after snapshot', () async {
    changeOnSecondRead = true;
    await expectLater(
      store.maintenance.exclusive(() => builder().capture()),
      throwsStateError,
    );
    expect(await layout.controlRoot.exists(), isFalse);
    expect(await Directory('${root.path}/cache').list().isEmpty, isTrue);
  });
  test('identity collision preserves existing retained data', () async {
    final existing = Directory(
      '${layout.controlRoot.path}/retained/${'b' * 32}',
    );
    await existing.create(recursive: true);
    final sentinel = File('${existing.path}/sentinel');
    await sentinel.writeAsString('existing');
    await expectLater(
      store.maintenance.exclusive(() => builder().capture()),
      throwsStateError,
    );
    expect(await sentinel.readAsString(), 'existing');
    expect(await Directory('${root.path}/cache').list().isEmpty, isTrue);
  });
}
