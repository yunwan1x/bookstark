import 'dart:convert';
import 'package:crypto/crypto.dart';

enum LocalArticleDraftDisposition { restored, skipped, matched }

/// Metadata only. No title, content, password or key material is serialized.
final class LocalArticleDraftReceipt {
  LocalArticleDraftReceipt({
    required this.digest,
    required this.disposition,
    this.ciphertextSHA256,
  }) {
    if (!_hash.hasMatch(digest) ||
        ciphertextSHA256 != null && !_hash.hasMatch(ciphertextSHA256!)) {
      throw const FormatException('Invalid article draft receipt');
    }
  }
  static const recordPrefix = 'bookstark.local-article-draft-handoff.v1';
  static const keyPrefix = '$recordPrefix.';
  static const legacyKeyPrefix = 'bookstark.draft.v1.';
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final String digest;
  final LocalArticleDraftDisposition disposition;
  final String? ciphertextSHA256;
  int get version => ciphertextSHA256 == null ? 1 : 2;
  static String digestOf({
    required String namespace,
    required int id,
    required String title,
    required String source,
    required List<String> labels,
  }) => sha256
      .convert(utf8.encode(jsonEncode([namespace, id, title, source, labels])))
      .toString();

  String encode() => jsonEncode({
    'version': version,
    'digest': digest,
    'disposition': disposition.name,
    if (ciphertextSHA256 != null) 'ciphertext_sha256': ciphertextSHA256,
  });

  factory LocalArticleDraftReceipt.parse(String raw) {
    if (utf8.encode(raw).length > 1024) {
      throw const FormatException('Oversized article draft receipt');
    }
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] is! int ||
        !{1, 2}.contains(value['version'])) {
      throw const FormatException('Invalid article draft receipt');
    }
    final keys = {
      'version',
      'digest',
      'disposition',
      if (value['version'] == 2) 'ciphertext_sha256',
    };
    if (value.length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['digest'] is! String ||
        !LocalArticleDraftDisposition.values.any(
          (v) => v.name == value['disposition'],
        ) ||
        value['version'] == 2 && value['ciphertext_sha256'] is! String) {
      throw const FormatException('Invalid article draft receipt');
    }
    return LocalArticleDraftReceipt(
      digest: value['digest'] as String,
      disposition: LocalArticleDraftDisposition.values.firstWhere(
        (v) => v.name == value['disposition'],
      ),
      ciphertextSHA256: value['ciphertext_sha256'] as String?,
    );
  }
}

/// Resolves identifiers against the current owned article namespaces only.
final class LocalArticleDraftReceiptScope {
  LocalArticleDraftReceiptScope._(
    this.markerKey,
    this.namespace,
    this.id,
    this.legacyKey,
  );
  final String markerKey, namespace, legacyKey;
  final int id;
  factory LocalArticleDraftReceiptScope.localLegacy(String key) {
    if (!key.startsWith(LocalArticleDraftReceipt.legacyKeyPrefix) ||
        key.length > 4096) {
      throw const FormatException('Invalid local article draft key');
    }
    final suffix = key.substring(
      LocalArticleDraftReceipt.legacyKeyPrefix.length,
    );
    final outer = jsonDecode(utf8.decode(base64Url.decode(suffix)));
    if (outer is! List || outer.length != 2 || outer[0] is! String) {
      throw const FormatException('Invalid local article draft scope');
    }
    final inner = jsonDecode(outer[0] as String);
    if (inner is! List ||
        inner.length != 2 ||
        inner[0] is! String ||
        inner[1] != 'article' ||
        (inner[0] != 'local' &&
            !RegExp(
              r'^local-generation:[a-f0-9]{32}$',
            ).hasMatch(inner[0] as String))) {
      throw const FormatException('Local article draft scope required');
    }
    return LocalArticleDraftReceiptScope.parse(
      LocalArticleDraftReceipt.keyPrefix + suffix,
      {inner[0] as String},
    );
  }

  factory LocalArticleDraftReceiptScope.parse(
    String key,
    Set<String> localNamespaces,
  ) {
    if (!key.startsWith(LocalArticleDraftReceipt.keyPrefix) ||
        utf8.encode(key).length > 65536) {
      throw const FormatException('Invalid article receipt key');
    }
    final suffix = key.substring(LocalArticleDraftReceipt.keyPrefix.length);
    final bytes = base64Url.decode(suffix);
    if (base64Url.encode(bytes) != suffix) {
      throw const FormatException('Noncanonical article receipt key');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    final scopes = {
      for (final namespace in localNamespaces)
        jsonEncode([namespace, 'article']),
    };
    if (decoded is! List ||
        decoded.length != 2 ||
        decoded[0] is! String ||
        !scopes.contains(decoded[0]) ||
        decoded[1] is! int ||
        (decoded[1] as int) <= 0) {
      throw const FormatException('Unowned article receipt key');
    }
    return LocalArticleDraftReceiptScope._(
      key,
      decoded[0] as String,
      decoded[1] as int,
      LocalArticleDraftReceipt.legacyKeyPrefix + suffix,
    );
  }
}
