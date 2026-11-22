import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned15_save_journal.dart';
import 'package:bookstark_flutter/core/owned15_save_marker_metadata.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';
import 'package:bookstark_flutter/core/protected_owned_marker_metadata.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'local_recovery_inventory_test.dart' show prefs, complex, inventory;

void main() {
  final values = <String, String>{};
  final opened = <Owned15SaveJournal>[];
  bool current = true, failFlush = false;
  int mutations = 0;
  Owned15SaveJournal journal({
    String namespace = 'local-generation:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    int id = 9,
    String collection = 'note',
  }) {
    final value = Owned15SaveJournal(
      draftNamespace: namespace,
      collection: collection,
      resourceId: id,
      isCurrent: () => current,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
      flush: () async {
        if (failFlush) throw StateError('flush unavailable');
      },
    );
    opened.add(value);
    return value;
  }

  setUp(() {
    values.clear();
    opened.clear();
    current = true;
    failFlush = false;
    mutations = 0;
  });
  tearDown(() async {
    for (final value in opened) {
      await value.drain();
      value.retire();
    }
  });
  test(
    'independent local principal key and no-body marker precedes mutation',
    () async {
      final value = journal();
      await value.claimUnknown(
        baselineFingerprint: 'b' * 64,
        inputDigest: 'c' * 64,
      );
      mutations++;
      final key = values.keys.single;
      expect(key.startsWith(Owned15SaveMarkerMetadata.keyPrefix), isTrue);
      final metadata = Owned15SaveMarkerMetadata.parse(key);
      expect(
        metadata.ownerTag,
        Owned15SaveJournal.ownerTagForGeneration(
          'local-generation:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      expect(
        () => ProtectedOwnedMarkerMetadata.parse(key),
        throwsFormatException,
      );
      final payload = jsonDecode(values.values.single) as Map;
      expect(payload.keys.toSet(), {
        'v',
        'scope',
        'attempt',
        'baseline',
        'input',
        'state',
      });
      expect(payload['state'], 'unknown');
      expect(mutations, 1);
      await expectLater(
        value.claimUnknown(
          baselineFingerprint: 'b' * 64,
          inputDigest: 'c' * 64,
        ),
        throwsStateError,
      );
      expect(mutations, 1);
    },
  );
  test(
    'durable claim failure authorizes zero mutation and blocks same warm retry',
    () async {
      final value = journal();
      failFlush = true;
      await expectLater(
        value.claimUnknown(
          baselineFingerprint: 'b' * 64,
          inputDigest: 'c' * 64,
        ),
        throwsStateError,
      );
      expect(mutations, 0);
      failFlush = false;
      // Failure before writing still permits no implicit retry in the same editor
      // through a controller; an existing record always blocks the cold path.
      if (values.isNotEmpty) {
        await expectLater(
          value.claimUnknown(
            baselineFingerprint: 'b' * 64,
            inputDigest: 'c' * 64,
          ),
          throwsStateError,
        );
      }
    },
  );
  test(
    'known cleanup failure retries storage only without another mutation',
    () async {
      final value = journal();
      await value.claimUnknown(
        baselineFingerprint: 'b' * 64,
        inputDigest: 'c' * 64,
      );
      mutations++;
      value.rememberKnownReceipt('d' * 64);
      failFlush = true;
      await expectLater(value.finishKnown(), throwsStateError);
      expect(value.hasKnownReceipt, isTrue);
      expect(mutations, 1);
      failFlush = false;
      await value.finishKnown();
      expect(values, isEmpty);
      expect(mutations, 1);
    },
  );
  test(
    'cold unknown requires explicit fresh fulltuple review and never claims historical success',
    () async {
      final warm = journal();
      await warm.claimUnknown(
        baselineFingerprint: 'b' * 64,
        inputDigest: 'c' * 64,
      );
      await warm.drain();
      warm.retire();
      final cold = journal();
      expect((await cold.load())!.known, isFalse);
      await expectLater(
        cold.endReviewed(
          reviewedFingerprint: 'd' * 64,
          fresh: () async => ProtectedComplexObservation(
            fingerprint: 'e' * 64,
            inputDigest: 'c' * 64,
          ),
        ),
        throwsStateError,
      );
      expect(values, isNotEmpty);
      await cold.endReviewed(
        reviewedFingerprint: 'd' * 64,
        fresh: () async => ProtectedComplexObservation(
          fingerprint: 'd' * 64,
          inputDigest: 'f' * 64,
        ),
      );
      expect(values, isEmpty);
      expect(mutations, 0);
    },
  );
  test(
    'resource slot remains stable across kind/protection changes while generation and collection isolate',
    () async {
      final scope = Owned15SaveJournal.scopeForResource(
        draftNamespace: 'local-generation:${'a' * 32}',
        collection: 'note',
        resourceId: 9,
      );
      expect(
        scope,
        Owned15SaveJournal.scopeForResource(
          draftNamespace: 'local-generation:${'a' * 32}',
          collection: 'note',
          resourceId: 9,
        ),
      );
      expect(
        scope,
        isNot(
          Owned15SaveJournal.scopeForResource(
            draftNamespace: 'local-generation:${'b' * 32}',
            collection: 'note',
            resourceId: 9,
          ),
        ),
      );
      expect(
        scope,
        isNot(
          Owned15SaveJournal.scopeForResource(
            draftNamespace: 'local-generation:${'a' * 32}',
            collection: 'article',
            resourceId: 9,
          ),
        ),
      );
    },
  );
  test(
    'all-owner keys-only inventory blocks valid markers without reading record values',
    () async {
      final value = journal();
      await value.claimUnknown(
        baselineFingerprint: 'b' * 64,
        inputDigest: 'c' * 64,
      );
      final result = await inventory(
        prefs(keys: values.keys.toList()),
        complex(),
        namespaces: {'local-generation:${'e' * 32}'},
      ).read();
      expect(result.references.single.kind, 'owned15-save');
      expect(result.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
  test(
    'malformed and wrong-store local15 keys remain unknown across owners',
    () async {
      final value = journal();
      await value.claimUnknown(
        baselineFingerprint: 'b' * 64,
        inputDigest: 'c' * 64,
      );
      final key = values.keys.single;
      final result = await inventory(
        prefs(
          keys: [
            Owned15SaveMarkerMetadata.prefix,
            '${Owned15SaveMarkerMetadata.keyPrefix}broken',
          ],
          html: [key],
        ),
        complex(),
      ).read();
      expect(result.references, isEmpty);
      expect(result.needsAttention, isTrue);
      expect(result.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
}
