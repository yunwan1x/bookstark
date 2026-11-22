import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_recovery_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final key =
      'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode([
        jsonEncode(['local', 'article']),
        17,
      ])))}';
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, null);
  });

  test(
    'fingerprint channel carries a bounded identifier and metadata only',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, (
        call,
      ) async {
        calls.add(call);
        return {
          'format': 1,
          'key': key,
          'sha256': 'a' * 64,
          'ciphertextBytes': 812,
          'valuesIncluded': false,
        };
      });
      expect(
        await NativeRecoveryStorage.localArticleDraftFingerprint(key),
        'a' * 64,
      );
      expect(calls.single.method, 'localArticleDraftFingerprint');
      expect(calls.single.arguments, {'key': key});
    },
  );

  test(
    'account, remote and ordinary-note keys are refused before invoking native',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, (
        _,
      ) async {
        calls++;
        return null;
      });
      for (final invalid in [
        'token',
        'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode(['local', 17])))}',
        'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode([
          jsonEncode(['https://server.test', 'article']),
          17,
        ])))}',
      ]) {
        await expectLater(
          NativeRecoveryStorage.localArticleDraftFingerprint(invalid),
          throwsFormatException,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'missing is explicit; mismatched, unbounded and body-bearing responses fail closed',
    () async {
      Map<String, Object?> reply = {
        'format': 1,
        'key': key,
        'sha256': null,
        'ciphertextBytes': 0,
        'valuesIncluded': false,
      };
      messenger.setMockMethodCallHandler(
        NativeRecoveryStorage.channel,
        (_) async => reply,
      );
      expect(
        await NativeRecoveryStorage.localArticleDraftFingerprint(key),
        isNull,
      );
      for (final bad in <Map<String, Object?>>[
        {...reply, 'key': 'other'},
        {...reply, 'format': 1.0},
        {...reply, 'sha256': 'a' * 64},
        {...reply, 'ciphertextBytes': -1},
        {...reply, 'ciphertextBytes': 32 * 1024 * 1024 + 1},
        {...reply, 'valuesIncluded': true},
        {...reply, 'value': 'forbidden'},
      ]) {
        reply = bad;
        await expectLater(
          NativeRecoveryStorage.localArticleDraftFingerprint(key),
          throwsFormatException,
        );
      }
    },
  );
}
