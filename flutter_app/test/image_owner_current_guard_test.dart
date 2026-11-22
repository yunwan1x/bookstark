import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/images/image_library_owner.dart';

void main() {
  test('initial false/throwing scope performs zero repository work', () async {
    var calls = 0;
    for (final guard in <bool Function()>[
      () => false,
      () => throw StateError('retired'),
    ]) {
      final owner = ImageLibraryOwner(isCurrentScope: guard);
      await expectLater(
        owner.run(() async {
          calls++;
          return 1;
        }),
        throwsStateError,
      );
      await owner.retireAndDrain();
    }
    expect(calls, 0);
  });
  test(
    'retire blocks new work and drains actual commit before identity advance',
    () async {
      var current = true,
          drained = 0,
          newWork = 0,
          oldCommit = false,
          advanced = false;
      final work = Completer<int>();
      final owner = ImageLibraryOwner(
        isCurrentScope: () => current,
        onDrained: () {
          drained++;
        },
      );
      final old = owner.run(() async {
        final value = await work.future;
        oldCommit = true;
        return value;
      });
      final oldExpectation = expectLater(old, throwsStateError);
      current = false;
      final transition = owner.retireAndDrain().then((_) {
        expect(oldCommit, isTrue);
        advanced = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(advanced, isFalse);
      await expectLater(
        owner.run(() async {
          newWork++;
          return 2;
        }),
        throwsStateError,
      );
      work.complete(1);
      await oldExpectation;
      await transition;
      await owner.retireAndDrain();
      expect(advanced, isTrue);
      expect(newWork, 0);
      expect(drained, 1);
    },
  );
}
