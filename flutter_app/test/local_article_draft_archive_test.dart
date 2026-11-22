import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_draft_archive.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

void main() {
  final namespace = jsonEncode(['local', 'article']);
  final store = SecureRecordStore(
    prefix: 'bookstark.draft.v1',
    namespace: namespace,
    readValue: (_) async => null,
    writeValue: (_, _) async {},
    deleteValue: (_) async {},
  );
  final oldKey = store.metadataKey(17);
  final markerKey = oldKey.replaceFirst(
    LocalArticleDraftReceipt.legacyKeyPrefix,
    LocalArticleDraftReceipt.keyPrefix,
  );
  const source = '\ufeff# 旧稿😀\r\n- 阅读\r\n';
  final preferences = <String, String>{};
  final reads = <String>[];
  late LocalDataMaintenance gate;
  late LocalArticleDraftReceipt receipt;
  bool current = true;
  int hashes = 0;
  LocalArticleDraftArchiveReader reader({
    String? actualHash,
    Future<String?> Function(String key)? read,
    Future<String?> Function(String key)? fingerprint,
  }) => LocalArticleDraftArchiveReader(
    maintenance: gate,
    ownedNamespaces: {'local'},
    readValue:
        read ??
        (key) async {
          reads.add(key);
          return preferences[key];
        },
    fingerprintDraft:
        fingerprint ??
        (_) async {
          hashes++;
          return actualHash ?? 'c' * 64;
        },
    isCurrentScope: () => current,
  );

  setUp(() {
    gate = LocalDataMaintenance();
    current = true;
    hashes = 0;
    reads.clear();
    preferences.clear();
    preferences[oldKey] = jsonEncode({
      'version': 1,
      'title': '旧文章',
      'content': source,
      'labels': ['a,b'],
      'updated_at': 1700000000,
    });
    receipt = LocalArticleDraftReceipt(
      digest: LocalArticleDraftReceipt.digestOf(
        namespace: namespace,
        id: 17,
        title: '旧文章',
        source: source,
        labels: ['a,b'],
      ),
      disposition: LocalArticleDraftDisposition.skipped,
      ciphertextSHA256: 'c' * 64,
    );
    preferences[markerKey] = receipt.encode();
  });

  test(
    'explicit archive read verifies twice and returns exact source without any writes',
    () async {
      final original = Map.of(preferences);
      final snapshot = await reader().read(oldKey);
      expect(snapshot.edit.title, '旧文章');
      expect(snapshot.edit.document.source, source);
      expect(snapshot.edit.labels, ['a,b']);
      expect(snapshot.scope.id, 17);
      expect(
        snapshot.receipt.disposition,
        LocalArticleDraftDisposition.skipped,
      );
      expect(reads, [markerKey, oldKey, markerKey]);
      expect(hashes, 2);
      expect(preferences, original);
    },
  );

  test(
    'unverified version one and changed ciphertext cannot reveal a draft body',
    () async {
      await expectLater(
        reader(actualHash: 'd' * 64).read(oldKey),
        throwsStateError,
      );
      expect(reads, [markerKey]);
      reads.clear();
      hashes = 0;
      preferences[markerKey] = LocalArticleDraftReceipt(
        digest: receipt.digest,
        disposition: receipt.disposition,
      ).encode();
      await expectLater(reader().read(oldKey), throwsStateError);
      expect(reads, [markerKey]);
      expect(hashes, 0);
    },
  );

  test(
    'remote, ordinary-note and unowned-generation archive keys are refused before reading',
    () async {
      for (final namespace in [
        'local',
        jsonEncode(['https://server.test', 'article']),
        jsonEncode(['local-generation:${'a' * 32}', 'article']),
      ]) {
        final key = SecureRecordStore(
          prefix: 'bookstark.draft.v1',
          namespace: namespace,
          readValue: (_) async => null,
          writeValue: (_, _) async {},
          deleteValue: (_) async {},
        ).metadataKey(17);
        await expectLater(reader().read(key), throwsFormatException);
      }
      expect(reads, isEmpty);
      expect(hashes, 0);
    },
  );

  test(
    'a corrupted body cannot be accepted by a matching fake ciphertext fingerprint',
    () async {
      preferences[oldKey] = jsonEncode({
        'version': 1,
        'title': 'Changed',
        'content': '# changed',
        'labels': [],
      });
      final original = Map.of(preferences);
      await expectLater(reader().read(oldKey), throwsStateError);
      expect(preferences, original);
      expect(hashes, 1);
    },
  );

  test(
    'fingerprint changing after decryption prevents displaying a stale snapshot',
    () async {
      var count = 0;
      final original = Map.of(preferences);
      await expectLater(
        reader(
          fingerprint: (_) async => ++count == 1 ? 'c' * 64 : 'd' * 64,
        ).read(oldKey),
        throwsStateError,
      );
      expect(count, 2);
      expect(preferences, original);
    },
  );

  test(
    'receipt mutation or space retirement during read prevents a stale snapshot',
    () async {
      await expectLater(
        reader(
          read: (key) async {
            final value = preferences[key];
            if (key == oldKey) {
              preferences[markerKey] = LocalArticleDraftReceipt(
                digest: receipt.digest,
                disposition: LocalArticleDraftDisposition.matched,
                ciphertextSHA256: 'c' * 64,
              ).encode();
            }
            return value;
          },
        ).read(oldKey),
        throwsStateError,
      );
      preferences[markerKey] = receipt.encode();
      await expectLater(
        reader(
          read: (key) async {
            if (key == oldKey) current = false;
            return preferences[key];
          },
        ).read(oldKey),
        throwsStateError,
      );
    },
  );
}
