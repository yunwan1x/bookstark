import 'dart:convert';

/// Ordinary draft scopes are nested JSON strings; server scopes must never
/// acquire a local maintenance lease or be included in a local backup.
class LocalDraftNamespace {
  static bool isLocal(String value) => _local(value, 0);

  static String generation(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid local generation identity');
    }
    return 'local-generation:$id';
  }

  static bool _local(String value, int depth) {
    if (value == 'local' ||
        RegExp(r'^local-generation:[a-f0-9]{32}$').hasMatch(value)) {
      return true;
    }
    if (depth >= 12 || value.length > 32768 || !value.startsWith('[')) {
      return false;
    }
    try {
      final decoded = jsonDecode(value);
      return decoded is List &&
          decoded.isNotEmpty &&
          decoded.first is String &&
          _local(decoded.first as String, depth + 1);
    } on FormatException {
      return false;
    }
  }
}
