import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_recovery_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeRecoveryStorage.channel, null);
  });
  test(
    'Android barrier takes no credential values and waits for native completion',
    () async {
      final gate = Completer<bool>();
      var finished = false;
      MethodCall? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeRecoveryStorage.channel, (
            call,
          ) async {
            request = call;
            return gate.future;
          });
      final future = NativeRecoveryStorage.flush().then((_) {
        finished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(request!.method, 'flush');
      expect(request!.arguments, isNull);
      expect(finished, false);
      gate.complete(true);
      await future;
      expect(finished, true);
    },
  );
  test('missing or negative native confirmation fails closed', () async {
    for (final value in [false, null]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeRecoveryStorage.channel,
            (_) async => value,
          );
      await expectLater(NativeRecoveryStorage.flush(), throwsStateError);
    }
  });
  test('native I/O failure propagates rather than allowing mutation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeRecoveryStorage.channel,
          (_) async => throw PlatformException(code: 'recovery_sync_failed'),
        );
    await expectLater(
      NativeRecoveryStorage.flush(),
      throwsA(isA<PlatformException>()),
    );
  });
  test(
    'other platforms do not invoke an Android preferences barrier',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeRecoveryStorage.channel, (_) async {
            calls++;
            return true;
          });
      await NativeRecoveryStorage.flush();
      expect(calls, 0);
    },
  );
}
