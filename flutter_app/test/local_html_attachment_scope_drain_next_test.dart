import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';

void main() {
  test('native epoch is revoked before held IO; transition awaits actual drain', () async {
    var nativeRetired = false, retireCalls = 0, transitioned = false;
    final started = Completer<void>(), gate = Completer<void>();
    final owner = await ComplexSourceIoScope.activate(
      scope: 'a' * 64, isCurrent: () => true,
      invoke: (method, args) async {
        if (method == 'scopeState') return {'epoch': 0};
        if (method == 'activateScope') return {'epoch': 1};
        if (method == 'retireScope') {
          retireCalls++; nativeRetired = true;
          return {'retired': true};
        }
        throw StateError('Unexpected native request');
      });
    owner.addRetirementDrain(() async {
      if (!nativeRetired) throw StateError('IO drained before Native revoke');
      started.complete();
      await gate.future;
    });
    final transition = () async {
      await owner.retire();
      transitioned = true;
    }();
    await started.future;
    expect(nativeRetired, isTrue);
    expect(transitioned, isFalse);
    expect(owner.guard, throwsStateError);
    final concurrent = owner.retire();
    expect(retireCalls, 1);
    gate.complete();
    await Future.wait([transition, concurrent]);
    expect(transitioned, isTrue);
    expect(retireCalls, 1);
  });

  test('failed drain is retryable without repeating native old-epoch CAS', () async {
    var retireCalls = 0, fail = true;
    final owner = await ComplexSourceIoScope.activate(
      scope: 'b' * 64, isCurrent: () => true,
      invoke: (method, args) async {
        if (method == 'scopeState') return {'epoch': 3};
        if (method == 'activateScope') return {'epoch': 4};
        if (method == 'retireScope') { retireCalls++; return {'retired': true}; }
        throw StateError('Unexpected native request');
      });
    owner.addRetirementDrain(() async {
      if (fail) throw StateError('Held file close failed');
    });
    await expectLater(owner.retire(), throwsStateError);
    expect(owner.guard, throwsStateError);
    fail = false;
    await owner.retire();
    expect(retireCalls, 1);
    expect(() => owner.addRetirementDrain(() async {}), throwsStateError);
  });
}
