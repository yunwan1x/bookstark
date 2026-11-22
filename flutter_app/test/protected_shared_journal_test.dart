import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_shared_journal.dart';
import 'package:bookstark_flutter/core/protected_shared_marker_metadata.dart';

class Harness {
  final values = <String, String>{};
  final writes = <String>[], reads = <String>[];
  bool current = true, failFlush = false, failDelete = false;
  int? failAtFlush;
  int flushes = 0;
  ProtectedSharedJournal open({String identity = 'b'}) =>
      ProtectedSharedJournal(
        capabilityPrincipal: 'a' * 64,
        identity: identity * 64,
        isCurrent: () => current,
        listKeys: () async => values.keys.toList(),
        readValue: (key) async {
          reads.add(key);
          return values[key];
        },
        writeValue: (key, value) async {
          writes.add(value);
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
          if (failDelete) {
            throw StateError('delete applied but acknowledgement lost');
          }
        },
        flush: () async {
          flushes++;
          if (failFlush || flushes == failAtFlush) {
            throw StateError('flush failed');
          }
        },
      );
  ProtectedSharedObservation observation(String identity) =>
      ProtectedSharedObservation(
        identity: identity * 64,
        sourceDigest: 'd' * 64,
        fingerprint: 'e' * 64,
        modified: 'now',
      );
}

void main() {
  test('same capability remains grouped after share ID replacement', () {
    final first = ProtectedSharedJournal.capabilityFor(
      server: 'https://share.test',
      shareId: 1,
      capabilityHash: 'f' * 64,
    );
    final replaced = ProtectedSharedJournal.capabilityFor(
      server: 'https://share.test',
      shareId: 2,
      capabilityHash: 'f' * 64,
    );
    expect(first, replaced);
    expect(
      first,
      isNot(
        ProtectedSharedJournal.capabilityFor(
          server: 'https://other.test',
          shareId: 1,
          capabilityHash: 'f' * 64,
        ),
      ),
    );
  });

  test('single live capability lease and one submission claim', () async {
    final h = Harness();
    final journal = h.open();
    addTearDown(journal.retire);
    expect(() => h.open(), throwsStateError);
    await journal.claimUnknown(
      expectedSource: 'c' * 64,
      submittedSource: 'd' * 64,
    );
    await expectLater(
      journal.claimUnknown(expectedSource: 'c' * 64, submittedSource: 'd' * 64),
      throwsStateError,
    );
    expect(h.values.length, 1);
    expect(h.writes.length, 1);
    final decoded = jsonDecode(h.writes.single) as Map;
    expect(decoded.keys.toSet(), {
      'version',
      'principal',
      'operation',
      'capabilityPrincipal',
      'identity',
      'expectedSource',
      'submittedSource',
      'phase',
      'modified',
    });
    expect(decoded['phase'], 'unknown');
  });
  test('known receipt storage retry never grants retry send', () async {
    final h = Harness();
    final journal = h.open();
    addTearDown(journal.retire);
    final first = journal.claimUnknown(
      expectedSource: 'c' * 64,
      submittedSource: 'd' * 64,
    );
    await first;
    h.failFlush = true;
    journal.rememberKnown(sourceDigest: 'd' * 64, modified: 'receipt');
    await expectLater(journal.persistKnown(), throwsStateError);
    expect(journal.hasKnown, isTrue);
    await expectLater(
      journal.claimUnknown(expectedSource: 'c' * 64, submittedSource: 'd' * 64),
      throwsStateError,
    );
    h.failFlush = false;
    await journal.persistKnown();
    expect(
      (await journal.loadGroup()).single.phase,
      ProtectedSharedMarkerPhase.known,
    );
    await journal.finishKnown();
    expect(h.values, isEmpty);
  });
  test(
    'cold retarget finds original group and requires explicit unverifiable end',
    () async {
      final h = Harness();
      final old = h.open();
      await old.claimUnknown(
        expectedSource: 'c' * 64,
        submittedSource: 'd' * 64,
      );
      await old.retire();
      final next = h.open(identity: 'f');
      addTearDown(next.retire);
      final record = (await next.loadGroup()).single;
      expect(record.identity, 'b' * 64);
      await expectLater(
        next.claimUnknown(expectedSource: 'c' * 64, submittedSource: 'd' * 64),
        throwsStateError,
      );
      await expectLater(
        next.endReviewed(
          record,
          reviewedFingerprint: 'e' * 64,
          allowUnverifiable: false,
          fresh: () async => h.observation('f'),
        ),
        throwsStateError,
      );
      expect(h.values.length, 1);
      await next.endReviewed(
        record,
        reviewedFingerprint: 'e' * 64,
        allowUnverifiable: true,
        fresh: () async => h.observation('f'),
      );
      expect(h.values, isEmpty);
    },
  );
  test(
    'foreign draft values never read and malformed own metadata retained',
    () async {
      final h = Harness();
      h.values['ordinary-private-draft'] = 'secret body';
      h.values[ProtectedSharedMarkerKey.prefix + '1' * 64] = 'malformed';
      final journal = h.open();
      addTearDown(journal.retire);
      await expectLater(journal.loadGroup(), throwsFormatException);
      expect(h.reads, isNot(contains('ordinary-private-draft')));
      expect(h.values['ordinary-private-draft'], 'secret body');
      expect(h.values.length, 2);
    },
  );
  test(
    'retirement forbids late writes and clear never resurrects a record',
    () async {
      final h = Harness();
      final journal = h.open();
      await journal.claimUnknown(
        expectedSource: 'c' * 64,
        submittedSource: 'd' * 64,
      );
      final record = (await journal.loadGroup()).single;
      await journal.endReviewed(
        record,
        reviewedFingerprint: 'e' * 64,
        allowUnverifiable: false,
        fresh: () async => h.observation('b'),
      );
      expect(h.values, isEmpty);
      await journal.retire();
      await expectLater(
        journal.claimUnknown(
          expectedSource: 'c' * 64,
          submittedSource: 'd' * 64,
        ),
        throwsStateError,
      );
      expect(h.values, isEmpty);
    },
  );
  test(
    'claim applied then flush failure stays unknown and cannot send again',
    () async {
      final h = Harness()..failAtFlush = 2;
      final journal = h.open();
      addTearDown(journal.retire);
      await expectLater(
        journal.claimUnknown(
          expectedSource: 'c' * 64,
          submittedSource: 'd' * 64,
        ),
        throwsStateError,
      );
      expect(h.values.length, 1);
      expect(journal.hasAttempt, isTrue);
      h.failAtFlush = null;
      await expectLater(
        journal.claimUnknown(
          expectedSource: 'c' * 64,
          submittedSource: 'd' * 64,
        ),
        throwsStateError,
      );
      expect(h.writes.length, 1);
    },
  );
  test(
    'delete applied acknowledgement lost retries cleanup without recreation',
    () async {
      final h = Harness();
      final journal = h.open();
      addTearDown(journal.retire);
      await journal.claimUnknown(
        expectedSource: 'c' * 64,
        submittedSource: 'd' * 64,
      );
      final record = (await journal.loadGroup()).single;
      h.failDelete = true;
      await expectLater(
        journal.endReviewed(
          record,
          reviewedFingerprint: 'e' * 64,
          allowUnverifiable: false,
          fresh: () async => h.observation('b'),
        ),
        throwsStateError,
      );
      expect(h.values, isEmpty);
      h.failDelete = false;
      await journal.endReviewed(
        record,
        reviewedFingerprint: 'e' * 64,
        allowUnverifiable: false,
        fresh: () async => h.observation('b'),
      );
      expect(h.values, isEmpty);
      expect(h.writes.length, 1);
    },
  );

  test(
    'reopening review after applied delete lost ACK completes only storage cleanup',
    () async {
      final h = Harness();
      final journal = h.open();
      addTearDown(journal.retire);
      await journal.claimUnknown(
        expectedSource: 'c' * 64,
        submittedSource: 'd' * 64,
      );
      final record = (await journal.loadGroup()).single;
      h.failDelete = true;
      await expectLater(
        journal.endReviewed(
          record,
          reviewedFingerprint: 'e' * 64,
          allowUnverifiable: false,
          fresh: () async => h.observation('b'),
        ),
        throwsStateError,
      );
      expect(journal.hasAttempt, isTrue);
      expect(h.values, isEmpty);
      h.failDelete = false;
      expect(await journal.loadGroup(), isEmpty);
      expect(journal.hasAttempt, isFalse);
      expect(h.writes.length, 1);
    },
  );
}
