import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';

String scopedKey(String prefix, String base, int id) =>
    '$prefix.${base64Url.encode(utf8.encode(jsonEncode([
      jsonEncode([base, 'article']),
      id,
    ])))}';

void main() {
  final old = scopedKey('bookstark.draft.v1', 'local', 17);
  final marker = scopedKey(LocalArticleDraftReceipt.recordPrefix, 'local', 17);
  final hash = 'a' * 64;
  final reads = <String>[], fingerprints = <String>[];
  LocalRecoveryInventory make({
    List<String>? keys,
    List<String> html = const [],
    List<String> complexKeys = const [],
    String? receipt,
    String? actualHash,
    bool failReceipt = false,
    bool failHash = false,
    Set<String> namespaces = const {'local'},
    Map<String, String>? receipts,
    Map<String, String>? hashes,
  }) {
    return LocalRecoveryInventory(
      maintenance: LocalDataMaintenance(),
      localNamespaces: namespaces,
      preferencesMetadata: () async => {
        'format': 1,
        'secureKeys': keys ?? [old, marker],
        'htmlKeys': html,
        'overflow': false,
        'valuesIncluded': false,
      },
      complexMetadata: () async => {
        'format': 1,
        'keys': complexKeys,
        'unknownFiles': 0,
        'activeTransfers': 0,
        'overflow': false,
        'valuesIncluded': false,
      },
      readArticleReceipt: (key) async {
        reads.add(key);
        if (failReceipt) throw StateError('Receipt unavailable');
        return receipts?[key] ?? receipt;
      },
      fingerprintArticleDraft: (key) async {
        fingerprints.add(key);
        if (failHash) throw StateError('Fingerprint unavailable');
        return hashes?[key] ?? actualHash;
      },
    );
  }

  String receipt({
    String? fingerprint,
    LocalArticleDraftDisposition disposition =
        LocalArticleDraftDisposition.skipped,
  }) => LocalArticleDraftReceipt(
    digest: 'b' * 64,
    disposition: disposition,
    ciphertextSHA256: fingerprint,
  ).encode();
  setUp(() {
    reads.clear();
    fingerprints.clear();
  });

  test(
    'matching handled ciphertext is archived and does not block backup, without reading a body',
    () async {
      final originalKeys = [old, marker];
      final summary = await make(
        keys: originalKeys,
        receipt: receipt(fingerprint: hash),
        actualHash: hash,
      ).read();
      expect(summary.needsAttention, isFalse);
      expect(summary.requireClear, returnsNormally);
      expect(summary.unknown, 0);
      expect(summary.references, isEmpty);
      expect(summary.archivedArticles.single.reference.key, old);
      expect(summary.archivedArticles.single.reference.kind, 'article-archive');
      expect(summary.archivedArticles.single.reference.recordId, 17);
      expect(
        summary.archivedArticles.single.disposition,
        LocalArticleDraftDisposition.skipped,
      );
      expect(reads, [marker]);
      expect(fingerprints, [old]);
      expect(originalKeys, [old, marker]);
    },
  );

  test(
    'changed or missing fingerprint leaves the original draft active and kept',
    () async {
      for (final actual in <String?>['c' * 64, null]) {
        final summary = await make(
          receipt: receipt(fingerprint: hash),
          actualHash: actual,
        ).read();
        expect(summary.needsAttention, isTrue);
        expect(summary.references.single.key, old);
        expect(summary.archivedArticles, isEmpty);
        expect(summary.unknown, 0);
      }
      expect(reads.every((key) => key == marker), isTrue);
    },
  );

  test(
    'old version one receipt is recognized but cannot suppress an unverified draft',
    () async {
      final summary = await make(receipt: receipt()).read();
      expect(summary.needsAttention, isTrue);
      expect(summary.references.single.key, old);
      expect(summary.unknown, 0);
      expect(summary.archivedArticles, isEmpty);
      expect(fingerprints, isEmpty);
    },
  );

  test(
    'failed metadata and corrupt body-bearing receipts remain blocking',
    () async {
      for (final fixture in [
        make(failReceipt: true),
        make(receipt: '{"version":2,"source":"forbidden"}'),
        make(receipt: receipt(fingerprint: hash), failHash: true),
      ]) {
        final summary = await fixture.read();
        expect(summary.needsAttention, isTrue);
        expect(summary.references.single.key, old);
        expect(summary.unknown, 1);
        expect(summary.archivedArticles, isEmpty);
      }
      expect(reads.every((key) => key == marker), isTrue);
    },
  );

  test(
    'real complex recovery still blocks even with an archived old record',
    () async {
      final summary = await make(
        receipt: receipt(fingerprint: hash),
        actualHash: hash,
        complexKeys: ['d' * 64],
      ).read();
      expect(summary.archivedArticles, hasLength(1));
      expect(summary.complexKeys, ['d' * 64]);
      expect(summary.needsAttention, isTrue);
    },
  );

  test(
    'a known receipt without the original record is metadata, not an invented pending body',
    () async {
      final summary = await make(
        keys: [marker],
        receipt: receipt(fingerprint: hash),
      ).read();
      expect(summary.needsAttention, isFalse);
      expect(summary.archivedArticles, isEmpty);
      expect(fingerprints, isEmpty);
      expect(reads, [marker]);
    },
  );

  test(
    'wrong store and unowned receipt keys remain unknown without decrypting them',
    () async {
      final unowned = scopedKey(
        LocalArticleDraftReceipt.recordPrefix,
        'local-generation:${'c' * 32}',
        17,
      );
      final summary = await make(
        keys: [unowned],
        html: [marker],
        receipt: receipt(fingerprint: hash),
        actualHash: hash,
      ).read();
      expect(summary.unknown, 2);
      expect(summary.needsAttention, isTrue);
      expect(reads, isEmpty);
      expect(fingerprints, isEmpty);
    },
  );

  test(
    'retained owned generations archive by exact namespace and key',
    () async {
      final generation = 'local-generation:${'c' * 32}';
      final oldGeneration = scopedKey('bookstark.draft.v1', generation, 17);
      final markerGeneration = scopedKey(
        LocalArticleDraftReceipt.recordPrefix,
        generation,
        17,
      );
      final summary = await make(
        keys: [old, marker, oldGeneration, markerGeneration],
        namespaces: {'local', generation},
        receipts: {
          marker: receipt(fingerprint: hash),
          markerGeneration: receipt(
            fingerprint: 'd' * 64,
            disposition: LocalArticleDraftDisposition.matched,
          ),
        },
        hashes: {old: hash, oldGeneration: 'd' * 64},
      ).read();
      expect(summary.needsAttention, isFalse);
      expect(summary.archivedArticles.map((a) => a.reference.namespace), [
        jsonEncode(['local', 'article']),
        jsonEncode([generation, 'article']),
      ]);
      expect(
        summary.archivedArticles.last.disposition,
        LocalArticleDraftDisposition.matched,
      );
      expect(reads.toSet(), {marker, markerGeneration});
      expect(fingerprints.toSet(), {old, oldGeneration});
    },
  );
  test(
    'retirement during receipt metadata read stops further inspection',
    () async {
      final gate = LocalDataMaintenance();
      var fingerprints = 0;
      final inventory = LocalRecoveryInventory(
        maintenance: gate,
        localNamespaces: {'local'},
        preferencesMetadata: () async => {
          'format': 1,
          'secureKeys': [old, marker],
          'htmlKeys': <String>[],
          'overflow': false,
          'valuesIncluded': false,
        },
        complexMetadata: () async => {
          'format': 1,
          'keys': <String>[],
          'unknownFiles': 0,
          'activeTransfers': 0,
          'overflow': false,
          'valuesIncluded': false,
        },
        readArticleReceipt: (_) async {
          gate.retire();
          return receipt(fingerprint: hash);
        },
        fingerprintArticleDraft: (_) async {
          fingerprints++;
          return hash;
        },
      );
      await expectLater(inventory.read(), throwsStateError);
      expect(fingerprints, 0);
    },
  );
}
