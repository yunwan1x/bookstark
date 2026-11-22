import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';
import 'public_shares.dart';

class ShareCommentsFixture implements ShareCommentsRepository {
  static PublicShareDetail detail() =>
      PublicShareDetail.fromJson(PublicSharesFixture.reference('public'), {
        'share_type': 'blog',
        'share_id': -7,
        'target_id': 7,
        'share_identify': 'public',
        'has_password': false,
        'title': '选择适合自己的书',
        'doc_type': 'markdown',
        'content': PublicSharesFixture.body,
      });
  static Map<String, Object?> row(
    int id,
    String name,
    String content, {
    int parent = 0,
    int? root,
  }) => {
    'comment_id': id,
    'parent_comment_id': parent,
    'root_comment_id': root ?? id,
    'reply_to_comment_id': parent,
    'target_type': 'blog',
    'target_id': 7,
    'share_identify': 'public',
    'author_name': name,
    'reply_to_author_name': parent > 0 ? '小林' : '',
    'content': content,
    'create_time': '2026-11-05T08:00:00+08:00',
    'can_delete': id == 1,
    'is_deleted': false,
  };
  final rows = <Map<String, Object?>>[
    row(1, '小林', '从一个问题出发，确实更容易坚持阅读。')
      ..['replies'] = [row(2, '阿青', '我也准备从工作中的问题开始选书。', parent: 1, root: 1)],
    row(3, '阿远', '先选能读懂的，再逐渐增加难度。'),
  ];
  bool enabled = true;
  int _next = 4;
  @override
  Future<ShareCommentCapabilities> capabilities(
    PublicShareDetail context, {
    Future<void>? abortTrigger,
  }) async =>
      ShareCommentCapabilities(enabled: enabled, maxLength: 2000, account: '');
  @override
  Future<PublicShareCommentPage> list(
    PublicShareDetail context,
    int page, {
    Future<void>? abortTrigger,
  }) async => PublicShareCommentPage.parse(
    {
      'page': page,
      'page_size': 20,
      'total': enabled ? rows.length : 0,
      'data': enabled && page == 1 ? rows : [],
    },
    context,
    requestedPage: page,
  );
  @override
  Future<PublicShareComment> create(
    PublicShareDetail context,
    ShareCommentCapabilities cap,
    PublicCommentInput input,
  ) async {
    input.body(cap);
    final id = _next++;
    Map<String, Object?>? parent;
    for (final root in rows) {
      for (final value in [
        root,
        ...(root['replies'] as List? ?? []).cast<Map<String, Object?>>(),
      ]) {
        if (value['comment_id'] == input.parentId) parent = value;
      }
    }
    final rootId = input.parentId == 0 ? id : parent!['root_comment_id'] as int;
    final value = row(
      id,
      input.author,
      input.content,
      parent: input.parentId,
      root: rootId,
    )..['can_delete'] = true;
    if (input.parentId == 0) {
      rows.insert(0, value);
    } else {
      final root = rows.singleWhere((root) => root['comment_id'] == rootId);
      (root.putIfAbsent('replies', () => []) as List).add(value);
    }
    return PublicShareComment.parse(
      value,
      context,
      root: input.parentId == 0 ? null : rootId,
    );
  }

  @override
  Future<void> remove(
    PublicShareDetail context,
    PublicShareComment comment,
  ) async {
    for (final root in List.of(rows)) {
      if (root['comment_id'] == comment.id) {
        if ((root['replies'] as List? ?? []).isEmpty) {
          rows.remove(root);
        } else {
          root['is_deleted'] = true;
          root['can_delete'] = false;
        }
      } else {
        (root['replies'] as List?)?.removeWhere(
          (value) => value['comment_id'] == comment.id,
        );
      }
    }
  }
}
