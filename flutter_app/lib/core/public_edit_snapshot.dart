import 'public_share_models.dart';

class PublicEditSnapshot {
  PublicEditSnapshot._(this.detail, this.modified);
  final PublicShareDetail detail;

  /// Opaque server wall-clock string; compare without inventing a timezone.
  final String modified;
  String get content => detail.content;
  String get format => detail.format;
  bool get locked => detail.locked;
  factory PublicEditSnapshot.parse(
    PublicShareDetail context,
    Map<String, Object?> row,
  ) {
    if (context.shareId <= 0 ||
        context.kind == PublicShareKind.book ||
        row['editable'] != true ||
        row['share_type'] != context.kind.name ||
        row['has_password'] is! bool ||
        row['has_password'] != context.protected) {
      throw StateError('Shared editing capability or protection changed');
    }
    final modified = row['modify_time'];
    if (modified is! String ||
        modified.isEmpty ||
        modified.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(modified)) {
      throw const FormatException('Missing actual modification receipt');
    }
    final declaredType = row['blog_type'];
    final hasDeclaredType = declaredType != null && declaredType != '';
    if (hasDeclaredType &&
        (context.kind != PublicShareKind.blog ||
            !{'note', 'article'}.contains(declaredType) ||
            context.blogType != null && context.blogType != declaredType)) {
      throw StateError('Shared editing collection changed');
    }
    var parsed = PublicShareDetail.fromJson(context.reference, {
      'share_type': context.kind.name,
      'share_id': context.shareId,
      'target_id': context.targetId,
      'share_identify': context.reference.identify,
      'has_password': row['has_password'],
      'doc_type': row['doc_type'],
      'blog_type': hasDeclaredType ? declaredType : context.blogType,
      'title': row['title'],
      'content': row['content'],
    });
    if (context.unlocked && parsed.locked && parsed.markdown) {
      parsed = parsed.unlockMarkdown(context.content);
    }
    return PublicEditSnapshot._(parsed, modified);
  }
  bool sameVersion(PublicEditSnapshot other) =>
      detail.reference == other.detail.reference &&
      detail.targetId == other.detail.targetId &&
      detail.kind == other.detail.kind &&
      detail.blogType == other.detail.blogType &&
      format == other.format &&
      detail.protected == other.detail.protected &&
      content == other.content &&
      modified == other.modified;
}
