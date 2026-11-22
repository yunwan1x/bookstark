import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';

void main() {
  String legacyKey(String base) =>
      'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode([
        jsonEncode([base, 'article']),
        null,
      ])))}';
  final old = legacyKey('local');
  final marker = LocalArticleCreationLegacyScope.fromLegacyKey(old).markerKey;
  final fp = 'a' * 64;
  final reads = <String>[], fingerprints = <String>[];
  String receipt() => LocalArticleCreationLegacyReceipt(
    digest: 'b' * 64,
    ciphertextSHA256: fp,
    disposition: LocalArticleCreationLegacyDisposition.restored,
    creationKey: 'c' * 32,
  ).encode();
  LocalRecoveryInventory inventory({
    List<String>? keys,
    List<String> html = const [],
    List<String> complex = const [],
    String? raw,
    String? hash,
    bool failHash = false,
    LocalDataMaintenance? maintenance,
    Future<String?> Function(String)? read,
  }) => LocalRecoveryInventory(
    maintenance: maintenance ?? LocalDataMaintenance(),
    localNamespaces: const {'local'},
    preferencesMetadata: () async => {
      'format': 1,
      'secureKeys': keys ?? [old, marker],
      'htmlKeys': html,
      'overflow': false,
      'valuesIncluded': false,
    },
    complexMetadata: () async => {
      'format': 1,
      'keys': complex,
      'unknownFiles': 0,
      'activeTransfers': 0,
      'overflow': false,
      'valuesIncluded': false,
    },
    readArticleReceipt: (_) async =>
        throw StateError('Wrong positive-ID purpose'),
    fingerprintArticleDraft: (_) async =>
        throw StateError('Wrong positive-ID purpose'),
    readArticleCreationReceipt:
        read ??
        (key) async {
          reads.add(key);
          return raw ?? receipt();
        },
    fingerprintArticleCreationDraft: (key) async {
      fingerprints.add(key);
      if (failHash) throw StateError('Owned metadata failure');
      return hash ?? fp;
    },
  );
  setUp(() {
    reads.clear();
    fingerprints.clear();
  });
  test(
    'handled null-ID original remains readonly-addressable without pending or body reads',
    () async {
      final view = await inventory().read();
      expect(view.needsAttention, isFalse);
      expect(view.references, isEmpty);
      expect(view.archivedArticles, isEmpty);
      expect(view.archivedCreations.single.reference.key, old);
      expect(view.archivedCreations.single.reference.recordId, isNull);
      expect(
        view.archivedCreations.single.reference.kind,
        'article-create-archive',
      );
      expect(view.archivedCreations.single.creationKey, 'c' * 32);
      expect(reads, [marker]);
      expect(fingerprints, [old]);
    },
  );
  test(
    'a real binary creation slot still blocks backup beside an archived original',
    () async {
      final slot = 'd' * 64;
      final view = await inventory(complex: [slot]).read();
      expect(view.archivedCreations, hasLength(1));
      expect(view.complexKeys, [slot]);
      expect(view.needsAttention, isTrue);
      expect(view.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
  test(
    'changed original ciphertext keeps its active null draft and cannot be hidden',
    () async {
      final view = await inventory(hash: 'e' * 64).read();
      expect(view.archivedCreations, isEmpty);
      expect(view.needsAttention, isTrue);
      expect(view.references.single.key, old);
      expect(view.references.single.recordId, isNull);
    },
  );
  test('malformed receipt and failed fingerprint preserve blockers', () async {
    for (final source in [inventory(raw: '{}'), inventory(failHash: true)]) {
      final view = await source.read();
      expect(view.archivedCreations, isEmpty);
      expect(view.unknown, 1);
      expect(view.references.single.key, old);
      expect(view.needsAttention, isTrue);
    }
  });
  test(
    'unowned receipt never decrypts metadata or reads a fingerprint',
    () async {
      final foreign = legacyKey('local-generation:${'f' * 32}');
      final key = LocalArticleCreationLegacyScope.fromLegacyKey(
        foreign,
      ).markerKey;
      final view = await inventory(keys: [foreign, key]).read();
      expect(view.unknown, 1);
      expect(view.needsAttention, isTrue);
      expect(reads, isEmpty);
      expect(fingerprints, isEmpty);
    },
  );
  test(
    'wrong preference store cannot turn a marker into permission to archive',
    () async {
      final view = await inventory(keys: [old], html: [marker]).read();
      expect(view.unknown, 1);
      expect(view.references.single.key, old);
      expect(view.archivedCreations, isEmpty);
      expect(reads, isEmpty);
    },
  );
  test(
    'valid metadata receipt without its old original causes no fictitious pending draft',
    () async {
      final view = await inventory(keys: [marker]).read();
      expect(view.needsAttention, isFalse);
      expect(view.archivedCreations, isEmpty);
      expect(fingerprints, isEmpty);
    },
  );
  test(
    'retirement during metadata lookup cannot publish a falsely clear summary',
    () async {
      final gate = LocalDataMaintenance();
      await expectLater(
        inventory(
          maintenance: gate,
          read: (_) async {
            gate.retire();
            return receipt();
          },
        ).read(),
        throwsStateError,
      );
      expect(fingerprints, isEmpty);
    },
  );
}
