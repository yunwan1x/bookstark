import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/core/protected_shared_lifetime.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';

void main() {
  test(
    'scope retirement revokes immediately and drains child native close before Root unregister',
    () async {
      final gate = Completer<void>(), entered = Completer<void>();
      var drained = 0;
      final transport = AnonymousSharedCapability(
        PublicEditLink.parse(
          Uri.parse('https://owner.test'),
          'https://owner.test/shares/one?token=${'a' * 64}',
        ),
        isCurrent: () => true,
        anonymousTestClient: () =>
            MockClient((_) async => throw StateError('No request expected')),
      );
      final owner = ProtectedSharedLifetime(
        transport: transport,
        isCurrentScope: () => true,
        onDrained: (_) {
          drained++;
        },
      );
      final preview = OwnedPreviewController();
      preview.bind(Object(), () async {
        entered.complete();
        await gate.future;
      });
      owner.registerPreview(preview);
      final closing = owner.retire();
      expect(owner.current, isFalse);
      await entered.future;
      expect(drained, 0);
      gate.complete();
      await closing;
      expect(drained, 1);
      await owner.retire();
      expect(drained, 1);
      preview.dispose();
    },
  );
  test(
    'failed native retirement keeps Root owner registered and supports retry',
    () async {
      var attempts = 0, drained = 0;
      final transport = AnonymousSharedCapability(
        PublicEditLink.parse(
          Uri.parse('https://owner.test'),
          'https://owner.test/shares/two?token=${'b' * 64}',
        ),
        isCurrent: () => true,
        anonymousTestClient: () =>
            MockClient((_) async => throw StateError('No request expected')),
      );
      final owner = ProtectedSharedLifetime(
        transport: transport,
        isCurrentScope: () => true,
        onDrained: (_) {
          drained++;
        },
      );
      final preview = OwnedPreviewController();
      preview.bind(Object(), () async {
        if (++attempts == 1) throw StateError('Native close unknown');
      });
      owner.registerPreview(preview);
      await expectLater(owner.retire(), throwsStateError);
      expect(drained, 0);
      expect(owner.current, isFalse);
      await owner.retire();
      expect(attempts, 2);
      expect(drained, 1);
      preview.dispose();
    },
  );
}
