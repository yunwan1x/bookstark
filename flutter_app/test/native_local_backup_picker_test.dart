import 'dart:async';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_local_backup_picker.dart';

void main() {
  final id = 'a' * 32;
  Map<String, Object?> receipt() => {
    'format': 1,
    'cancelled': false,
    'id': id,
    'bytes': 120,
    'sha256': 'b' * 64,
  };
  test(
    'successful receipt is bound and release uses only opaque identity',
    () async {
      final calls = <String>[];
      final picker = NativeLocalBackupPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          return method == 'pick' ? receipt() : {'format': 1, 'released': id};
        },
      );
      final picked = (await picker.pick())!;
      expect(picked.bytes, 120);
      expect(picked.sha256, 'b' * 64);
      await picker.release(picked);
      expect(calls, ['pick', 'release']);
    },
  );
  test('cancelled choice produces no input artifact', () async {
    final picker = NativeLocalBackupPicker(
      identity: () => id,
      invoke: (_, _) async => {'format': 1, 'cancelled': true},
    );
    expect(await picker.pick(), isNull);
  });
  test('wrong identity/hash/size/format and extra paths fail closed', () async {
    for (final changes in [
      {'id': 'c' * 32},
      {'sha256': 'invalid'},
      {'bytes': 0},
      {'bytes': 3 * 1024 * 1024 * 1024},
      {'format': 1.0},
      {'path': '/outside'},
      {'bytes': 120.0},
    ]) {
      final picker = NativeLocalBackupPicker(
        identity: () => id,
        invoke: (_, _) async => {...receipt(), ...changes},
      );
      await expectLater(picker.pick(), throwsFormatException);
    }
  });
  test(
    'timeout cancels the same request once without releasing or replaying',
    () async {
      final calls = <String>[];
      final picker = NativeLocalBackupPicker(
        identity: () => id,
        timeout: const Duration(milliseconds: 10),
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          if (method == 'pick') return Completer<Object?>().future;
          return {'format': 1, 'cancelled': true};
        },
      );
      await expectLater(picker.pick(), throwsA(isA<TimeoutException>()));
      expect(calls, ['pick', 'cancel']);
    },
  );
  test(
    'overlapping selection rejected; explicit cancel targets active request',
    () async {
      final pending = Completer<Object?>();
      final calls = <String>[];
      final picker = NativeLocalBackupPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          if (method == 'pick') return await pending.future;
          return <String, Object?>{'format': 1, 'cancelled': true};
        },
      );
      final first = picker.pick();
      await expectLater(picker.pick(), throwsStateError);
      await picker.cancel();
      pending.complete({'format': 1, 'cancelled': true});
      expect(await first, isNull);
      expect(calls, ['pick', 'cancel']);
    },
  );
  test('bad generated identity never invokes native code', () async {
    var called = false;
    final picker = NativeLocalBackupPicker(
      identity: () => '../bad',
      invoke: (_, _) async {
        called = true;
        return null;
      },
    );
    await expectLater(picker.pick(), throwsFormatException);
    expect(called, isFalse);
  });
  test(
    'dispose releases wait immediately and cleans only a late bound receipt',
    () async {
      final native = Completer<Object?>();
      final released = Completer<void>();
      final calls = <String>[];
      final picker = NativeLocalBackupPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          if (method == 'pick') return await native.future;
          if (method == 'release') {
            released.complete();
            return {'format': 1, 'released': id};
          }
          return {'format': 1, 'cancelled': true};
        },
      );
      final waiting = picker.pick();
      final rejected = expectLater(
        waiting,
        throwsA(isA<AttachmentCancelled>()),
      );
      await Future.wait([picker.dispose(), picker.dispose(), rejected]);
      expect(calls, ['pick', 'cancel']);
      native.complete(receipt());
      await released.future;
      expect(calls, ['pick', 'cancel', 'release']);
      await expectLater(picker.pick(), throwsStateError);
    },
  );
  test('disposed owner never cleans a mismatched late receipt', () async {
    final native = Completer<Object?>();
    final calls = <String>[];
    final picker = NativeLocalBackupPicker(
      identity: () => id,
      invoke: (method, args) async {
        calls.add(method);
        if (method == 'pick') return await native.future;
        return {'format': 1, 'cancelled': true};
      },
    );
    final waiting = picker.pick();
    final rejected = expectLater(waiting, throwsA(isA<AttachmentCancelled>()));
    await picker.dispose();
    await rejected;
    native.complete({...receipt(), 'id': 'f' * 32});
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['pick', 'cancel']);
  });
}
