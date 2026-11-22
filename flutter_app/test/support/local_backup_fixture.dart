import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_store.dart';

class LocalBackupFixture {
  LocalBackupFixture._(this.root, this.store, this.retention, this.candidate);
  final Directory root;
  final LocalStore store;
  final LocalRetention retention;
  final LocalBackupCandidate candidate;
  LocalBackupCandidateImporter get importer => LocalBackupCandidateImporter(
    privateSupport: root,
    privateCache: root,
    factory: databaseFactoryFfiNoIsolate,
    availableBytes: () async => 1 << 40,
    // Test fixture owns every generation here; production uses serialized native discard.
    discardCandidate: (id) async => Directory(
      '${root.path}/local-data-v1/generations/$id',
    ).delete(recursive: true),
  );
  static Future<LocalBackupFixture> create() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    var root = await base.createTemp('backup-ui-fixture-');
    root = Directory(await root.resolveSymbolicLinks());
    final layout = LocalDataPaths.legacy(
      databasePath: '${root.path}/source.db',
      privateSupport: root,
    );
    final store = LocalStore(
      path: layout.databasePath,
      dataPaths: layout,
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.createNote('原笔记', '\uFEFF# 原文\r\n');
    await store.createNote('原文章', '内容', collection: 'article');
    await layout.attachments.create();
    await layout.driveBlobs.create();
    await File(
      '${layout.attachments.path}/${'a' * 32}',
    ).writeAsBytes([1, 255, 0]);
    final exported = await LocalBackupExporter(
      store: store,
      attachments: layout.attachments,
      driveBlobs: layout.driveBlobs,
      workspace: Directory('${root.path}/exports'),
      checkPendingRecovery: () async {},
      clock: () => DateTime.utc(2026, 11, 8, 18, 20),
    ).create();
    final retention = LocalRetention(
      id: 'b' * 32,
      sourcePointerSHA256: localPointerSHA256(null),
      sourceGeneration: 'legacy',
      manifestSHA256: exported.manifestSHA256,
    );
    final retained = await Directory(
      '${root.path}/local-data-v1/retained/${retention.id}',
    ).create(recursive: true);
    await exported.file.copy('${retained.path}/content.bsbackup');
    await File(
      '${retained.path}/_ready.json',
    ).writeAsString(retention.encode());
    final importer = LocalBackupCandidateImporter(
      privateSupport: root,
      privateCache: root,
      factory: databaseFactoryFfiNoIsolate,
      availableBytes: () async => 1 << 40,
      discardCandidate: (id) async => Directory(
        '${root.path}/local-data-v1/generations/$id',
      ).delete(recursive: true),
    );
    final candidate = await importer.inspectRetained(retention);
    await exported.dispose();
    return LocalBackupFixture._(root, store, retention, candidate);
  }

  Future<void> dispose() async {
    await store.close();
    await root.delete(recursive: true);
  }
}
