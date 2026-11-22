import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'public_share_models.dart';

class ShareCommentCapabilities {
  const ShareCommentCapabilities({
    required this.enabled,
    required this.maxLength,
    required this.account,
  });
  final bool enabled;
  final int maxLength;
  final String account;
  bool get signedIn => account.isNotEmpty;
}

/// Read fixed server literals, never evaluate scripts or regex through a JSON
/// string. JSON strings occupy one source line in this legacy template.
ShareCommentCapabilities parseShareCommentCapabilities(
  String source,
  PublicShareReference reference,
) {
  final scripts = html
      .parse(source)
      .querySelectorAll('script')
      .where(
        (script) =>
            script.attributes['src'] == null &&
            script.text.trimLeft().startsWith('var shareContent = '),
      )
      .toList();
  if (scripts.length != 1) {
    throw const FormatException('Unknown public comment capability template');
  }
  final lines = scripts.single.text
      .split('\n')
      .map((line) => line.trim())
      .toList();
  Object? literal(String name) {
    final prefix = '$name = ';
    final matches = lines.where((line) => line.startsWith(prefix)).toList();
    if (matches.length != 1 || !matches.single.endsWith(';')) {
      throw const FormatException('Unknown public comment capability');
    }
    return jsonDecode(
      matches.single.substring(prefix.length, matches.single.length - 1),
    );
  }

  if (literal('var shareIdentify') != reference.identify) {
    throw const FormatException('Public comment context changed');
  }
  final enabled = literal('window.__SHARE_COMMENTS_ENABLED__'),
      max = literal('window.__SHARE_COMMENT_MAX_LENGTH__'),
      account = literal('window.__SHARE_COMMENT_ACCOUNT__');
  if (enabled is! bool ||
      max is! int ||
      max < 100 ||
      max > 5000 ||
      account is! String ||
      account.length > 1000) {
    throw const FormatException('Invalid public comment capabilities');
  }
  return ShareCommentCapabilities(
    enabled: enabled,
    maxLength: max,
    account: account,
  );
}

String _text(Object? value, {int max = 20000}) {
  if (value is! String || value.length > max) {
    throw const FormatException('Invalid public comment text');
  }
  // Reject unpaired surrogates rather than count replacement characters.
  for (var i = 0; i < value.length; i++) {
    final u = value.codeUnitAt(i);
    if (u >= 0xd800 && u <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid comment Unicode');
      }
    } else if (u >= 0xdc00 && u <= 0xdfff) {
      throw const FormatException('Invalid comment Unicode');
    }
  }
  return value;
}

class PublicShareComment {
  PublicShareComment._({
    required this.id,
    required this.parentId,
    required this.rootId,
    required this.replyToId,
    required this.author,
    required this.replyToAuthor,
    required this.content,
    required this.createdAt,
    required this.canDelete,
    required this.deleted,
    required List<PublicShareComment> replies,
  }) : replies = List.unmodifiable(replies);
  final int id, parentId, rootId, replyToId;
  final String author, replyToAuthor, content;
  final DateTime createdAt;
  final bool canDelete, deleted;
  final List<PublicShareComment> replies;
  static PublicShareComment parse(
    Map row,
    PublicShareDetail context, {
    Set<int>? seen,
    int? root,
  }) {
    final ids = seen ?? <int>{};
    final id = row['comment_id'],
        parent = row['parent_comment_id'],
        rootId = row['root_comment_id'],
        replyTo = row['reply_to_comment_id'];
    if (id is! int ||
        id <= 0 ||
        !ids.add(id) ||
        ids.length > 10000 ||
        parent is! int ||
        parent < 0 ||
        rootId is! int ||
        rootId <= 0 ||
        replyTo is! int ||
        replyTo < 0 ||
        row['target_type'] != context.kind.name ||
        row['target_id'] != context.targetId ||
        row['is_deleted'] is! bool ||
        row['can_delete'] is! bool ||
        (root == null && (parent != 0 || rootId != id || replyTo != 0)) ||
        (root != null &&
            (rootId != root || parent <= 0 || parent == id || replyTo == id))) {
      throw const FormatException('Invalid public comment membership');
    }
    final deleted = row['is_deleted'] as bool;
    final time = DateTime.tryParse(_text(row['create_time'], max: 128));
    if (time == null) throw const FormatException('Invalid comment date');
    final nested = row['replies'];
    if (nested != null &&
        (nested is! List || root != null && nested.isNotEmpty)) {
      throw const FormatException('Invalid flat public thread replies');
    }
    final replies = <PublicShareComment>[];
    if (nested is List) {
      for (final child in nested) {
        if (child is! Map) {
          throw const FormatException('Invalid public comment row');
        }
        replies.add(parse(child, context, seen: ids, root: id));
      }
    }
    return PublicShareComment._(
      id: id,
      parentId: parent,
      rootId: rootId,
      replyToId: replyTo,
      author: deleted ? '' : _text(row['author_name'], max: 1000),
      replyToAuthor: deleted
          ? ''
          : _text(row['reply_to_author_name'] ?? '', max: 1000),
      content: deleted ? '' : _text(row['content']),
      createdAt: time,
      canDelete: !deleted && row['can_delete'] == true,
      deleted: deleted,
      replies: replies,
    );
  }
}

class PublicShareCommentPage {
  PublicShareCommentPage._(
    this.page,
    this.pageSize,
    this.totalThreads,
    List<PublicShareComment> items,
  ) : items = List.unmodifiable(items);
  final int page, pageSize, totalThreads;
  final List<PublicShareComment> items;
  bool get hasNext => page * pageSize < totalThreads;
  factory PublicShareCommentPage.parse(
    Map<String, Object?> json,
    PublicShareDetail context, {
    required int requestedPage,
  }) {
    final page = json['page'],
        size = json['page_size'],
        total = json['total'],
        rows = json['data'];
    if (page != requestedPage ||
        size != 20 ||
        total is! int ||
        total < 0 ||
        rows is! List ||
        rows.length > 20 ||
        rows.length > total) {
      throw const FormatException('Invalid public comment pagination');
    }
    final seen = <int>{}, items = <PublicShareComment>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('Invalid public comment row');
      }
      items.add(PublicShareComment.parse(row, context, seen: seen));
    }
    return PublicShareCommentPage._(page as int, size as int, total, items);
  }
}

class PublicCommentInput {
  const PublicCommentInput({
    required this.content,
    this.author = '',
    this.email = '',
    this.parentId = 0,
    this.replyToId = 0,
  });
  final String content, author, email;
  final int parentId, replyToId;
  Map<String, Object?> body(ShareCommentCapabilities capability) {
    _text(content);
    _text(author);
    _text(email);
    if (!capability.enabled ||
        content.trim().isEmpty ||
        content.trim().runes.length > capability.maxLength ||
        !capability.signedIn && author.trim().isEmpty ||
        author.trim().runes.length > 40 ||
        email.trim().runes.length > 200 ||
        email.isNotEmpty && !email.contains('@') ||
        parentId < 0 ||
        replyToId < 0 ||
        parentId == 0 && replyToId != 0) {
      throw const FormatException('Invalid public comment input');
    }
    return {
      'content': content,
      'author_name': author.trim(),
      'author_email': email.trim(),
      'parent_comment_id': parentId,
      'reply_to_comment_id': replyToId,
    };
  }
}
