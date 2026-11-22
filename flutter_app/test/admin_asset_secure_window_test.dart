import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'nested routes use independent random leases and release only their own',
    () async {
      final parent = AdminAssetSecureWindow(), child = AdminAssetSecureWindow();
      await parent.acquire();
      await child.acquire();
      final p = calls[0].arguments['lease'], c = calls[1].arguments['lease'];
      expect(p, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(p, isNot(c));
      await child.close();
      expect(calls.last.method, 'release');
      expect(calls.last.arguments['lease'], c);
      expect(calls.where((e) => e.method == 'release').length, 1);
      await parent.close();
      expect(calls.last.arguments['lease'], p);
    },
  );
  test('repeated acquire is single flight and close is idempotent', () async {
    final lease = AdminAssetSecureWindow();
    await Future.wait([lease.acquire(), lease.acquire()]);
    expect(calls, hasLength(1));
    await lease.close();
    await lease.close();
    expect(calls, hasLength(2));
    await expectLater(lease.acquire(), throwsStateError);
    expect(calls, hasLength(2));
  });
  test(
    'closing while acquisition pending releases exact ID and never exposes readiness',
    () async {
      final gate = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'acquire') return gate.future;
        return true;
      });
      final lease = AdminAssetSecureWindow();
      final acquiring = expectLater(lease.acquire(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await lease.close();
      expect(calls.map((c) => c.method), ['acquire', 'release']);
      expect(calls[0].arguments, calls[1].arguments);
      gate.complete(true);
      await acquiring;
    },
  );
  test('native refusal releases tentative lease and fails closed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method != 'acquire';
    });
    final lease = AdminAssetSecureWindow();
    await expectLater(lease.acquire(), throwsStateError);
    expect(calls.map((c) => c.method), ['acquire', 'release']);
  });
  test('unsupported platform never claims screenshot protection', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final lease = AdminAssetSecureWindow();
    await expectLater(lease.acquire(), throwsUnsupportedError);
    expect(calls, isEmpty);
    await lease.close();
  });
}
