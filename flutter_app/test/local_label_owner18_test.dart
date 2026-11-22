import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_label_management_repository.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';

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
  test(
    'retirement during actual rename receipt rolls back registry and all source label changes',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      var current = true, retireAtReceipt = false, clockCalls = 0;
      final repo = LocalLabelManagementRepository(
        store,
        isCurrent: () => current,
        clock: () {
          clockCalls++;
          if (retireAtReceipt) current = false;
          return DateTime.now();
        },
      );
      try {
        final old = await repo.save('Old');
        final id = await store.createNote(
          'Source',
          '\ufeffActual body\r\n😀',
          labels: ['Old', 'untouched,tag'],
        );
        final db = await store.database;
        final beforeLabels = await db.query(
          'local_labels',
          orderBy: 'label_id',
        );
        final beforeNote = await db.rawQuery(
          'SELECT id,title,CAST(content AS BLOB) AS source,labels,updated_at FROM notes WHERE id=?',
          [id],
        );
        retireAtReceipt = true;
        await expectLater(repo.save('New', id: old.id), throwsStateError);
        expect(clockCalls, greaterThan(0));
        expect(
          await db.query('local_labels', orderBy: 'label_id'),
          beforeLabels,
        );
        expect(
          await db.rawQuery(
            'SELECT id,title,CAST(content AS BLOB) AS source,labels,updated_at FROM notes WHERE id=?',
            [id],
          ),
          beforeNote,
        );
        expect(
          jsonDecode(
            (await db.query(
                  'notes',
                  columns: ['labels'],
                  where: 'id=?',
                  whereArgs: [id],
                )).single['labels']
                as String,
          ),
          ['Old', 'untouched,tag'],
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'retired local owner cannot create or write shared recommendation settings',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      var current = true;
      final repo = LocalLabelManagementRepository(
        store,
        isCurrent: () => current,
      );
      try {
        final db = await store.database;
        final before = await db.query('label_recommendation_settings');
        current = false;
        await expectLater(repo.save('must not create'), throwsStateError);
        await expectLater(
          repo.saveRecommendationSettings(
            const LabelRecommendationSettings(
              strategy: LabelRecommendationStrategy.manual,
              manualLabels: ['must not save'],
            ),
          ),
          throwsStateError,
        );
        expect(await db.query('local_labels'), isEmpty);
        expect(await db.query('label_recommendation_settings'), before);
      } finally {
        await store.close();
      }
    },
  );
}
