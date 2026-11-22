import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_schema.dart';
import 'package:bookstark_flutter/core/local_backup_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory directory;
  late File source;
  late LocalBackupSchemaVerifier verifier;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookstark-backup16-');
    source = File('${directory.path}/source.db');
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      source.path,
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (db, _) => createLocalSchema16(db),
      ),
    );
    await db.insert('notes', {
      'id': 123,
      'title': 'Historical',
      'content': 'Deleted',
      'updated_at': 1,
    });
    await db.delete('notes', where: 'id=?', whereArgs: [123]);
    await db.insert('assistant_creation_receipts', {
      'creation_key': 'a' * 32,
      'resource_type': 'note',
      'resource_id': 123,
      'input_hash': 'b' * 64,
      'created_at': 1,
    });
    await db.close();
    verifier = LocalBackupSchemaVerifier(
      factory: databaseFactoryFfiNoIsolate,
      workspace: Directory('${directory.path}/check'),
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<LocalBackupManifest> manifest(LocalBackupDatabaseFacts facts) async {
    final bytes = await source.readAsBytes();
    return LocalBackupManifest(
      databaseSchema: 16,
      id: 'c' * 32,
      createdAt: '2026-11-10T00:00:00.000Z',
      sqliteVersion: facts.readerSQLiteVersion,
      tables: facts.tables,
      files: [
        LocalBackupFile(
          path: 'database/content.db',
          bytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        ),
      ],
    );
  }

  test(
    'future16 requires explicit trusted template and strict table structure',
    () async {
      final before = sha256.convert(await source.readAsBytes()).toString();
      await expectLater(verifier.verify(source), throwsFormatException);
      final facts = await verifier.verify(source, expectedSchema: 16);
      expect(facts.databaseSchema, 16);
      expect(facts.tables['assistant_creation_receipts'], 1);
      expect(sha256.convert(await source.readAsBytes()).toString(), before);
      final db = await databaseFactoryFfiNoIsolate.openDatabase(source.path);
      await db.execute(
        'ALTER TABLE assistant_creation_receipts ADD COLUMN untrusted TEXT',
      );
      await db.close();
      await expectLater(
        verifier.verify(source, expectedSchema: 16),
        throwsFormatException,
      );
    },
  );
  test(
    'version2 schema16 archive roundtrips complete receipt bytes; legacy defaults stay1/14',
    () async {
      final facts = await verifier.verify(source, expectedSchema: 16);
      final metadata = await manifest(facts);
      expect(metadata.toJson()['version'], 2);
      expect(metadata.toJson()['schema'], 16);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in LocalBackupCodec.encode(
        metadata,
        (_) => source.openRead(),
      )) {
        bytes.add(chunk);
      }
      final consumed = BytesBuilder(copy: false);
      final decoded = await LocalBackupCodec.decode(
        Stream.value(bytes.takeBytes()),
        (_, stream) async {
          await for (final chunk in stream) {
            consumed.add(chunk);
          }
        },
      );
      expect(decoded.databaseSchema, 16);
      expect(consumed.takeBytes(), await source.readAsBytes());
      final legacy = LocalBackupManifest(
        id: 'd' * 32,
        createdAt: '2026-11-10T00:00:00.000Z',
        sqliteVersion: '3.40.1',
        tables: {
          for (final table in LocalBackupManifest.requiredTables) table: 0,
        },
        files: metadata.files,
      );
      expect(legacy.toJson()['version'], 1);
      expect(legacy.toJson()['schema'], 14);
      for (final pair in [(1, 16), (2, 14), (1, 15), (2, 15)]) {
        expect(
          () => LocalBackupManifest.fromJson(
            jsonDecode(
              jsonEncode({
                ...metadata.toJson(),
                'version': pair.$1,
                'schema': pair.$2,
              }),
            ),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'receipt content validation permits deleted resources but rejects mismatched schema facts',
    () async {
      final facts = await verifier.verify(source, expectedSchema: 16);
      final metadata = await manifest(facts);
      final report = await LocalBackupContentVerifier(
        databaseFactoryFfiNoIsolate,
      ).verify(source, metadata, facts);
      expect(report.needsAdditionalReview, isFalse);
      final wrong = LocalBackupDatabaseFacts(
        readerSQLiteVersion: facts.readerSQLiteVersion,
        tables: facts.tables,
      );
      await expectLater(
        LocalBackupContentVerifier(
          databaseFactoryFfiNoIsolate,
        ).verify(source, metadata, wrong),
        throwsFormatException,
      );
    },
  );
  for (final kind in ['note', 'task']) {
    test(
      'historical $kind receipt prevents restored sequence ID reuse',
      () async {
        final db = await databaseFactoryFfiNoIsolate.openDatabase(source.path);
        if (kind == 'task') {
          await db.insert('tasks', {
            'task_id': 77,
            'content': 'Historical',
            'due_date': '2026-11-10',
            'create_time': 'now',
            'modify_time': 'now',
          });
          await db.delete('tasks', where: 'task_id=?', whereArgs: [77]);
          await db.insert('assistant_creation_receipts', {
            'creation_key': 'e' * 32,
            'resource_type': 'task',
            'resource_id': 77,
            'input_hash': 'f' * 64,
            'created_at': 1,
          });
        }
        await db.update(
          'sqlite_sequence',
          {'seq': kind == 'note' ? 122 : 76},
          where: 'name=?',
          whereArgs: [kind == 'note' ? 'notes' : 'tasks'],
        );
        await db.close();
        final facts = await verifier.verify(source, expectedSchema: 16);
        await expectLater(
          LocalBackupContentVerifier(
            databaseFactoryFfiNoIsolate,
          ).verify(source, await manifest(facts), facts),
          throwsFormatException,
        );
      },
    );
  }
}
