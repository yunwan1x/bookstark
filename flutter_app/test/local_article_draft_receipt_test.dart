import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

String marker(String namespace, Object? id) =>
    LocalArticleDraftReceipt.keyPrefix +
    base64Url.encode(utf8.encode(jsonEncode([namespace, id])));

void main() {
  test(
    'receipt versions retain metadata only and bind a ciphertext fingerprint',
    () {
      for (final fingerprint in <String?>[null, 'b' * 64]) {
        final receipt = LocalArticleDraftReceipt(
          digest: 'a' * 64,
          disposition: LocalArticleDraftDisposition.restored,
          ciphertextSHA256: fingerprint,
        );
        final decoded = LocalArticleDraftReceipt.parse(receipt.encode());
        expect(decoded.digest, receipt.digest);
        expect(decoded.disposition, receipt.disposition);
        expect(decoded.ciphertextSHA256, fingerprint);
        expect(decoded.version, fingerprint == null ? 1 : 2);
        final map = jsonDecode(receipt.encode()) as Map;
        expect(map.keys.toSet(), {
          'version',
          'digest',
          'disposition',
          if (fingerprint != null) 'ciphertext_sha256',
        });
      }
      expect(
        LocalArticleDraftReceipt.parse(
          LocalArticleDraftReceipt(
            digest: 'a' * 64,
            disposition: LocalArticleDraftDisposition.matched,
            ciphertextSHA256: 'c' * 64,
          ).encode(),
        ).disposition,
        LocalArticleDraftDisposition.matched,
      );
    },
  );

  test(
    'corrupt or body-bearing receipts are rejected rather than treated as archived',
    () {
      final good = {
        'version': 2,
        'digest': 'a' * 64,
        'disposition': 'skipped',
        'ciphertext_sha256': 'b' * 64,
      };
      for (final value in <Object?>[
        null,
        [],
        {...good, 'version': 2.0},
        {...good, 'version': 3},
        {...good, 'source': '# private'},
        {...good, 'digest': 'A' * 64},
        {...good, 'ciphertext_sha256': null},
        {...good, 'disposition': 'unknown'},
      ]) {
        expect(
          () => LocalArticleDraftReceipt.parse(jsonEncode(value)),
          throwsFormatException,
        );
      }
      expect(
        () => LocalArticleDraftReceipt.parse(' ' * 1025),
        throwsFormatException,
      );
    },
  );

  test(
    'receipt keys bind positive article IDs and owned current or retained namespaces',
    () {
      final generation = 'local-generation:${'a' * 32}';
      for (final base in ['local', generation]) {
        final namespace = jsonEncode([base, 'article']);
        final key = marker(namespace, 17);
        final scope = LocalArticleDraftReceiptScope.parse(key, {
          'local',
          generation,
        });
        expect(scope.id, 17);
        expect(scope.namespace, namespace);
        expect(
          scope.legacyKey,
          key.replaceFirst(
            LocalArticleDraftReceipt.keyPrefix,
            LocalArticleDraftReceipt.legacyKeyPrefix,
          ),
        );
        expect(
          LocalArticleDraftReceiptScope.localLegacy(scope.legacyKey).id,
          17,
        );
        var reads = 0;
        final records = SecureRecordStore(
          prefix: 'bookstark.draft.v1',
          namespace: namespace,
          readValue: (_) async {
            reads++;
            throw StateError('Body access forbidden');
          },
          writeValue: (_, _) async {},
          deleteValue: (_) async {},
        );
        expect(records.metadataKey(17), scope.legacyKey);
        expect(reads, 0);
      }
    },
  );

  test(
    'ordinary notes, remote scopes, orphan namespaces and non-integer IDs cannot be archived',
    () {
      final article = jsonEncode(['local', 'article']);
      for (final key in [
        marker('local', 17),
        marker(jsonEncode(['https://server.test', 'article']), 17),
        marker(jsonEncode(['local', 'note']), 17),
        marker(jsonEncode(['local-generation:${'b' * 32}', 'article']), 17),
        marker(article, null),
        marker(article, -1),
        marker(article, 0),
        marker(article, '17'),
        marker(article, 17.0),
        'bookstark.local-article-draft-handoff.v1.invalid!',
      ]) {
        expect(
          () => LocalArticleDraftReceiptScope.parse(key, {'local'}),
          throwsFormatException,
        );
      }
      for (final namespace in [
        'local',
        jsonEncode(['local', 'note']),
        jsonEncode(['https://server.test', 'article']),
      ]) {
        final key = marker(namespace, 17).replaceFirst(
          LocalArticleDraftReceipt.keyPrefix,
          LocalArticleDraftReceipt.legacyKeyPrefix,
        );
        expect(
          () => LocalArticleDraftReceiptScope.localLegacy(key),
          throwsFormatException,
        );
      }
    },
  );
}
