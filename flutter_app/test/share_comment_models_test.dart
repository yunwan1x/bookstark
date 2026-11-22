import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';

final ref = PublicShareReference(Uri.parse('https://example.test'), 'actual');
PublicShareDetail context() => PublicShareDetail.fromJson(ref, {
  'share_type': 'blog',
  'share_id': -9,
  'target_id': 9,
  'share_identify': 'actual',
  'has_password': false,
  'title': 'Title',
  'doc_type': 'markdown',
  'content': 'Content',
});
Map<String, Object?> row(
  int id, {
  int parent = 0,
  int? root,
  bool deleted = false,
}) => {
  'comment_id': id,
  'target_type': 'blog',
  'target_id': 9,
  'share_identify': 'actual',
  'parent_comment_id': parent,
  'root_comment_id': root ?? id,
  'reply_to_comment_id': parent,
  'reply_to_author_name': 'Actual parent',
  'author_name': 'Public name',
  'content': 'Actual public content',
  'create_time': '2026-11-05T08:00:00Z',
  'can_delete': true,
  'is_deleted': deleted,
  'author_email': 'must never enter UI',
  'ip_hash': 'must never enter UI',
};
String template({
  bool enabled = true,
  int max = 2000,
  String identify = 'actual',
}) =>
    '''
<script>
var shareContent = ${jsonEncode('window.__SHARE_COMMENT_MAX_LENGTH__ = 1;\nwindow.__SHARE_COMMENTS_ENABLED__ = false;')};
var shareIdentify = ${jsonEncode(identify)};
window.__SHARE_COMMENTS_ENABLED__ = $enabled;
window.__SHARE_COMMENT_ACCOUNT__ = "";
window.__SHARE_COMMENT_MAX_LENGTH__ = $max;
function ignored() { throw new Error('must never execute'); }
</script>
''';
void main() {
  test(
    'fixed inert capabilities ignore script-looking content and distinguish disabled from unknown',
    () {
      final cap = parseShareCommentCapabilities(template(), ref);
      expect(cap.enabled, isTrue);
      expect(cap.maxLength, 2000);
      expect(cap.signedIn, isFalse);
      expect(
        parseShareCommentCapabilities(template(enabled: false), ref).enabled,
        isFalse,
      );
      for (final html in [
        template(max: 99),
        template(identify: 'foreign'),
        '<html>login</html>',
        template() + template(),
      ]) {
        expect(
          () => parseShareCommentCapabilities(html, ref),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'deleted content and author are discarded while actual flat-thread membership survives absent deleted parents',
    () {
      final root = row(1, deleted: true)
        ..['replies'] = [row(4, parent: 3, root: 1)];
      final parsed = PublicShareComment.parse(root, context());
      expect(parsed.content, isEmpty);
      expect(parsed.author, isEmpty);
      expect(parsed.canDelete, isFalse);
      expect(parsed.replies.single.id, 4);
      expect(parsed.replies.single.parentId, 3);
      final foreign = row(1)..['target_id'] = 8;
      expect(
        () => PublicShareComment.parse(foreign, context()),
        throwsFormatException,
      );
      final duplicate = row(1)..['replies'] = [row(1, parent: 1, root: 1)];
      expect(
        () => PublicShareComment.parse(duplicate, context()),
        throwsFormatException,
      );
    },
  );
  test(
    'actual API pagination counts root threads independently from replies',
    () {
      final page = PublicShareCommentPage.parse(
        {
          'page': 1,
          'page_size': 20,
          'total': 21,
          'data': [
            row(1)..['replies'] = [row(2, parent: 1, root: 1)],
          ],
        },
        context(),
        requestedPage: 1,
      );
      expect(page.items.length, 1);
      expect(page.items.single.replies.length, 1);
      expect(page.totalThreads, 21);
      expect(page.hasNext, isTrue);
      expect(
        () => PublicShareCommentPage.parse(
          {'page': 2, 'page_size': 20, 'total': 0, 'data': []},
          context(),
          requestedPage: 1,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'real Unicode scalar limit, anonymous name and email validation precede any write',
    () {
      const cap = ShareCommentCapabilities(
        enabled: true,
        maxLength: 100,
        account: '',
      );
      final emoji = List.filled(100, '📚').join();
      expect(
        PublicCommentInput(
          content: emoji,
          author: 'Visitor',
        ).body(cap)['content'],
        emoji,
      );
      for (final value in [
        PublicCommentInput(content: '${emoji}x', author: 'Visitor'),
        const PublicCommentInput(content: 'Body'),
        const PublicCommentInput(
          content: 'Body',
          author: 'Visitor',
          email: 'invalid',
        ),
        const PublicCommentInput(
          content: 'Body',
          author: 'Visitor',
          replyToId: 3,
        ),
      ]) {
        expect(() => value.body(cap), throwsFormatException);
      }
      const signed = ShareCommentCapabilities(
        enabled: true,
        maxLength: 2000,
        account: 'Actual account',
      );
      expect(
        const PublicCommentInput(content: 'Body').body(signed)['content'],
        'Body',
      );
    },
  );
}
