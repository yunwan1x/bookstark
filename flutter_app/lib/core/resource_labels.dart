/// The legacy API splits ASCII/Chinese commas without CSV escaping or trim.
/// Preserve existing whitespace and fail before any resource mutation if a
/// single selected label cannot be represented without changing its identity.
String encodeResourceLabels(List<String> labels) {
  if (labels.any((name) => name.isEmpty || name.contains(RegExp('[,，]')))) {
    throw const FormatException(
      '标签包含旧接口无法保存的分隔符，请先调整标签 / A label cannot be represented by the legacy API',
    );
  }
  return labels.toSet().join(',');
}
