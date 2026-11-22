import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';

String legacyKey(
  Object? id, {
  String base = 'local',
  String collection = 'article',
  bool spaced = false,
}) {
  final scope = jsonEncode([base, collection]);
  final raw = spaced ? '[${jsonEncode(scope)}, null]' : jsonEncode([scope, id]);
  return 'bookstark.draft.v1.${base64Url.encode(utf8.encode(raw))}';
}

void main() {
  test('only canonical owned null-ID article scopes resolve', () {
    final key = legacyKey(null);
    final scope = LocalArticleCreationLegacyScope.fromLegacyKey(key);
    expect(scope.legacyKey, key);
    expect(scope.baseNamespace, 'local');
    expect(scope.namespace, jsonEncode(['local', 'article']));
    expect(
      LocalArticleCreationLegacyScope.fromMarkerKey(scope.markerKey, {
        'local',
      }).legacyKey,
      key,
    );
    final generation = 'local-generation:${'a' * 32}';
    expect(
      LocalArticleCreationLegacyScope.fromLegacyKey(
        legacyKey(null, base: generation),
      ).baseNamespace,
      generation,
    );
  });
  test(
    'positive ordinary remote malformed and noncanonical keys cannot authorize a read',
    () {
      for (final key in [
        legacyKey(1),
        legacyKey(0),
        legacyKey(false),
        legacyKey('new'),
        legacyKey(null, collection: 'note'),
        legacyKey(null, base: 'https://example.invalid'),
        legacyKey(null, base: 'local-generation:wrong'),
        legacyKey(null, spaced: true),
        legacyKey(null).replaceAll('=', ''),
        'account',
        'bookstark.draft.v1.not-base64',
      ]) {
        expect(
          () => LocalArticleCreationLegacyScope.fromLegacyKey(key),
          throwsFormatException,
        );
      }
    },
  );
  test('a valid retained namespace is still refused when not owned', () {
    final scope = LocalArticleCreationLegacyScope.fromLegacyKey(
      legacyKey(null),
    );
    expect(
      () => LocalArticleCreationLegacyScope.fromMarkerKey(scope.markerKey, {
        'local-generation:${'b' * 32}',
      }),
      throwsFormatException,
    );
  });
  test(
    'authenticated binding contains identifiers and hashes only and is closed',
    () {
      final binding = LocalArticleCreationLegacyBinding(
        legacyKey: legacyKey(null),
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
      );
      expect(binding.toJson().keys.toSet(), {
        'legacyKey',
        'digest',
        'ciphertextSHA256',
      });
      expect(
        LocalArticleCreationLegacyBinding.parse(binding.toJson()).same(binding),
        isTrue,
      );
      expect(
        () => LocalArticleCreationLegacyBinding.parse({
          ...binding.toJson(),
          'source': 'must not enter metadata',
        }),
        throwsFormatException,
      );
      expect(
        () => LocalArticleCreationLegacyBinding(
          legacyKey: legacyKey(1),
          digest: 'a' * 64,
          ciphertextSHA256: 'b' * 64,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'restored receipt binds one creation key while skipped receipt has no link',
    () {
      final restored = LocalArticleCreationLegacyReceipt(
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
        disposition: LocalArticleCreationLegacyDisposition.restored,
        creationKey: 'c' * 32,
      );
      expect(
        LocalArticleCreationLegacyReceipt.parse(restored.encode()).creationKey,
        'c' * 32,
      );
      final skipped = LocalArticleCreationLegacyReceipt(
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
        disposition: LocalArticleCreationLegacyDisposition.skipped,
        creationKey: null,
      );
      expect(
        LocalArticleCreationLegacyReceipt.parse(skipped.encode()).creationKey,
        isNull,
      );
      expect(
        () => LocalArticleCreationLegacyReceipt(
          digest: 'a' * 64,
          ciphertextSHA256: 'b' * 64,
          disposition: LocalArticleCreationLegacyDisposition.restored,
          creationKey: null,
        ),
        throwsFormatException,
      );
      expect(
        () => LocalArticleCreationLegacyReceipt(
          digest: 'a' * 64,
          ciphertextSHA256: 'b' * 64,
          disposition: LocalArticleCreationLegacyDisposition.skipped,
          creationKey: 'c' * 32,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'receipt rejects open metadata numeric version ambiguity and oversized values',
    () {
      final good = LocalArticleCreationLegacyReceipt(
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
        disposition: LocalArticleCreationLegacyDisposition.restored,
        creationKey: 'c' * 32,
      );
      final raw = jsonDecode(good.encode()) as Map<String, dynamic>;
      for (final patch in [
        {'version': 1.0},
        {'disposition': 'saved'},
        {'digest': 'not-a-hash'},
        {'ciphertextSHA256': 'A' * 64},
        {'creationKey': 'd' * 31},
        {'body': 'forbidden'},
      ]) {
        expect(
          () => LocalArticleCreationLegacyReceipt.parse(
            jsonEncode({...raw, ...patch}),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => LocalArticleCreationLegacyReceipt.parse(' ' * 1025),
        throwsFormatException,
      );
    },
  );
}
