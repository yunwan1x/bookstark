import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_recovery_storage.dart';
import 'package:bookstark_flutter/core/protected_shared_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shared journal uses actual Android localMetadata keys-only contract',
    () async {
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, (
        call,
      ) async {
        calls.add(call.method);
        // RecoveryStorageChannel.kt accepts localMetadata, never metadata.
        if (call.method != 'localMetadata' || call.arguments != null) {
          throw MissingPluginException('Unsupported recovery method');
        }
        return <String, Object>{
          'format': 1,
          'secureKeys': <String>[
            'bookstark.protectedSharedOp.v1.owned-fixture',
            'bookstark.draft.v1.unrelated-fixture',
          ],
          'htmlKeys': <String>[],
          'overflow': false,
          'valuesIncluded': false,
        };
      });
      try {
        final keys = await nativeProtectedSharedKeys();
        expect(keys, <String>['bookstark.protectedSharedOp.v1.owned-fixture']);
        expect(calls, <String>['localMetadata']);
      } finally {
        messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, null);
      }
    },
  );
}
