import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_source_io_owner.dart';

class Native {
  int epoch = 0, activations = 0, retirements = 0;
  bool failRetire = false, failActivate = false;
  final calls = <String>[];
  Future<Map<Object?, Object?>?> invoke(
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add(method);
    if (method == 'scopeState') return {'epoch': epoch};
    if (method == 'activateScope') {
      activations++;
      if (failActivate) throw PlatformException(code: 'stale_epoch');
      if (args['expectedEpoch'] != epoch) throw StateError('CAS');
      return {'epoch': ++epoch};
    }
    if (method == 'retireScope') {
      retirements++;
      if (failRetire) {
        throw MissingPluginException('simulated lost channel after activation');
      }
      epoch++;
      return {'retired': true};
    }
    throw StateError('Unknown method');
  }
}

void main() {
  test(
    'non-Android/Web/host is explicitly unsupported and navigation never invokes plugin',
    () async {
      final n = Native(),
          owner = ComplexSourceIoOwner(
            nativeSupported: false,
            invoke: n.invoke,
          );
      expect(
        await owner.ensure(identity: 'local-one', isCurrent: () => true),
        isNull,
      );
      await owner.beforeTransition();
      owner.assertTransitionAllowed();
      expect(n.calls, isEmpty);
    },
  );
  test(
    'confirmed epoch retirement failure remains blocking even for MissingPlugin',
    () async {
      final n = Native(),
          owner = ComplexSourceIoOwner(nativeSupported: true, invoke: n.invoke);
      await owner.ensure(identity: 'one', isCurrent: () => true);
      n.failRetire = true;
      await expectLater(
        owner.beforeTransition(),
        throwsA(isA<MissingPluginException>()),
      );
      expect(owner.blocked, true);
      expect(owner.current, isNull);
      expect(owner.assertTransitionAllowed, throwsStateError);
      await expectLater(
        owner.ensure(identity: 'two', isCurrent: () => true),
        throwsStateError,
      );
      expect(n.activations, 1);
      n.failRetire = false;
      await owner.beforeTransition();
      owner.assertTransitionAllowed();
      await owner.ensure(identity: 'two', isCurrent: () => true);
      expect(n.activations, 2);
      await owner.close();
    },
  );
  test(
    'same Root owner and picker resume do not reactivate native epoch',
    () async {
      final n = Native(),
          owner = ComplexSourceIoOwner(nativeSupported: true, invoke: n.invoke);
      final first = await owner.ensure(identity: 'one', isCurrent: () => true);
      final resumed = await owner.ensure(
        identity: 'one',
        isCurrent: () => true,
      );
      expect(identical(first, resumed), true);
      expect(n.activations, 1);
      await owner.close();
    },
  );
  test(
    'stale activation CAS is not auto retried or treated as unsupported',
    () async {
      final n = Native()..failActivate = true;
      final owner = ComplexSourceIoOwner(
        nativeSupported: true,
        invoke: n.invoke,
      );
      await expectLater(
        owner.ensure(identity: 'one', isCurrent: () => true),
        throwsA(isA<PlatformException>()),
      );
      expect(n.activations, 1);
      expect(owner.blocked, true);
      await expectLater(
        owner.ensure(identity: 'two', isCurrent: () => true),
        throwsStateError,
      );
      expect(n.activations, 1);
      n.failActivate = false;
      await owner.beforeTransition();
      expect(n.retirements, 1);
      await owner.ensure(identity: 'two', isCurrent: () => true);
      await owner.close();
    },
  );
}
