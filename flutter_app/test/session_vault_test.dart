import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/session_vault.dart';

void main() {
  test('logout clear is serialized after an in-flight session write', () async {
    String? stored = 'previous';
    final gate = Completer<void>(), events = <String>[];
    final vault = SessionVault(
      readValue: () async => stored,
      writeValue: (value) async {
        events.add('write-start');
        await gate.future;
        stored = value;
        events.add('write-finish');
      },
      deleteValue: () async {
        stored = null;
        events.add('clear');
      },
    );
    final saving = vault.save('fixture-session', stillCurrent: () => true);
    await Future<void>.delayed(Duration.zero);
    final clearing = vault.clear();
    expect(events, ['write-start']);
    gate.complete();
    await saving;
    await clearing;
    expect(stored, isNull);
    expect(events, ['write-start', 'write-finish', 'clear']);
  });
  test(
    'a queued stale login cannot overwrite a newer space generation',
    () async {
      final gate = Completer<void>();
      var current = true, writes = 0;
      String? stored;
      final vault = SessionVault(
        readValue: () async {
          await gate.future;
          return stored;
        },
        writeValue: (value) async {
          writes++;
          stored = value;
        },
        deleteValue: () async {
          stored = null;
        },
      );
      final reading = vault.read();
      final stale = vault.save('stale-fixture', stillCurrent: () => current);
      current = false;
      gate.complete();
      await reading;
      expect(await stale, isFalse);
      expect(writes, 0);
      expect(stored, isNull);
    },
  );
  test(
    'failed storage operation does not poison a later clear or fresh save',
    () async {
      var fail = true;
      String? stored = 'prior';
      final vault = SessionVault(
        readValue: () async => stored,
        writeValue: (value) async {
          if (fail) {
            throw StateError('storage unavailable');
          }
          stored = value;
        },
        deleteValue: () async {
          stored = null;
        },
      );
      await expectLater(
        vault.save('first', stillCurrent: () => true),
        throwsStateError,
      );
      await vault.clear();
      expect(stored, isNull);
      fail = false;
      expect(await vault.save('fresh', stillCurrent: () => true), isTrue);
      expect(await vault.read(), 'fresh');
    },
  );
}
