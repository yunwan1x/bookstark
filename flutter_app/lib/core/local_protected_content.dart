/// ENC: is the reserved local protection-envelope namespace, including unknown
/// versions. One optional standard BOM is preserved; embedded prose is allowed.
bool isLocalProtectedEnvelopePrefix(String content) =>
    (content.startsWith('\ufeff') ? content.substring(1) : content).startsWith(
      'ENC:',
    );

/// For hex(substr(CAST(content AS BLOB),1,7)): no full source/ciphertext is
/// materialized in Android CursorWindow merely to determine its protection.
bool isLocalProtectedEnvelopeHexPrefix(Object? prefix) =>
    prefix is String &&
    (prefix.startsWith('454E433A') || prefix.startsWith('EFBBBF454E433A'));
