import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_migration_page.dart';

void main() {
  test('retirement seals immediately and joins actual close once', () async {
    final owner = LocalLegacyInspectionLifetime();
    final release = Completer<void>();
    var closes = 0;
    owner.bind(() async {
      closes++;
      await release.future;
    });
    final first = owner.retire(), second = owner.retire();
    expect(owner.current, isFalse);
    expect(identical(first, second), isTrue);
    var finished = false;
    first.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
    expect(finished, isFalse);
    release.complete();
    await first;
    expect(finished, isTrue);
    await owner.retire();
    expect(closes, 1);
  });
  test(
    'close failure remains sealed and explicit retry joins real cleanup',
    () async {
      final owner = LocalLegacyInspectionLifetime();
      var closes = 0;
      owner.bind(() async {
        if (++closes == 1) throw StateError('owned cleanup failed');
      });
      await expectLater(owner.retire(), throwsStateError);
      expect(owner.current, isFalse);
      await owner.retire();
      expect(closes, 2);
      await owner.retire();
      expect(closes, 2);
    },
  );
  test('close callback reentry observes published retirement future', () async {
    final owner = LocalLegacyInspectionLifetime();
    Future<void>? observed;
    owner.bind(() async {
      observed = owner.retire();
    });
    final closing = owner.retire();
    await closing;
    expect(identical(closing, observed), isTrue);
  });
}
