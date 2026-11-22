import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_complex_memory_store.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';

String hex(String v) => List.filled(64, v).join();

class Env {
  final values = <String, String>{};
  bool failDelete = false;
  late final journal = ProtectedOwnedComplexJournal(
    scope: hex('a'),
    ownerTag: hex('b'),
    isCurrent: () => true,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      if (failDelete) throw StateError('IO');
      values.remove(k);
    },
    flush: () async {},
  );
}

void main() {
  test(
    'full body only in memory; copies isolated and retire wipes access',
    () async {
      final e = Env();
      addTearDown(e.journal.retire);
      final memory = ProtectedComplexMemoryStore(e.journal);
      final input = Uint8List.fromList([11, 22, 33]);
      await memory.write(hex('c'), input);
      input[0] = 99;
      final first = (await memory.read(hex('c')))!;
      expect(first, [11, 22, 33]);
      first[1] = 99;
      expect(await memory.read(hex('c')), [11, 22, 33]);
      expect(e.values, isEmpty);
      memory.close();
      expect(() => memory.read(hex('c')), throwsStateError);
    },
  );
  test('unknown cannot remove full warm draft or authorize repeat', () async {
    final e = Env();
    addTearDown(e.journal.retire);
    final memory = ProtectedComplexMemoryStore(e.journal);
    await memory.write(hex('c'), Uint8List.fromList([44]));
    await e.journal.claimUnknown(
      baselineFingerprint: hex('d'),
      inputDigest: hex('e'),
    );
    expect(() => memory.remove(hex('c')), throwsStateError);
    expect(await memory.read(hex('c')), [44]);
    expect(
      () => e.journal.claimUnknown(
        baselineFingerprint: hex('d'),
        inputDigest: hex('e'),
      ),
      throwsStateError,
    );
    expect(e.values.values.single, isNot(contains('44')));
  });
  test(
    'known cleanup failure retries only journal and releases memory after success',
    () async {
      final e = Env();
      addTearDown(e.journal.retire);
      final memory = ProtectedComplexMemoryStore(e.journal);
      await memory.write(hex('c'), Uint8List.fromList([55]));
      await e.journal.claimUnknown(
        baselineFingerprint: hex('d'),
        inputDigest: hex('e'),
      );
      e.journal.rememberKnownReceipt(hex('f'));
      e.failDelete = true;
      await expectLater(memory.remove(hex('c')), throwsStateError);
      expect(await memory.read(hex('c')), [55]);
      expect(e.journal.hasKnownReceipt, isTrue);
      e.failDelete = false;
      await memory.remove(hex('c'));
      expect(e.values, isEmpty);
      expect(await memory.read(hex('c')), isNull);
    },
  );
}
