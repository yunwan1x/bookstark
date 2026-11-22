import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';

void main() {
  test(
    'retirement awaits its owner exactly once and cannot bind another body',
    () async {
      final controller = OwnedPreviewController(),
          owner = Object(),
          gate = Completer<void>();
      var calls = 0, done = false;
      controller.bind(owner, () {
        calls++;
        return gate.future;
      });
      expect(() => controller.bind(Object(), () async {}), throwsStateError);
      final closed = controller.retire()..then((_) => done = true);
      expect(controller.retired, isTrue);
      expect(calls, 1);
      expect(done, isFalse);
      expect(identical(controller.retire(), closed), isTrue);
      gate.complete();
      await closed;
      expect(done, isTrue);
      controller.unbind(owner);
      controller.bind(Object(), () async {
        calls++;
      });
      await controller.retire();
      expect(calls, 1);
      controller.dispose();
    },
  );
  test(
    'observed native close awaits full barrier without recursive close',
    () async {
      final controller = OwnedPreviewController(),
          owner = Object(),
          native = Completer<void>();
      var calls = 0;
      controller.bind(owner, () async {
        calls++;
      });
      controller.ownerRetiring(Object(), Future<void>.value());
      expect(controller.retired, isFalse);
      controller.ownerRetiring(owner, native.future);
      var done = false;
      final closed = controller.retire()..then((_) => done = true);
      expect(calls, 0);
      expect(done, isFalse);
      native.complete();
      await closed;
      expect(done, isTrue);
      controller.dispose();
    },
  );
  test(
    'a failed owned close stays retired and can be explicitly retried',
    () async {
      final controller = OwnedPreviewController(), owner = Object();
      var calls = 0;
      controller.bind(owner, () async {
        if (++calls == 1) throw StateError('native close failed');
      });
      await expectLater(controller.retire(), throwsStateError);
      expect(controller.retired, isTrue);
      await controller.retire();
      expect(calls, 2);
      controller.dispose();
    },
  );
  test(
    'unbind closes old owner without affecting a newer independent controller',
    () async {
      final old = OwnedPreviewController(),
          next = OwnedPreviewController(),
          owner = Object(),
          gate = Completer<void>();
      var oldCalls = 0, nextCalls = 0;
      old.bind(owner, () {
        oldCalls++;
        return gate.future;
      });
      next.bind(Object(), () async {
        nextCalls++;
      });
      old.unbind(owner);
      expect(oldCalls, 1);
      expect(nextCalls, 0);
      gate.complete();
      await old.retire();
      expect(next.retired, isFalse);
      old.dispose();
      await next.retire();
      next.dispose();
    },
  );
  test('retirement before attachment never creates a runtime', () async {
    final controller = OwnedPreviewController();
    var calls = 0;
    await controller.retire();
    controller.bind(Object(), () async {
      calls++;
    });
    await controller.retire();
    expect(calls, 0);
    controller.dispose();
  });
}
