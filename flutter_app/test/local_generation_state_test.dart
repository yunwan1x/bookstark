import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';

LocalGenerationPointer pointer(
  String generation,
  int epoch,
  String operation,
) => LocalGenerationPointer(
  generation: generation,
  epoch: epoch,
  activationId: operation,
  sourceSHA256: 'f' * 64,
);
LocalRetention retention(String? source, {String? id, String? manifest}) =>
    LocalRetention(
      id: id ?? 'c' * 32,
      sourcePointerSHA256: localPointerSHA256(source),
      sourceGeneration: source == null
          ? 'legacy'
          : LocalGenerationPointer.parse(source).generation,
      manifestSHA256: manifest ?? 'd' * 64,
    );
LocalRestoreIntent intent(String? source, LocalGenerationPointer target) =>
    LocalRestoreIntent(
      operationId: target.activationId,
      sourcePointerRaw: source,
      retainedId: 'c' * 32,
      retainedManifestSHA256: 'd' * 64,
      targetPointerRaw: target.encode(),
    );
LocalGenerationObservation observe({
  String? pointerRaw,
  LocalRestoreIntent? pending,
  LocalRetention? current,
  LocalRetention? source,
}) => LocalGenerationObservation.inspect(
  pointerRaw: pointerRaw,
  intentRaw: pending?.encode(),
  currentRetentionRaw: current?.encode(),
  sourceRetentionRaw: source?.encode(),
);

void main() {
  test('legacy absence and acknowledged active pointer are ready', () {
    expect(observe().phase, LocalGenerationPhase.ready);
    final p = pointer('a' * 32, 1, 'b' * 32);
    expect(observe(pointerRaw: p.encode()).needsReview, isFalse);
    expect(localPointerSHA256(null), sha256.convert([]).toString());
  });

  test(
    'retention lock without intent stays read-only after an intermediate crash',
    () {
      final result = observe(current: retention(null));
      expect(result.phase, LocalGenerationPhase.retained);
      expect(result.needsReview, isTrue);
      expect(result.canAcknowledgeApplied, isFalse);
      expect(result.canFinishUnapplied, isFalse);
    },
  );

  test(
    'prepared intent binds unchanged legacy pointer and both retention observations',
    () {
      final pending = intent(null, pointer('a' * 32, 1, 'b' * 32));
      final lock = retention(null);
      final result = observe(pending: pending, current: lock, source: lock);
      expect(result.phase, LocalGenerationPhase.prepared);
      expect(result.canFinishUnapplied, isTrue);
      expect(result.canAcknowledgeApplied, isFalse);
      expect(result.needsReview, isTrue);
    },
  );

  test(
    'applied pointer still requires explicit acknowledgement while intent exists',
    () {
      final target = pointer('a' * 32, 1, 'b' * 32);
      final pending = intent(null, target);
      final result = observe(
        pointerRaw: target.encode(),
        pending: pending,
        source: retention(null),
      );
      expect(result.phase, LocalGenerationPhase.switched);
      expect(result.canAcknowledgeApplied, isTrue);
      expect(result.canFinishUnapplied, isFalse);
      expect(result.needsReview, isTrue);
      expect(
        LocalRestoreIntent.parse(pending.encode()).encode(),
        pending.encode(),
      );
    },
  );

  test(
    'existing generations advance exactly one epoch and retain original metadata',
    () {
      final old = pointer('1' * 32, 7, '2' * 32).encode();
      final target = pointer('3' * 32, 8, '4' * 32);
      final pending = intent(old, target);
      final lock = retention(old);
      expect(
        observe(
          pointerRaw: old,
          pending: pending,
          current: lock,
          source: lock,
        ).phase,
        LocalGenerationPhase.prepared,
      );
      expect(
        observe(
          pointerRaw: target.encode(),
          pending: pending,
          source: lock,
        ).phase,
        LocalGenerationPhase.switched,
      );
      expect(LocalRetention.parse(lock.encode()).encode(), lock.encode());
    },
  );

  test(
    'missing or conflicting durable facts never look ready or acknowledged',
    () {
      final target = pointer('a' * 32, 1, 'b' * 32);
      final pending = intent(null, target);
      final wrong = retention(null, id: 'e' * 32);
      final another = pointer('1' * 32, 2, '2' * 32).encode();
      for (final result in [
        observe(pending: pending),
        observe(pending: pending, current: retention(null)),
        observe(pending: pending, current: wrong, source: retention(null)),
        observe(pending: pending, current: retention(null), source: wrong),
        observe(pointerRaw: another, pending: pending, source: retention(null)),
        observe(
          pointerRaw: target.encode(),
          pending: pending,
          current: retention(target.encode()),
          source: retention(null),
        ),
        observe(source: retention(null)),
      ]) {
        expect(result.phase, LocalGenerationPhase.inconsistent);
        expect(result.needsReview, isTrue);
        expect(result.canAcknowledgeApplied, isFalse);
        expect(result.canFinishUnapplied, isFalse);
      }
    },
  );

  test('retention source generation and manifest must match exact intent', () {
    final pending = intent(null, pointer('a' * 32, 1, 'b' * 32));
    final wrong = LocalRetention(
      id: 'c' * 32,
      sourcePointerSHA256: localPointerSHA256(null),
      sourceGeneration: 'e' * 32,
      manifestSHA256: 'd' * 64,
    );
    expect(observe(current: wrong).phase, LocalGenerationPhase.inconsistent);
    expect(
      observe(
        pending: pending,
        current: retention(null),
        source: retention(null, manifest: 'e' * 64),
      ).phase,
      LocalGenerationPhase.inconsistent,
    );
  });

  test(
    'intent rejects reuse of source generation, wrong epoch or operation binding',
    () {
      final old = pointer('a' * 32, 3, 'b' * 32).encode();
      expect(
        () => intent(old, pointer('a' * 32, 4, 'c' * 32)),
        throwsFormatException,
      );
      expect(
        () => intent(old, pointer('d' * 32, 5, 'c' * 32)),
        throwsFormatException,
      );
      expect(
        () => LocalRestoreIntent(
          operationId: 'e' * 32,
          sourcePointerRaw: old,
          retainedId: 'c' * 32,
          retainedManifestSHA256: 'd' * 64,
          targetPointerRaw: pointer('d' * 32, 4, 'c' * 32).encode(),
        ),
        throwsFormatException,
      );
      final pending = intent(old, pointer('d' * 32, 4, 'c' * 32));
      final raw = jsonDecode(pending.encode()) as Map<String, dynamic>;
      raw['sourcePointerSHA256'] = '0' * 64;
      expect(
        () => LocalRestoreIntent.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    },
  );

  test(
    'duplicate keys, unknown fields, numeric versions and path-like IDs fail',
    () {
      final raw = pointer('a' * 32, 1, 'b' * 32).encode();
      for (final candidate in [
        raw.replaceFirst('"format":1', '"format":1,"format":1'),
        raw.replaceFirst('"format":1', '"format":1.0'),
        raw.replaceFirst('"format":1', '"format":1,"path":"/other"'),
        raw.replaceFirst('a' * 32, '../escape'),
        ' $raw',
      ]) {
        expect(
          () => LocalGenerationPointer.parse(candidate),
          throwsFormatException,
        );
      }
    },
  );

  test('oversized metadata and invalid epoch bounds are rejected', () {
    expect(
      () => LocalGenerationPointer.parse('x' * 4097),
      throwsFormatException,
    );
    expect(() => pointer('a' * 32, 0, 'b' * 32), throwsFormatException);
    expect(
      () => pointer('a' * 32, 0x1fffffffffffff, 'b' * 32),
      throwsFormatException,
    );
    expect(() => pointer('A' * 32, 1, 'b' * 32), throwsFormatException);
  });
}
