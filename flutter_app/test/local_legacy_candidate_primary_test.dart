import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
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
  final opened = <Database>[];
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-primary-sql-');
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.isOpen) await db.close();
    }
    opened.clear();
    await root.delete(recursive: true);
  });
  Future<Database> db(String name) async {
    final target = await databaseFactoryFfiNoIsolate.openDatabase(
      '${root.path}/$name.db',
      options: OpenDatabaseOptions(
        version: 15,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
    opened.add(target);
    return target;
  }

  Future<LegacyImportRecords> records([
    String variant = 'known-formats',
    bool alternate = false,
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
    final selection = LegacyFormatSelection(
      real,
      choices: {
        for (final item in real.items)
          item.id: item.collection == 'article' && !alternate
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    return LegacyImportRecords.fromExport(
      source,
      LegacyImportMapping.fromRecipe(
        source,
        selection.toJson(),
        scopeKey: 'b' * 32,
      ),
    );
  }

  final stamp = DateTime.utc(2026, 11, 8);
  Future<LegacyPrimaryFacts> write(
    Database target,
    LegacyCandidateRows plan, {
    bool Function()? cancelled,
    void Function(LegacyPrimaryProgress)? progress,
  }) => target.transaction((tx) async {
    await writeLegacyCandidateMetadata(tx, plan.records, importedAt: stamp);
    return writeLegacyCandidatePrimaryRows(
      tx,
      plan,
      isCancelled: cancelled,
      onProgress: progress,
    );
  });
  Future<void> empty(Database target) async {
    final tables =
        (await target.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table'",
            ))
            .map((r) => r['name'] as String)
            .where((name) => name != 'android_metadata');
    for (final name in tables) {
      expect(
        (await target.rawQuery(
          'SELECT count(*) AS n FROM "$name"',
        )).single['n'],
        0,
        reason: name,
      );
    }
  }

  Matcher reason(LegacyPrimaryWriteReason r) =>
      isA<LegacyPrimaryWriteFailure>().having((e) => e.reason, 'reason', r);

  test(
    'metadata and all 19 primary rows commit together with typed field verification',
    () async {
      final target = await db('all'),
          plan = LegacyCandidateRows.fromRecords(await records());
      final facts = await write(target, plan);
      expect(facts.counts, plan.counts);
      expect(facts.verifiedCells, greaterThan(100));
      expect(facts.verifiedTextBytes, greaterThan(0));
      expect(facts.pendingUploads, 1);
      expect(await target.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await target.rawQuery(
          'SELECT count(*) AS n FROM legacy_import_records',
        )).single['n'],
        20,
      );
      expect(
        (await target.rawQuery(
          'SELECT count(*) AS n FROM legacy_friend_links',
        )).single['n'],
        2,
      );
      final body = await target.rawQuery(
        'SELECT hex(CAST(content AS BLOB)) AS exact FROM notes WHERE id=1',
      );
      expect(body.single['exact'], startsWith('EFBBBF'));
    },
  );
  test(
    'negative epoch, original max64 and new positive revision persist as integers',
    () async {
      final target = await db('integers'),
          plan = LegacyCandidateRows.fromRecords(await records('pre-epoch'));
      await write(target, plan);
      final row = (await target.rawQuery(
        'SELECT updated_at,legacy_version,revision,'
        'typeof(updated_at) AS a,typeof(legacy_version) AS b,typeof(revision) AS c '
        'FROM notes WHERE id=1',
      )).single;
      expect(row, {
        'updated_at': -1,
        'legacy_version': 9223372036854775807,
        'revision': 1,
        'a': 'integer',
        'b': 'integer',
        'c': 'integer',
      });
    },
  );
  test(
    'multi-MiB native body remains exact through independent SQLite BLOB read',
    () async {
      final target = await db('large'), source = await records('record-chunks');
      final plan = LegacyCandidateRows.fromRecords(source);
      await write(target, plan);
      final raw = native.sqlite3.open(
        target.path,
        mode: native.OpenMode.readOnly,
      );
      try {
        raw.execute('PRAGMA trusted_schema=OFF');
        final bytes =
            raw
                    .select(
                      'SELECT CAST(content AS BLOB) AS b FROM notes WHERE id=1',
                    )
                    .single['b']
                as Uint8List;
        expect(bytes.length, greaterThan(2 * 1024 * 1024));
        final original =
            (source.source.sections['blogs.json'] as List).first as Map;
        final expected = utf8.encode(original['blog_content'] as String);
        expect(bytes.length, expected.length);
        expect(
          sha256.convert(bytes).toString(),
          sha256.convert(expected).toString(),
        );
        expect(bytes.take(3).toList(), [239, 187, 191]);
      } finally {
        raw.dispose();
      }
    },
  );
  test(
    'forward parents survive actual SQL insertion before their parent rows',
    () async {
      final target = await db('parents'),
          plan = LegacyCandidateRows.fromRecords(
            await records('forward-native'),
          );
      await write(target, plan);
      for (final pair in [
        ('documents', 'document_id'),
        ('tasks', 'task_id'),
        ('topic_comments', 'comment_id'),
      ]) {
        final column = pair.$1 == 'topic_comments'
            ? 'parent_comment_id'
            : 'parent_id';
        expect(
          (await target.rawQuery(
            'SELECT "$column" AS parent FROM "${pair.$1}" '
            'WHERE "${pair.$2}"=1',
          )).single['parent'],
          2,
        );
      }
    },
  );
  test(
    'cancel after a primary row rolls back metadata, all families and sequences',
    () async {
      final target = await db('cancel'),
          plan = LegacyCandidateRows.fromRecords(await records());
      var cancelled = false, observed = 0;
      await expectLater(
        write(
          target,
          plan,
          cancelled: () => cancelled,
          progress: (p) {
            observed = p.rows;
            if (p.rows == 1) cancelled = true;
          },
        ),
        throwsA(isA<LegacyRecordsCancelled>()),
      );
      expect(observed, 1);
      await empty(target);
    },
  );
  test(
    'changed SQL body is detected and the whole candidate transaction rolls back',
    () async {
      final target = await db('corrupt'),
          plan = LegacyCandidateRows.fromRecords(await records());
      await target.execute(
        "CREATE TRIGGER owned_test_corrupt AFTER INSERT ON notes "
        "BEGIN UPDATE notes SET content='tampered' WHERE id=NEW.id; END",
      );
      await expectLater(
        write(target, plan),
        throwsA(reason(LegacyPrimaryWriteReason.integrity)),
      );
      await empty(target);
    },
  );
  test('driver error details cannot leak primary field arguments', () async {
    final target = await db('driver'),
        plan = LegacyCandidateRows.fromRecords(await records());
    await target.execute(
      "CREATE TRIGGER owned_test_abort BEFORE INSERT ON notes "
      "BEGIN SELECT RAISE(ABORT,'synthetic-private-provider-message'); END",
    );
    Object? failure;
    try {
      await write(target, plan);
    } catch (error) {
      failure = error;
    }
    expect(failure, reason(LegacyPrimaryWriteReason.storage));
    expect(
      failure.toString(),
      isNot(contains('synthetic-private-provider-message')),
    );
    await empty(target);
  });
  test(
    'same archive with a different format decision cannot reuse metadata',
    () async {
      final target = await db('recipe'),
          source = await records(),
          other = await records('known-formats', true);
      expect(source.source.sourceSha256, other.source.sourceSha256);
      await expectLater(
        target.transaction((tx) async {
          await writeLegacyCandidateMetadata(tx, source, importedAt: stamp);
          return writeLegacyCandidatePrimaryRows(
            tx,
            LegacyCandidateRows.fromRecords(other),
          );
        }),
        throwsA(reason(LegacyPrimaryWriteReason.sourceMismatch)),
      );
      await empty(target);
    },
  );
  test(
    'primary rows cannot be written without their verified source metadata',
    () async {
      final target = await db('missing'),
          plan = LegacyCandidateRows.fromRecords(await records());
      await expectLater(
        target.transaction((tx) => writeLegacyCandidatePrimaryRows(tx, plan)),
        throwsA(reason(LegacyPrimaryWriteReason.sourceMismatch)),
      );
      await empty(target);
    },
  );
}
