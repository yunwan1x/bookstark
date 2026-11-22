import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';

class Env {
  Env({Map<String, String>? values}) : values = values ?? {};
  final Map<String, String> values;
  bool current = true,
      failFlush = false,
      failKnown = false,
      failDelete = false,
      failRead = false;
  late final journal = ProtectedOwnedComplexJournal(
    ownerTag: List.filled(64, 'b').join(),
    scope: 'a' * 64,
    isCurrent: () => current,
    readValue: (k) async {
      if (failRead) throw StateError('io');
      return values[k];
    },
    writeValue: (k, v) async {
      if (failKnown && jsonDecode(v)['state'] == 'known') {
        failKnown = false;
        throw StateError('io');
      }
      values[k] = v;
    },
    deleteValue: (k) async {
      if (failDelete) {
        failDelete = false;
        throw StateError('io');
      }
      values.remove(k);
    },
    flush: () async {
      if (failFlush) {
        failFlush = false;
        throw StateError('io');
      }
    },
  );
  Future<void> claim() => journal.claimUnknown(
    baselineFingerprint: 'b' * 64,
    inputDigest: 'c' * 64,
  );
}

void main() {
  late Env e;
  setUp(() => e = Env());
  tearDown(() => e.journal.retire());
  test(
    'one durable claim; strict unknown never authorizes repeated save',
    () async {
      await e.claim();
      final raw = e.values.values.single;
      expect(jsonDecode(raw).keys.toSet(), {
        'v',
        'scope',
        'attempt',
        'baseline',
        'input',
        'state',
      });
      expect(jsonDecode(raw)['state'], 'unknown');
      await expectLater(e.claim(), throwsStateError);
      expect(e.values.values.single, raw);
    },
  );
  test('flush/read failures block; never interpreted as absent', () async {
    e.failRead = true;
    await expectLater(e.journal.load(), throwsStateError);
    e.failRead = false;
    e.failFlush = true;
    await expectLater(e.claim(), throwsStateError);
    expect(e.values, isEmpty);
    await e.claim();
    expect((await e.journal.load())!.known, isFalse);
  });
  test('known write failure retries only metadata then clears', () async {
    await e.claim();
    e.journal.rememberKnownReceipt('d' * 64);
    e.failKnown = true;
    await expectLater(e.journal.finishKnown(), throwsStateError);
    expect(jsonDecode(e.values.values.single)['state'], 'unknown');
    await e.journal.finishKnown();
    expect(e.values, isEmpty);
    expect(e.journal.hasWarmAttempt, isFalse);
  });
  test(
    'known delete failure retains known record and storage-only retry',
    () async {
      await e.claim();
      e.journal.rememberKnownReceipt('d' * 64);
      e.failDelete = true;
      await expectLater(e.journal.finishKnown(), throwsStateError);
      expect(jsonDecode(e.values.values.single)['state'], 'known');
      await e.journal.finishKnown();
      expect(e.values, isEmpty);
    },
  );
  test(
    'explicit review rejects changed fresh version; no silent clear',
    () async {
      await e.claim();
      final raw = e.values.values.single;
      await expectLater(
        e.journal.endReviewed(
          reviewedFingerprint: 'd' * 64,
          fresh: () async => ProtectedComplexObservation(
            fingerprint: 'e' * 64,
            inputDigest: 'f' * 64,
          ),
        ),
        throwsStateError,
      );
      expect(e.values.values.single, raw);
      await e.journal.endReviewed(
        reviewedFingerprint: 'd' * 64,
        fresh: () async => ProtectedComplexObservation(
          fingerprint: 'd' * 64,
          inputDigest: 'f' * 64,
        ),
      );
      expect(e.values, isEmpty);
    },
  );
  test('cold known requires same actual fingerprint and digest', () async {
    await e.claim();
    e.journal.rememberKnownReceipt('d' * 64);
    e.failDelete = true;
    await expectLater(e.journal.finishKnown(), throwsStateError);
    final persisted = e.values;
    e.journal.retire();
    e = Env(values: persisted);
    expect(e.journal.hasKnownReceipt, isFalse);
    await expectLater(
      e.journal.confirmColdKnown(
        ProtectedComplexObservation(
          fingerprint: 'd' * 64,
          inputDigest: 'e' * 64,
        ),
      ),
      throwsStateError,
    );
    await e.journal.confirmColdKnown(
      ProtectedComplexObservation(fingerprint: 'd' * 64, inputDigest: 'c' * 64),
    );
    await e.journal.finishKnown();
    expect(e.values, isEmpty);
  });
  test('retired scope cannot clear record; second live owner denied', () async {
    await e.claim();
    expect(
      () => ProtectedOwnedComplexJournal(
        ownerTag: List.filled(64, 'b').join(),
        scope: 'a' * 64,
        isCurrent: () => true,
        readValue: (k) async => null,
        writeValue: (k, v) async {},
        deleteValue: (k) async {},
        flush: () async {},
      ),
      throwsStateError,
    );
    e.current = false;
    await expectLater(e.journal.finishKnown(), throwsStateError);
    expect(e.values, isNotEmpty);
  });
}
