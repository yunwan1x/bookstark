import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';

void main() {
  var sequence = 0;
  Map<String, Object?> state({String? pointer, String? retention}) => {
    'format': 1,
    'pointerRaw': pointer,
    'intentRaw': null,
    'currentRetentionRaw': retention,
    'sourceRetentionRaw': null,
    'metadataOnly': true,
  };
  LocalStorageSession session(NativeLocalDataControl control, String id) =>
      LocalStorageSession(
        control: control,
        privateSupport: Directory('/private/session-$id'),
        legacyDatabasePath: '/private/session-$id/db/content.db',
        factory: databaseFactoryFfiNoIsolate,
      );

  test(
    'cold ready resolver uses exact legacy path without opening SQL',
    () async {
      final service = session(
        NativeLocalDataControl(invoke: (_, _) async => state()),
        'legacy',
      );
      final store = await service.open();
      expect(store.path, '/private/session-legacy/db/content.db');
      expect(store.dataPaths!.generationId, isNull);
      expect(await Directory('/private/session-legacy').exists(), isFalse);
    },
  );
  test(
    'cold generation pointer selects all resources and namespace together',
    () async {
      final pointer = LocalGenerationPointer(
        generation: 'a' * 32,
        epoch: 1,
        activationId: 'b' * 32,
        sourceSHA256: 'c' * 64,
      ).encode();
      final store = await session(
        NativeLocalDataControl(invoke: (_, _) async => state(pointer: pointer)),
        'generation',
      ).open();
      expect(
        store.path,
        contains('/generations/${'a' * 32}/database/content.db'),
      );
      expect(
        store.dataPaths!.attachments.path,
        contains('/generations/${'a' * 32}/attachments'),
      );
      expect(store.dataPaths!.draftNamespace, 'local-generation:${'a' * 32}');
    },
  );
  test(
    'retained or unavailable native state refuses before any database access',
    () async {
      final lock = LocalRetention(
        id: 'b' * 32,
        sourcePointerSHA256: localPointerSHA256(null),
        sourceGeneration: 'legacy',
        manifestSHA256: 'c' * 64,
      );
      await expectLater(
        session(
          NativeLocalDataControl(
            invoke: (_, _) async => state(retention: lock.encode()),
          ),
          'retained',
        ).open(),
        throwsA(isA<LocalDataNeedsReview>()),
      );
      await expectLater(
        session(
          NativeLocalDataControl(
            invoke: (_, _) async => throw StateError('Unavailable'),
          ),
          'unavailable',
        ).open(),
        throwsStateError,
      );
    },
  );
  test('only explicit bound durable reentry replaces retired gate', () async {
    final id = 'reentry-${sequence++}';
    var locked = false;
    final lock = LocalRetention(
      id: 'b' * 32,
      sourcePointerSHA256: localPointerSHA256(null),
      sourceGeneration: 'legacy',
      manifestSHA256: 'c' * 64,
    );
    final control = NativeLocalDataControl(
      invoke: (method, args) async {
        if (method == 'readState') {
          return state(retention: locked ? lock.encode() : null);
        }
        if (method == 'reenterUnchangedSource') {
          locked = false;
          return {
            'format': 1,
            'action': 'reentered',
            'id': lock.id,
            'durable': true,
            'state': state(),
          };
        }
        throw StateError('Unexpected mutation');
      },
    );
    final service = session(control, id);
    final old = await service.open();
    await old.maintenance.exclusive(old.maintenance.retire);
    await expectLater(service.open(), throwsA(isA<LocalStorageRetired>()));
    locked = true;
    final reviewed = await control.readState();
    final receipt = await control.reenterUnchangedSource(reviewed);
    final fresh = await service.open(sourceReentry: receipt);
    expect(identical(fresh.maintenance, old.maintenance), isFalse);
    expect(fresh.maintenance.retired, isFalse);
    await expectLater(
      old.maintenance.use(() => 1),
      throwsA(isA<LocalStorageRetired>()),
    );
    expect(await fresh.maintenance.use(() => 2), 2);
    await fresh.maintenance.exclusive(fresh.maintenance.retire);
    await expectLater(
      service.open(sourceReentry: receipt),
      throwsA(isA<LocalStorageRetired>()),
    );
  });
}
