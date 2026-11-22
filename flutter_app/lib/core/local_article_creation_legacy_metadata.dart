import 'dart:convert';

/// Purpose-only identifiers for the old native *new article* (null-ID) draft.
/// This parser cannot authorize an existing-ID, ordinary-note or remote key.
class LocalArticleCreationLegacyScope {
  LocalArticleCreationLegacyScope._(
    this.legacyKey,
    this.markerKey,
    this.namespace,
    this.baseNamespace,
  );
  static const legacyPrefix = 'bookstark.draft.v1.';
  static const markerRecordPrefix =
      'bookstark.local-article-creation-draft-handoff.v1';
  static const markerPrefix = '$markerRecordPrefix.';
  final String legacyKey, markerKey, namespace, baseNamespace;
  factory LocalArticleCreationLegacyScope.fromLegacyKey(String key) {
    if (!key.startsWith(legacyPrefix) || key.length > 4096) {
      throw const FormatException('Invalid local article creation draft key');
    }
    final suffix = key.substring(legacyPrefix.length);
    final raw = utf8.decode(base64Url.decode(suffix), allowMalformed: false);
    final outer = jsonDecode(raw);
    if (outer is! List ||
        outer.length != 2 ||
        outer[0] is! String ||
        outer[1] != null) {
      throw const FormatException('Local article creation requires a null ID');
    }
    final inner = jsonDecode(outer[0] as String);
    if (inner is! List ||
        inner.length != 2 ||
        inner[0] is! String ||
        inner[1] != 'article') {
      throw const FormatException(
        'Local article creation draft scope required',
      );
    }
    return LocalArticleCreationLegacyScope.fromMarkerKey(
      markerPrefix + suffix,
      {inner[0] as String},
    );
  }
  factory LocalArticleCreationLegacyScope.fromMarkerKey(
    String key,
    Set<String> ownedNamespaces,
  ) {
    if (!key.startsWith(markerPrefix) || key.length > 4096) {
      throw const FormatException('Invalid article creation receipt key');
    }
    final suffix = key.substring(markerPrefix.length);
    final bytes = base64Url.decode(suffix);
    if (base64Url.encode(bytes) != suffix) {
      throw const FormatException('Noncanonical article creation draft key');
    }
    final raw = utf8.decode(bytes, allowMalformed: false);
    final outer = jsonDecode(raw);
    if (outer is! List ||
        outer.length != 2 ||
        outer[0] is! String ||
        outer[1] != null ||
        jsonEncode(outer) != raw) {
      throw const FormatException('Invalid article creation draft identity');
    }
    final namespace = outer[0] as String;
    final inner = jsonDecode(namespace);
    if (inner is! List ||
        inner.length != 2 ||
        inner[0] is! String ||
        inner[1] != 'article' ||
        jsonEncode(inner) != namespace) {
      throw const FormatException('Invalid article creation draft namespace');
    }
    final base = inner[0] as String;
    if (!ownedNamespaces.contains(base) ||
        base != 'local' &&
            !RegExp(r'^local-generation:[a-f0-9]{32}$').hasMatch(base)) {
      throw const FormatException(
        'Owned local article creation namespace required',
      );
    }
    return LocalArticleCreationLegacyScope._(
      legacyPrefix + suffix,
      key,
      namespace,
      base,
    );
  }
}

class LocalArticleCreationLegacyBinding {
  LocalArticleCreationLegacyBinding({
    required this.legacyKey,
    required this.digest,
    required this.ciphertextSHA256,
  }) {
    LocalArticleCreationLegacyScope.fromLegacyKey(legacyKey);
    if (!_hash.hasMatch(digest) || !_hash.hasMatch(ciphertextSHA256)) {
      throw const FormatException('Invalid legacy creation binding');
    }
  }
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final String legacyKey, digest, ciphertextSHA256;
  Map<String, Object?> toJson() => {
    'legacyKey': legacyKey,
    'digest': digest,
    'ciphertextSHA256': ciphertextSHA256,
  };
  factory LocalArticleCreationLegacyBinding.parse(Object? raw) {
    const fields = {'legacyKey', 'digest', 'ciphertextSHA256'};
    if (raw is! Map ||
        raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['legacyKey'] is! String ||
        raw['digest'] is! String ||
        raw['ciphertextSHA256'] is! String) {
      throw const FormatException('Invalid legacy creation binding');
    }
    return LocalArticleCreationLegacyBinding(
      legacyKey: raw['legacyKey'] as String,
      digest: raw['digest'] as String,
      ciphertextSHA256: raw['ciphertextSHA256'] as String,
    );
  }
  bool same(LocalArticleCreationLegacyBinding? other) =>
      other != null &&
      legacyKey == other.legacyKey &&
      digest == other.digest &&
      ciphertextSHA256 == other.ciphertextSHA256;
}

enum LocalArticleCreationLegacyDisposition { restored, skipped }

class LocalArticleCreationLegacyReceipt {
  LocalArticleCreationLegacyReceipt({
    required this.digest,
    required this.ciphertextSHA256,
    required this.disposition,
    required this.creationKey,
  }) {
    if (!LocalArticleCreationLegacyBinding._hash.hasMatch(digest) ||
        !LocalArticleCreationLegacyBinding._hash.hasMatch(ciphertextSHA256) ||
        (disposition == LocalArticleCreationLegacyDisposition.restored
            ? creationKey == null ||
                  !RegExp(r'^[a-f0-9]{32}$').hasMatch(creationKey!)
            : creationKey != null)) {
      throw const FormatException('Invalid legacy creation receipt');
    }
  }
  final String digest, ciphertextSHA256;
  final LocalArticleCreationLegacyDisposition disposition;
  final String? creationKey;
  String encode() => jsonEncode({
    'version': 1,
    'digest': digest,
    'ciphertextSHA256': ciphertextSHA256,
    'disposition': disposition.name,
    'creationKey': creationKey,
  });
  factory LocalArticleCreationLegacyReceipt.parse(String raw) {
    if (utf8.encode(raw).length > 1024) {
      throw const FormatException('Oversized legacy creation receipt');
    }
    final value = jsonDecode(raw);
    const fields = {
      'version',
      'digest',
      'ciphertextSHA256',
      'disposition',
      'creationKey',
    };
    if (value is! Map ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['digest'] is! String ||
        value['ciphertextSHA256'] is! String ||
        value['creationKey'] != null && value['creationKey'] is! String ||
        !LocalArticleCreationLegacyDisposition.values.any(
          (v) => v.name == value['disposition'],
        )) {
      throw const FormatException('Invalid legacy creation receipt');
    }
    return LocalArticleCreationLegacyReceipt(
      digest: value['digest'] as String,
      ciphertextSHA256: value['ciphertextSHA256'] as String,
      disposition: LocalArticleCreationLegacyDisposition.values.firstWhere(
        (v) => v.name == value['disposition'],
      ),
      creationKey: value['creationKey'] as String?,
    );
  }
}
