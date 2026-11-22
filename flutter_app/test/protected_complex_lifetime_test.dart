import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_complex_lifetime.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';

String hex(String c) => List.filled(64, c).join();
void main() {
  test(
    'retirement revokes immediately but joins started secure claim before barrier',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final values = <String, String>{};
      var drained = false;
      final journal = ProtectedOwnedComplexJournal(
        scope: hex('a'),
        ownerTag: hex('b'),
        isCurrent: () => true,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
          entered.complete();
          await release.future;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
        flush: () async {},
      );
      final owner = ProtectedComplexLifetime(
        journal: journal,
        isCurrentScope: () => true,
        onDrained: (_) {
          drained = true;
        },
      );
      final claim = journal.claimUnknown(
        baselineFingerprint: hex('c'),
        inputDigest: hex('d'),
      );
      final rejected = expectLater(claim, throwsStateError);
      await entered.future;
      final close = owner.retire();
      expect(owner.current, false);
      expect(drained, false);
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      release.complete();
      await rejected;
      await close;
      expect(drained, true);
      expect(values.length, 1);
      // A partial claim remains metadata blocking, but did not authorize any PUT.
    },
  );
}
