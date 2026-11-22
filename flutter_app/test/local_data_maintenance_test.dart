import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';

void main() {
  test(
    'exclusive identity expires and differs for every new operation',
    () async {
      final gate = LocalDataMaintenance();
      final other = LocalDataMaintenance();
      Object? previous;
      final later = Completer<void>();
      late Future<Object?> stale;
      expect(gate.exclusiveIdentity, isNull);
      await gate.use(() => expect(gate.exclusiveIdentity, isNull));
      await gate.exclusive(() async {
        previous = gate.exclusiveIdentity;
        expect(previous, isNotNull);
        await gate.use(() async {
          expect(identical(gate.exclusiveIdentity, previous), isTrue);
          await other.exclusive(() {
            expect(identical(gate.exclusiveIdentity, previous), isTrue);
            expect(identical(other.exclusiveIdentity, previous), isFalse);
          });
        });
        stale = later.future.then((_) => gate.exclusiveIdentity);
      });
      later.complete();
      expect(await stale, isNull);
      expect(gate.exclusiveIdentity, isNull);
      await gate.exclusive(() {
        expect(gate.exclusiveIdentity, isNotNull);
        expect(identical(gate.exclusiveIdentity, previous), isFalse);
        gate.retire();
        expect(gate.exclusiveIdentity, isNull);
      });
    },
  );

  test(
    'maintenance waits for all overlapping SQL and blob operations',
    () async {
      final gate = LocalDataMaintenance();
      final sqlStarted = Completer<void>(), blobStarted = Completer<void>();
      final sqlDone = Completer<void>(), blobDone = Completer<void>();
      final events = <String>[];
      final sql = gate.use(() async {
        sqlStarted.complete();
        await sqlDone.future;
        events.add('sql');
      });
      final blob = gate.use(() async {
        blobStarted.complete();
        await blobDone.future;
        events.add('blob');
      });
      await Future.wait([sqlStarted.future, blobStarted.future]);
      final backup = gate.exclusive(() => events.add('backup'));
      expect(gate.maintenanceRequested, isTrue);
      sqlDone.complete();
      await sql;
      expect(events, ['sql']);
      blobDone.complete();
      await Future.wait([blob, backup]);
      expect(events, ['sql', 'blob', 'backup']);
      expect(gate.maintenanceRequested, isFalse);
    },
  );

  test('queued backup prevents later writers overtaking it', () async {
    final gate = LocalDataMaintenance();
    final started = Completer<void>(), release = Completer<void>();
    final events = <String>[];
    final first = gate.use(() async {
      started.complete();
      await release.future;
    });
    await started.future;
    final backup = gate.exclusive(() => events.add('backup'));
    final writer = gate.use(() => events.add('writer'));
    final nextBackup = gate.exclusive(() => events.add('next-backup'));
    final nextWriter = gate.use(() => events.add('next-writer'));
    release.complete();
    await Future.wait([first, backup, writer, nextBackup, nextWriter]);
    expect(events, ['backup', 'writer', 'next-backup', 'next-writer']);
  });

  test('nested repositories reenter while backup is already queued', () async {
    final gate = LocalDataMaintenance();
    final started = Completer<void>(), nest = Completer<void>();
    final events = <String>[];
    final writer = gate.use(() async {
      started.complete();
      await nest.future;
      await gate.use(() => events.add('nested-blob'));
      events.add('transaction');
    });
    await started.future;
    final backup = gate.exclusive(() => events.add('backup'));
    nest.complete();
    await Future.wait([writer, backup]);
    expect(events, ['nested-blob', 'transaction', 'backup']);
  });

  test(
    'shared-to-exclusive upgrade fails without deadlocking later work',
    () async {
      final gate = LocalDataMaintenance();
      var invoked = false;
      await expectLater(
        gate.use(() => gate.exclusive(() => invoked = true)),
        throwsStateError,
      );
      expect(invoked, isFalse);
      expect(await gate.exclusive(() => 42), 42);
    },
  );

  test('exclusive operation may reenter SQL and exclusive helpers', () async {
    final gate = LocalDataMaintenance();
    await gate.exclusive(() async {
      expect(gate.maintenanceActive, isTrue);
      expect(
        await gate.use(() => gate.exclusive(() => 'snapshot')),
        'snapshot',
      );
      expect(gate.maintenanceActive, isTrue);
    });
    expect(gate.maintenanceActive, isFalse);
  });

  test('exceptions release shared and maintenance leases', () async {
    final gate = LocalDataMaintenance();
    await expectLater(
      gate.use(() => throw StateError('blob')),
      throwsStateError,
    );
    await expectLater(
      gate.exclusive(() async => throw StateError('snapshot')),
      throwsStateError,
    );
    expect(await gate.use(() => 'still writable'), 'still writable');
    expect(gate.maintenanceRequested, isFalse);
  });

  test('started unawaited nested file operation retains its lease', () async {
    final gate = LocalDataMaintenance();
    final entered = Completer<void>(), release = Completer<void>();
    final events = <String>[];
    late Future<void> child;
    await gate.use(() async {
      child = gate.use(() async {
        entered.complete();
        await release.future;
        events.add('file-published');
      });
      await entered.future;
    });
    final backup = gate.exclusive(() => events.add('backup'));
    expect(events, isEmpty);
    release.complete();
    await Future.wait([child, backup]);
    expect(events, ['file-published', 'backup']);
  });

  test(
    'inherited async context reacquires after its original lease ended',
    () async {
      final gate = LocalDataMaintenance();
      final later = Completer<void>(), entered = Completer<void>();
      final maintenanceStarted = Completer<void>(),
          maintenanceDone = Completer<void>();
      late Future<void> delayed;
      await gate.use(() {
        delayed = later.future.then((_) => gate.use(() => entered.complete()));
      });
      final backup = gate.exclusive(() async {
        maintenanceStarted.complete();
        await maintenanceDone.future;
      });
      await maintenanceStarted.future;
      later.complete();
      await Future<void>.value();
      expect(entered.isCompleted, isFalse);
      maintenanceDone.complete();
      await Future.wait([backup, delayed]);
      expect(entered.isCompleted, isTrue);
    },
  );

  test(
    'same identity shares gate; unrelated stores remain independent',
    () async {
      final a = LocalDataMaintenance.forStorage('owned-a');
      expect(identical(a, LocalDataMaintenance.forStorage('owned-a')), isTrue);
      final b = LocalDataMaintenance.forStorage('owned-b');
      final started = Completer<void>(), release = Completer<void>();
      final maintenance = a.exclusive(() async {
        started.complete();
        await release.future;
      });
      await started.future;
      expect(await b.use(() => 'independent'), 'independent');
      release.complete();
      await maintenance;
    },
  );
  test('nested different stores preserve the first store lease', () async {
    final a = LocalDataMaintenance(), b = LocalDataMaintenance();
    final entered = Completer<void>(), proceed = Completer<void>();
    final events = <String>[];
    final writer = a.use(() async {
      entered.complete();
      await proceed.future;
      await b.use(() => a.use(() => events.add('nested-a')));
    });
    await entered.future;
    final backup = a.exclusive(() => events.add('backup'));
    proceed.complete();
    await Future.wait([writer, backup]).timeout(const Duration(seconds: 1));
    expect(events, ['nested-a', 'backup']);
  });
  test(
    'retired generation rejects queued and later writers without invoking them',
    () async {
      final gate = LocalDataMaintenance();
      final entered = Completer<void>(), release = Completer<void>();
      var invoked = false;
      final activation = gate.exclusive(() async {
        entered.complete();
        await release.future;
        gate.retire();
      });
      await entered.future;
      final queued = gate.use(() => invoked = true);
      final rejected = expectLater(queued, throwsA(isA<LocalStorageRetired>()));
      release.complete();
      await Future.wait([activation, rejected]);
      await expectLater(
        gate.use(() => invoked = true),
        throwsA(isA<LocalStorageRetired>()),
      );
      await expectLater(
        gate.exclusive(() => invoked = true),
        throwsA(isA<LocalStorageRetired>()),
      );
      expect(invoked, isFalse);
      expect(gate.retired, isTrue);
    },
  );

  test('retirement cannot bypass an active normal operation', () async {
    final gate = LocalDataMaintenance();
    expect(gate.retire, throwsStateError);
    await gate.use(() => expect(gate.retire, throwsStateError));
    expect(gate.retired, isFalse);
    expect(await gate.use(() => 42), 42);
  });

  test(
    'started nested operation must finish before generation retirement',
    () async {
      final gate = LocalDataMaintenance();
      final entered = Completer<void>(), release = Completer<void>();
      await gate.exclusive(() async {
        final child = gate.use(() async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        expect(gate.retire, throwsStateError);
        release.complete();
        await child;
        gate.retire();
      });
      expect(gate.retired, isTrue);
    },
  );
}
