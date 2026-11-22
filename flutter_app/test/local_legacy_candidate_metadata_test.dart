import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory root;
  final databases = <Database>[];
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-metadata-');
  });
  tearDown(() async {
    for (final db in databases) {
      if (db.isOpen) await db.close();
    }
    databases.clear();
    await root.delete(recursive: true);
  });
  Future<Database> db(
    String name, {
    int version = 15,
    bool foreign = true,
  }) async {
    final result = await databaseFactoryFfiNoIsolate.openDatabase(
      '${root.path}/$name.db',
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onConfigure: (db) => db.execute(
          foreign ? 'PRAGMA foreign_keys=ON' : 'PRAGMA foreign_keys=OFF',
        ),
        onCreate: (db, v) => v == 15
            ? createLegacyCandidateSchema15(db)
            : createLocalSchema14(db),
      ),
    );
    databases.add(result);
    return result;
  }

  Future<LegacyImportRecords> records([
    String variant = 'known-formats',
  ]) async {
    final file = File('test/fixtures/legacy_zip/identity-$variant.zip');
    final source = await LegacyGoExport.inspect(
      await LegacyZipStage.inspect(
        file,
        privateParent: root,
        expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
      ),
    );
    final real = LegacyFormatSource.fromInspection(source, scopeKey: 'b' * 32);
    final choice = LegacyFormatSelection(
      real,
      choices: {
        for (final item in real.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    return LegacyImportRecords.fromExport(
      source,
      LegacyImportMapping.fromRecipe(
        source,
        choice.toJson(),
        scopeKey: 'b' * 32,
      ),
    );
  }

  final stamp = DateTime.utc(2026, 11, 8);
  Future<void> empty(Database db) async {
    for (final name in [
      'legacy_import_sources',
      'legacy_import_records',
      'legacy_import_label_relations',
    ]) {
      expect(
        (await db.rawQuery('SELECT count(*) AS n FROM "$name"')).single['n'],
        0,
      );
    }
  }

  Matcher reason(LegacyMetadataReason value) =>
      isA<LegacyMetadataFailure>().having((e) => e.reason, 'reason', value);

  test(
    'actual metadata transaction verifies source, recipe and every stored row',
    () async {
      final target = await db('basic'), prepared = await records();
      final progress = <LegacyMetadataProgress>[];
      final facts = await target.transaction(
        (tx) => writeLegacyCandidateMetadata(
          tx,
          prepared,
          importedAt: stamp,
          onProgress: progress.add,
        ),
      );
      expect(facts.records, 20);
      expect(facts.labelRelations, 1);
      expect(facts.sourceSha256, prepared.source.sourceSha256);
      expect(facts.verifiedBytes, greaterThan(0));
      final source = (await target.query('legacy_import_sources')).single;
      expect(source['format_recipe_json'], prepared.mapping.recipeJson);
      expect(source['imported_at'], stamp.toIso8601String());
      expect(progress.last.records, 20);
      expect(progress.last.relations, 1);
      expect(progress.last.totalRecords, 20);
      expect(
        (await target.rawQuery('SELECT count(*) AS n FROM notes')).single['n'],
        0,
      );
      // This is deliberately metadata-only, not a fully populated migration.
      expect(
        (await target.rawQuery(
          'SELECT count(*) AS n FROM legacy_friend_links',
        )).single['n'],
        0,
      );
    },
  );
  test(
    'large Unicode BOM/CRLF payload survives SQL and independent SQLite BLOB read',
    () async {
      final target = await db('large'),
          prepared = await records('record-chunks');
      final facts = await target.transaction(
        (tx) => writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
      );
      expect(facts.verifiedBytes, greaterThan(3 * 1024 * 1024));
      final raw = native.sqlite3.open(
        target.path,
        mode: native.OpenMode.readOnly,
      );
      try {
        raw.execute('PRAGMA trusted_schema=OFF');
        final row = raw
            .select(
              "SELECT CAST(payload AS BLOB) AS bytes,payload_sha256 "
              "FROM legacy_import_records WHERE kind='note' AND local_id=1",
            )
            .single;
        final bytes = row['bytes'] as Uint8List;
        expect(bytes.length, greaterThan(2 * 1024 * 1024));
        expect(sha256.convert(bytes).toString(), row['payload_sha256']);
        final fields = (jsonDecode(utf8.decode(bytes)) as Map)['fields'] as Map;
        final original =
            (prepared.source.sections['blogs.json'] as List).first as Map;
        expect(fields['blog_content'], original['blog_content']);
        expect(fields['blog_content'], startsWith('\uFEFF汉🙂\r\n'));
      } finally {
        raw.dispose();
      }
    },
  );
  test(
    'cancellation after one verified row rolls back source and all metadata',
    () async {
      final target = await db('cancel'), prepared = await records();
      var cancelled = false, observed = 0;
      await expectLater(
        target.transaction(
          (tx) => writeLegacyCandidateMetadata(
            tx,
            prepared,
            importedAt: stamp,
            isCancelled: () => cancelled,
            onProgress: (p) {
              observed = p.records;
              if (p.records == 1) cancelled = true;
            },
          ),
        ),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      expect(observed, 1);
      await empty(target);
    },
  );
  test(
    'stored payload corruption is detected and the complete transaction rolls back',
    () async {
      final target = await db('corrupt'), prepared = await records();
      await target.execute(
        "CREATE TRIGGER owned_test_corrupt AFTER INSERT ON legacy_import_records "
        "BEGIN UPDATE legacy_import_records SET payload=payload||'x' "
        "WHERE kind=NEW.kind AND local_id=NEW.local_id; END",
      );
      await expectLater(
        target.transaction(
          (tx) => writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
        ),
        throwsA(reason(LegacyMetadataReason.integrity)),
      );
      await empty(target);
    },
  );
  test('existing content prevents writes and remains byte exact', () async {
    final target = await db('nonempty'), prepared = await records();
    await target.insert('notes', {
      'id': 41,
      'title': 'existing',
      'content': '\uFEFF# original\r\n',
      'updated_at': 17,
    });
    final before = await target.rawQuery(
      'SELECT hex(CAST(content AS BLOB)) AS bytes FROM notes',
    );
    await expectLater(
      target.transaction(
        (tx) => writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
      ),
      throwsA(reason(LegacyMetadataReason.nonemptyCandidate)),
    );
    expect(
      await target.rawQuery(
        'SELECT hex(CAST(content AS BLOB)) AS bytes FROM notes',
      ),
      before,
    );
    await empty(target);
  });
  test(
    'active v14 and candidates without foreign-key enforcement are refused',
    () async {
      final prepared = await records();
      for (final target in [
        await db('v14', version: 14),
        await db('fkoff', foreign: false),
      ]) {
        await expectLater(
          target.transaction(
            (tx) =>
                writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
          ),
          throwsA(reason(LegacyMetadataReason.incompatibleSchema)),
        );
      }
    },
  );
  test(
    'driver errors containing source text become fixed errors and roll back',
    () async {
      final target = await db('driver-error'), prepared = await records();
      await target.execute(
        "CREATE TRIGGER owned_test_abort BEFORE INSERT ON legacy_import_records "
        "BEGIN SELECT RAISE(ABORT,'synthetic-sensitive-provider-message'); END",
      );
      Object? failure;
      try {
        await target.transaction(
          (tx) => writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, reason(LegacyMetadataReason.storage));
      expect(
        failure.toString(),
        isNot(contains('synthetic-sensitive-provider-message')),
      );
      await empty(target);
    },
  );
  test(
    'duplicate source label relations remain separate durable rows',
    () async {
      final target = await db('relations'),
          prepared = await records('duplicate-label-relations');
      final facts = await target.transaction(
        (tx) => writeLegacyCandidateMetadata(tx, prepared, importedAt: stamp),
      );
      expect(facts.labelRelations, 2);
      final rows = await target.query(
        'legacy_import_label_relations',
        columns: ['relation_id', 'label_id', 'resource_kind', 'resource_id'],
        orderBy: 'relation_id',
      );
      expect(rows.map((r) => r['relation_id']).toList(), [1, 2]);
      expect(
        rows.every(
          (r) =>
              r['label_id'] == 1 &&
              r['resource_kind'] == 'note' &&
              r['resource_id'] == 1,
        ),
        isTrue,
      );
    },
  );
  test(
    'progress observer failure also rolls back the candidate transaction',
    () async {
      final target = await db('observer'), prepared = await records();
      await expectLater(
        target.transaction(
          (tx) => writeLegacyCandidateMetadata(
            tx,
            prepared,
            importedAt: stamp,
            onProgress: (p) {
              if (p.records == 1) throw StateError('owned-observer');
            },
          ),
        ),
        throwsStateError,
      );
      await empty(target);
    },
  );
}
