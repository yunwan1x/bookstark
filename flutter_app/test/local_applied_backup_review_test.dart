import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_applied_backup_review.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_store_schema16.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  for (final version in [14, 16]) {
    for (final stale in [false, true]) {
      test(
        'schema$version applied review ${stale ? "rejects changed pending state" : "reads exact declared format"} without upgrade/acknowledgement',
        () async {
          final base = Directory(
            Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
                '${Directory.systemTemp.path}/bookstark-unit',
          );
          await base.create(recursive: true);
          final temporary = await base.createTemp('applied-review-');
          final root = Directory(await temporary.resolveSymbolicLinks());
          addTearDown(() async => root.delete(recursive: true));
          final layout = LocalDataPaths.generation(
            id: 'a' * 32,
            privateSupport: root,
          );
          await File(layout.databasePath).parent.create(recursive: true);
          final db = await databaseFactoryFfiNoIsolate.openDatabase(
            layout.databasePath,
            options: OpenDatabaseOptions(
              version: version,
              singleInstance: false,
              onCreate: (db, _) => version == 14
                  ? createLocalSchema14(db)
                  : createLocalSchema16(db),
            ),
          );
          await db.rawInsert(
            'INSERT INTO notes(title,content,updated_at) VALUES (?,CAST(? AS TEXT),?)',
            ['原始😀', utf8.encode('\uFEFF# untouched\r\n'), 1],
          );
          if (version == 16) {
            await db.insert('assistant_creation_receipts', {
              'creation_key': 'b' * 32,
              'resource_type': 'note',
              'resource_id': 1,
              'input_hash': 'c' * 64,
              'created_at': 1,
            });
          }
          final counts = <String, int>{};
          for (final table in LocalBackupManifest.requiredTablesFor(version)) {
            counts[table] =
                (await db.rawQuery(
                      'SELECT COUNT(*) AS n FROM "$table"',
                    )).single['n']
                    as int;
          }
          final sqliteVersion =
              (await db.rawQuery('SELECT sqlite_version() AS v')).single['v']
                  as String;
          await db.close();
          final before = await File(layout.databasePath).readAsBytes();
          final hash = sha256.convert(before).toString();
          final manifest = LocalBackupManifest(
            id: 'a' * 32,
            createdAt: DateTime.utc(2026).toIso8601String(),
            sqliteVersion: sqliteVersion,
            databaseSchema: version,
            tables: counts,
            files: [
              LocalBackupFile(
                path: 'database/content.db',
                bytes: before.length,
                sha256: hash,
              ),
            ],
          );
          final pointer = LocalGenerationPointer(
            generation: 'a' * 32,
            epoch: 1,
            activationId: 'd' * 32,
            sourceSHA256: 'e' * 64,
          ).encode();
          final intent = LocalRestoreIntent(
            operationId: 'd' * 32,
            sourcePointerRaw: null,
            retainedId: 'f' * 32,
            retainedManifestSHA256: '1' * 64,
            targetPointerRaw: pointer,
          );
          final retention = LocalRetention(
            id: 'f' * 32,
            sourcePointerSHA256: localPointerSHA256(null),
            sourceGeneration: 'legacy',
            manifestSHA256: '1' * 64,
          ).encode();
          var reads = 0;
          final calls = <String>[];
          final control = NativeLocalDataControl(
            invoke: (method, arguments) async {
              calls.add(method);
              if (method == 'reviewApplied') {
                expect(
                  sha256
                      .convert(await File(layout.databasePath).readAsBytes())
                      .toString(),
                  hash,
                );
                return {
                  'format': 1,
                  'operationId': intent.operationId,
                  'pointerSHA256': localPointerSHA256(pointer),
                  'intentSHA256': localPointerSHA256(intent.encode()),
                  'manifestRaw': jsonEncode(manifest.toJson()),
                  'metadataOnly': true,
                };
              }
              expect(
                method,
                'readState',
                reason: 'review must never mutate native activation',
              );
              reads++;
              return {
                'format': 1,
                'pointerRaw': pointer,
                'intentRaw': stale && reads > 1 ? null : intent.encode(),
                'currentRetentionRaw': null,
                'sourceRetentionRaw': stale && reads > 1 ? null : retention,
                'metadataOnly': true,
              };
            },
          );
          final selected = await control.readState();
          expect(selected.observation.canAcknowledgeApplied, isTrue);
          final pending = LocalAppliedBackupReviewer(
            control: control,
            privateSupport: root,
            privateCache: root,
            factory: databaseFactoryFfiNoIsolate,
          ).read(selected);
          if (stale) {
            await expectLater(pending, throwsStateError);
          } else {
            final review = await pending;
            expect(review.manifest.databaseSchema, version);
            expect(review.manifest.toJson()['version'], version == 14 ? 1 : 2);
            expect(review.manifest.tables['notes'], 1);
            expect(review.intent.encode(), intent.encode());
          }
          expect(calls, ['readState', 'reviewApplied', 'readState']);
          expect(
            sha256
                .convert(await File(layout.databasePath).readAsBytes())
                .toString(),
            hash,
          );
          final readonly = await databaseFactoryFfiNoIsolate.openDatabase(
            layout.databasePath,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
          expect(
            (await readonly.rawQuery(
              'PRAGMA user_version',
            )).single.values.single,
            version,
          );
          await readonly.close();
          expect(
            await root
                .list()
                .where(
                  (e) => e.path.split('/').last.startsWith('applied-review-'),
                )
                .isEmpty,
            isTrue,
          );
        },
      );
    }
  }
}
