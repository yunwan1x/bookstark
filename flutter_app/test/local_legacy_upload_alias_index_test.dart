import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_policy.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_index.dart';

class _PausedDatabase implements Database {
  _PausedDatabase(this.inner);
  final Database inner;
  final selected = Completer<void>(), release = Completer<void>();
  @override
  String get path => inner.path;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final value = await inner.rawQuery(sql, arguments);
    if (sql.contains('FROM legacy_import_upload_blobs')) {
      selected.complete();
      await release.future;
    }
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late LocalDataPaths generation;
  late Database db;
  late bool current;
  final source = 'a' * 64, id = 'c' * 32, hash = 'd' * 64;
  final origin = Uri.parse('https://${'b' * 32}.bookstark-local.invalid');
  final policy = LegacyUploadAliasPolicy(isolatedOrigin: origin);
  final indexes = <LegacyUploadAliasIndex>[];
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
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-alias-index-');
    generation = LocalDataPaths.generation(id: 'e' * 32, privateSupport: root);
    await File(generation.databasePath).parent.create(recursive: true);
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      generation.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.insert('legacy_import_sources', {
      'source_sha256': source,
      'source_kind': 'go_zip_v1',
      'manifest_json': '{}',
      'format_recipe_json': '{}',
      'imported_at': '2026-11-08T00:00:00Z',
    });
    final payload = jsonEncode({
      'source_sha256': source,
      'fields': {'storage_path': 'a.png'},
    });
    await db.insert('legacy_import_records', {
      'kind': 'upload',
      'local_id': 1,
      'source_sha256': source,
      'source_key': '["upload","a.png"]',
      'payload': payload,
      'payload_sha256': sha256.convert(utf8.encode(payload)).toString(),
    });
    await db.insert('legacy_import_upload_blobs', {
      'attachment_id': id,
      'source_sha256': source,
      'logical_name': 'uploads/a.png',
      'alias_path': '/upload-files/a.png',
      'file_size': 7,
      'file_sha256': hash,
    });
    await db.insert('legacy_import_upload_bindings', {
      'source_sha256': source,
      'upload_id': 1,
      'role': 'original',
      'attachment_id': id,
    });
    current = true;
    indexes.clear();
  });
  tearDown(() async {
    for (final index in indexes) {
      index.dispose();
    }
    if (db.isOpen) {
      await db.close();
    }
    await root.delete(recursive: true);
  });
  LegacyUploadAliasIndex index({
    Database? database,
    String? sourceSha,
    bool Function()? live,
  }) {
    final result = LegacyUploadAliasIndex(
      database: database ?? db,
      generation: generation,
      sourceSha256: sourceSha ?? source,
      policy: policy,
      isCurrent: live ?? () => current,
    );
    indexes.add(result);
    return result;
  }

  test(
    'returns same-source generation metadata without opening attachment files',
    () async {
      final result = await index().lookup('/upload-files/a.png?v=123#image');
      expect(result, isNotNull);
      expect(result!.generationId, generation.generationId);
      expect(result.sourceSha256, source);
      expect(result.attachmentId, id);
      expect(result.sha256Hex, hash);
      expect(result.bytes, 7);
      expect(result.isCurrent, true);
      expect(await generation.attachments.exists(), false);
    },
  );
  test(
    'foreign origin, missing alias and wrong source return no reference',
    () async {
      final value = index();
      expect(
        await value.lookup('https://evil.invalid/upload-files/a.png'),
        isNull,
      );
      expect(await value.lookup('/upload-files/missing.png'), isNull);
      expect(
        await index(sourceSha: 'f' * 64).lookup('/upload-files/a.png'),
        isNull,
      );
    },
  );
  test(
    'removing the source binding prevents otherwise matching blob lookup',
    () async {
      await db.delete('legacy_import_upload_bindings');
      expect(await index().lookup('/upload-files/a.png'), isNull);
    },
  );
  test(
    'retiring a lease invalidates issued references and cannot be reversed',
    () async {
      final value = index(),
          reference = await value.lookup('/upload-files/a.png');
      expect(reference!.isCurrent, true);
      current = false;
      expect(reference.isCurrent, false);
      current = true;
      expect(reference.isCurrent, false);
      expect(await value.lookup('/upload-files/a.png'), isNull);
    },
  );
  test(
    'closing index retires issued metadata without closing shared database',
    () async {
      final value = index(),
          reference = await value.lookup('/upload-files/a.png');
      value.dispose();
      expect(reference!.isCurrent, false);
      expect(db.isOpen, true);
      expect(await value.lookup('/upload-files/a.png'), isNull);
    },
  );
  test('lease loss during real SQL await discards late query result', () async {
    final paused = _PausedDatabase(db);
    final actual = index(database: paused);
    final pending = actual.lookup('/upload-files/a.png');
    await paused.selected.future.timeout(const Duration(seconds: 5));
    current = false;
    paused.release.complete();
    expect(await pending, isNull);
    current = true;
    expect(await actual.lookup('/upload-files/a.png'), isNull);
  });
  test('closing during SQL await discards result', () async {
    final paused = _PausedDatabase(db);
    final actual = index(database: paused),
        pending = actual.lookup('/upload-files/a.png');
    await paused.selected.future.timeout(const Duration(seconds: 5));
    actual.dispose();
    paused.release.complete();
    expect(await pending, isNull);
  });
  test('throwing lease callback fails closed permanently', () async {
    var throwing = true;
    final value = index(
      live: () {
        if (throwing) throw StateError('synthetic');
        return true;
      },
    );
    expect(await value.lookup('/upload-files/a.png'), isNull);
    throwing = false;
    expect(await value.lookup('/upload-files/a.png'), isNull);
  });
  test(
    'explicit inline size bounds never authorize oversized resource metadata',
    () async {
      await db.update('legacy_import_upload_blobs', {
        'file_size': 6 * 1024 * 1024,
      });
      final value = index();
      expect(await value.lookup('/upload-files/a.png'), isNull);
      expect(
        (await value.lookup(
          '/upload-files/a.png',
          maxBytes: 6 * 1024 * 1024,
        ))!.bytes,
        6 * 1024 * 1024,
      );
      await expectLater(
        value.lookup('/upload-files/a.png', maxBytes: -1),
        throwsArgumentError,
      );
      await expectLater(
        value.lookup('/upload-files/a.png', maxBytes: 20 * 1024 * 1024 + 1),
        throwsArgumentError,
      );
    },
  );
  test('schema14 and SQL failures fail closed', () async {
    await db.execute('PRAGMA user_version=14');
    expect(await index().lookup('/upload-files/a.png'), isNull);
    await db.execute('PRAGMA user_version=15');
    await db.close();
    expect(await index().lookup('/upload-files/a.png'), isNull);
  });
  test(
    'invalid hash and noninteger SQLite size cannot create a reference',
    () async {
      await db.execute('PRAGMA ignore_check_constraints=ON');
      await db.update('legacy_import_upload_blobs', {'file_sha256': 'Z' * 64});
      expect(await index().lookup('/upload-files/a.png'), isNull);
      await db.update('legacy_import_upload_blobs', {
        'file_sha256': hash,
        'file_size': 3.5,
      });
      expect(await index().lookup('/upload-files/a.png'), isNull);
    },
  );
  test(
    'legacy or mismatched generation paths and malformed source hashes are rejected',
    () {
      final legacy = LocalDataPaths.legacy(
        databasePath: db.path,
        privateSupport: root,
      );
      final other = LocalDataPaths.generation(
        id: 'f' * 32,
        privateSupport: root,
      );
      for (final value in [legacy, other]) {
        expect(
          () => LegacyUploadAliasIndex(
            database: db,
            generation: value,
            sourceSha256: source,
            policy: policy,
            isCurrent: () => true,
          ),
          throwsArgumentError,
        );
      }
      expect(() => index(sourceSha: 'not-a-source'), throwsArgumentError);
    },
  );
}
