import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';

class TracedTx implements Transaction {
  TracedTx(this.actual, this.hit);
  final Transaction actual;
  final void Function() hit;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? args,
  ]) {
    hit();
    return actual.rawQuery(sql, args);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class TracedDb implements Database {
  TracedDb(this.actual);
  final Database actual;
  int queries = 0;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => actual.transaction(
    (tx) => action(
      TracedTx(tx, () {
        queries++;
      }),
    ),
    exclusive: exclusive,
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

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
  late Directory root;
  late Database db;
  final gate = OwnedGeneration15SchemaGate();
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-digest-');
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      '${root.path}/unit.db',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute(
      'CREATE TABLE unit (id INTEGER PRIMARY KEY AUTOINCREMENT, payload)',
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'BOM CRLF invalid UTF8 and storage class are hashed from actual SQLite bytes',
    () async {
      final snapshots = <String>{};
      for (final bytes in [
        utf8.encode('\ufeff# same\r\n'),
        utf8.encode('# same\r\n'),
        [255, 65],
      ]) {
        await db.rawInsert(
          'INSERT OR REPLACE INTO unit(id,payload) VALUES (1,CAST(? AS TEXT))',
          [Uint8List.fromList(bytes)],
        );
        snapshots.add((await gate.rowDigests(db))['unit']!);
      }
      await db.rawUpdate('UPDATE unit SET payload=? WHERE id=1', [
        Uint8List.fromList([255, 65]),
      ]);
      snapshots.add((await gate.rowDigests(db))['unit']!);
      await db.rawUpdate('UPDATE unit SET payload=NULL WHERE id=1');
      snapshots.add((await gate.rowDigests(db))['unit']!);
      await db.rawUpdate("UPDATE unit SET payload=CAST('' AS BLOB) WHERE id=1");
      snapshots.add((await gate.rowDigests(db))['unit']!);
      expect(snapshots.length, 6);
    },
  );
  test(
    'many small rows use bounded pages instead of one bridge trip per row',
    () async {
      await db.transaction((tx) async {
        for (var i = 0; i < 1025; i++) {
          await tx.insert('unit', {'payload': 'row $i'});
        }
      });
      final trace = TracedDb(db);
      final first = await gate.rowDigests(trace);
      expect(trace.queries, lessThan(100));
      expect(await gate.rowDigests(db), first);
      expect(first.containsKey('sqlite_sequence'), isTrue);
    },
  );
  test(
    'epoch cancellation returns no partial result and releases read transaction',
    () async {
      for (var i = 0; i < 300; i++) {
        await db.insert('unit', {'payload': 'original'});
      }
      var checks = 0;
      await expectLater(
        gate.rowDigests(db, isCurrent: () => ++checks < 20),
        throwsFormatException,
      );
      await db.update(
        'unit',
        {'payload': 'after cancelled verification'},
        where: 'id=?',
        whereArgs: [1],
      );
      expect(
        (await db.query(
          'unit',
          where: 'id=?',
          whereArgs: [1],
        )).single['payload'],
        'after cancelled verification',
      );
    },
  );
  test(
    'absolute deadline rejects rather than publishing partial digest',
    () async {
      await db.insert('unit', {'payload': 'original'});
      await expectLater(
        gate.rowDigests(db, timeout: const Duration(microseconds: 1)),
        throwsFormatException,
      );
      expect(
        (await db.rawQuery('SELECT count(*) AS n FROM unit')).single['n'],
        1,
      );
    },
  );
}
