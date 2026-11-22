import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'local_article_draft_receipt.dart';
import 'local_article_creation_legacy_metadata.dart';

/// Shared with RecoveryStorageChannel. Keep the HTML journal separate from
/// login/other secure preferences, including its potentially large draft data.
class NativeRecoveryStorage {
  static const preferencesName = 'BookstarkHtmlRecovery';
  static const channel = MethodChannel('bookstark/recovery_storage');

  /// Ciphertext fingerprint only, for a canonical positive-ID local article
  /// draft key. Native rejects account, remote and ordinary-note identifiers.
  static Future<String?> localArticleDraftFingerprint(String key) =>
      _articleFingerprint(key, creation: false);

  static Future<String?> localArticleCreationDraftFingerprint(String key) =>
      _articleFingerprint(key, creation: true);

  static Future<String?> _articleFingerprint(
    String key, {
    required bool creation,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Native article draft metadata requires Android');
    }
    if (creation) {
      LocalArticleCreationLegacyScope.fromLegacyKey(key);
    } else {
      LocalArticleDraftReceiptScope.localLegacy(key);
    }
    final value = await channel
        .invokeMethod<Object?>(
          creation
              ? 'localArticleCreationDraftFingerprint'
              : 'localArticleDraftFingerprint',
          {'key': key},
        )
        .timeout(const Duration(seconds: 30));
    const fields = {
      'format',
      'key',
      'sha256',
      'ciphertextBytes',
      'valuesIncluded',
    };
    if (value is! Map ||
        value.length != fields.length ||
        !value.keys.toSet().containsAll(fields) ||
        value['format'] is! int ||
        value['format'] != 1 ||
        value['key'] != key ||
        value['valuesIncluded'] != false ||
        value['ciphertextBytes'] is! int) {
      throw const FormatException('Invalid article draft fingerprint response');
    }
    final bytes = value['ciphertextBytes'] as int;
    final hash = value['sha256'];
    if (bytes < 0 ||
        bytes > 32 * 1024 * 1024 ||
        (hash == null
            ? bytes != 0
            : bytes == 0 ||
                  hash is! String ||
                  !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))) {
      throw const FormatException('Invalid article draft fingerprint value');
    }
    return hash as String?;
  }

  static Future<void> flush() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final committed = await channel.invokeMethod<bool>('flush');
    if (committed != true) {
      throw StateError('Recovery write was not synchronized');
    }
  }
}
