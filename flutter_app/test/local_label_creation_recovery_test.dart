import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/label_creation_attempt.dart';
import 'package:bookstark_flutter/core/local_label_creation_controller.dart';
import 'package:bookstark_flutter/core/local_label_creation_review.dart';
import 'package:bookstark_flutter/core/local_label_creation_store.dart';
import 'package:bookstark_flutter/core/local_label_management_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';

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
  for (final loseAck in [true, false]) {
    test(
      loseAck
          ? 'actual SQL commit then cold unknown never repeats SQL and adoption stays manual'
          : 'actual SQL acknowledgement storage retry never creates another row',
      () async {
        final local = LocalStore(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final repository = LocalLabelManagementRepository(local);
        final reader = LocalLabelCreationMetadataReader(
          store: local,
          isCurrent: () => true,
        );
        final values = <String, String>{};
        var calls = 0, flushes = 0, failAck = !loseAck;
        final scope = (loseAck ? '1' : '2') * 64,
            key = (loseAck ? '1' : '2') * 32;
        LocalLabelCreationStore journal() => LocalLabelCreationStore(
          scope: scope,
          key: key,
          read: (k) async => values[k],
          write: (k, v) async {
            values[k] = v;
          },
          remove: (k) async {
            values.remove(k);
          },
          flush: () async {
            flushes++;
            if (failAck && flushes == 3) {
              throw StateError('synthetic acknowledgement flush failure');
            }
          },
          isCurrent: () => true,
        );
        LocalLabelCreationController make() => LocalLabelCreationController(
          store: journal(),
          create: (name) async {
            calls++;
            final actual = await repository.createLocalTransaction(name);
            if (loseAck) {
              throw StateError('synthetic process boundary after real commit');
            }
            return actual;
          },
          inspect: reader.inspect,
        );
        var c = make();
        try {
          const name = '\ufeff Exact 😀 ';
          await c.begin(
            LabelCreationAttempt(
              scope: scope,
              key: key,
              body: {'label_name': name},
            ),
          );
          await c.submit();
          expect(calls, 1);
          expect(c.record!.phase, LabelCreationPhase.unknown);
          final db = await local.database;
          final actualRows = await db.rawQuery(
            'SELECT label_id,CAST(label_name AS BLOB) AS name FROM local_labels',
          );
          expect(actualRows, hasLength(1));
          expect(actualRows.single['name'], utf8.encode(name));
          final id = actualRows.single['label_id'] as int;
          if (loseAck) {
            c.dispose();
            c = make();
            await c.reload();
            await c.submit();
            expect(calls, 1);
            final before = Map<String, String>.of(values);
            await c.begin(
              LabelCreationAttempt(
                scope: scope,
                key: key,
                body: {'label_name': 'changed'},
              ),
            );
            expect(values, before);
            expect(calls, 1);
            await c.reload();
            await c.review(id);
            final stale = c.reviewed!;
            // Real metadata change invalidates the complete fresh review fingerprint.
            final note = await local.createNote(
              'private title',
              '\ufeff private body\r\n😀',
              labels: [name],
            );
            await c.adopt(stale);
            expect(c.record!.phase, LabelCreationPhase.unknown);
            await c.review(id);
            expect(c.reviewed!.wire['relation_count'], 1);
            expect(c.reviewed!.display, contains('"resource_id":$note'));
            expect(c.reviewed!.display, isNot(contains('private title')));
            expect(c.reviewed!.display, isNot(contains('private body')));
            await c.adopt(c.reviewed!);
            expect(c.record!.origin, LabelCreationOrigin.manualExisting);
          } else {
            expect(c.hasKnownAcknowledgement, isTrue);
            failAck = false;
            await c.retryAcknowledgement();
            expect(
              c.record!.origin,
              LabelCreationOrigin.localTransactionAcknowledgement,
            );
          }
          expect(calls, 1);
          expect(
            LabelCreationAttempt.decode(values.values.single).origin,
            c.record!.origin,
          );
          await c.end(c.record!);
          expect(values, isEmpty);
          expect(await db.query('local_labels'), hasLength(1));
        } finally {
          c.dispose();
          await local.close();
        }
      },
    );
  }
  test(
    'held durable claim retired before completion never starts actual SQL',
    () async {
      final local = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      var current = true, flushes = 0, calls = 0;
      final held = Completer<void>(),
          entered = Completer<void>(),
          values = <String, String>{};
      final repo = LocalLabelManagementRepository(
        local,
        isCurrent: () => current,
      );
      final journal = LocalLabelCreationStore(
        scope: '3' * 64,
        key: '3' * 32,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        isCurrent: () => current,
        flush: () async {
          flushes++;
          if (flushes == 2) {
            entered.complete();
            await held.future;
          }
        },
      );
      final reader = LocalLabelCreationMetadataReader(
        store: local,
        isCurrent: () => current,
      );
      final c = LocalLabelCreationController(
        store: journal,
        create: (name) async {
          calls++;
          return repo.createLocalTransaction(name);
        },
        inspect: reader.inspect,
      );
      try {
        await c.begin(
          LabelCreationAttempt(
            scope: journal.scope,
            key: journal.key,
            body: {'label_name': 'Exact'},
          ),
        );
        final submit = c.submit();
        await entered.future;
        current = false;
        held.complete();
        await submit;
        expect(calls, 0);
        expect(await (await local.database).query('local_labels'), isEmpty);
        expect(
          LabelCreationAttempt.decode(values.values.single).phase,
          LabelCreationPhase.unknown,
        );
      } finally {
        if (!held.isCompleted) held.complete();
        c.dispose();
        await local.close();
      }
    },
  );
  test(
    'metadata bound rejects complete review without reading or changing large source body',
    () async {
      final local = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      final repo = LocalLabelManagementRepository(local);
      try {
        final label = await repo.createLocalTransaction('Exact');
        final source = await local.createNote(
          'private',
          '\ufeff${'😀\r\n' * 300000}',
          labels: ['Exact'],
        );
        final db = await local.database;
        final before = (await db.rawQuery(
          'SELECT length(CAST(content AS BLOB)) AS n FROM notes WHERE id=?',
          [source],
        )).single['n'];
        final reader = LocalLabelCreationMetadataReader(
          store: local,
          isCurrent: () => true,
        );
        final attempt = LabelCreationAttempt(
          scope: '4' * 64,
          key: '4' * 32,
          body: {'label_name': 'Exact'},
        );
        final actual = await reader.inspect(attempt, label.id);
        expect(actual.wire['relation_count'], 1);
        expect(actual.display, isNot(contains('private')));
        await db.update(
          'notes',
          {
            'labels': jsonEncode(['Exact', 'x' * 65536]),
          },
          where: 'id=?',
          whereArgs: [source],
        );
        await expectLater(
          reader.inspect(attempt, label.id),
          throwsFormatException,
        );
        expect(
          (await db.rawQuery(
            'SELECT length(CAST(content AS BLOB)) AS n FROM notes WHERE id=?',
            [source],
          )).single['n'],
          before,
        );
      } finally {
        await local.close();
      }
    },
  );
}
