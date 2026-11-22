import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';

final server = Uri.parse('https://example.test/base');
PublicShareDetail context() =>
    PublicShareDetail.fromJson(PublicShareReference(server, '实际%2F+'), {
      'share_type': 'blog',
      'share_id': -9,
      'target_id': 9,
      'share_identify': '实际%2F+',
      'has_password': false,
      'title': 'Actual public title',
      'doc_type': 'markdown',
      'content': 'Body',
    });
Map<String, Object?> row() => {
  'comment_id': 31,
  'target_type': 'blog',
  'target_id': 9,
  'share_identify': '实际%2F+',
  'parent_comment_id': 0,
  'root_comment_id': 31,
  'reply_to_comment_id': 0,
  'author_name': 'Actual account',
  'reply_to_author_name': '',
  'content': 'Actual body',
  'create_time': '2026-11-05T08:00:00Z',
  'can_delete': true,
  'is_deleted': false,
};
http.Response json(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Repository implements ShareCommentsRepository {
  int creates = 0;
  Object? failure;
  @override
  Future<PublicShareComment> create(
    PublicShareDetail detail,
    ShareCommentCapabilities cap,
    PublicCommentInput input,
  ) async {
    creates++;
    if (failure != null) throw failure!;
    return PublicShareComment.parse(row(), detail);
  }

  @override
  Future<ShareCommentCapabilities> capabilities(
    PublicShareDetail detail, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
  @override
  Future<PublicShareCommentPage> list(
    PublicShareDetail detail,
    int page, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
  @override
  Future<void> remove(
    PublicShareDetail detail,
    PublicShareComment comment,
  ) async => throw UnimplementedError();
}

void main() {
  const cap = ShareCommentCapabilities(
    enabled: true,
    maxLength: 2000,
    account: 'Actual account',
  );
  test(
    'real list shape and create/delete requests keep exact public context and actual receipt ID',
    () async {
      final methods = <String>[];
      final client = BookstarkClient(
        server.toString(),
        transport: MockClient((r) async {
          methods.add(r.method);
          expect(r.followRedirects, isFalse);
          expect(r.url.origin, server.origin);
          if (r.method == 'GET') {
            expect(r.url.pathSegments, [
              'base',
              'api',
              'shares',
              '实际%2F+',
              'comments',
            ]);
            expect(r.url.queryParameters, {'page': '2', 'page_size': '20'});
            return json({
              'code': 0,
              'data': [row()],
              'total': 21,
              'page': 2,
              'page_size': 20,
            });
          }
          expect(r.headers['x-csrf-token'], 'csrf');
          if (r.method == 'POST') {
            expect(jsonDecode(r.body)['content'], 'Actual body');
            expect(r.url.hasQuery, isFalse);
            return json({'code': 0, 'data': row()});
          }
          expect(r.url.path, '/base/api/share-comments/31');
          expect(r.url.queryParameters, {'identify': '实际%2F+'});
          return json({'code': 0});
        }),
      );
      client.restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteShareCommentsRepository(client);
      final page = await repo.list(context(), 2);
      expect(page.items.single.id, 31);
      final value = await repo.create(
        context(),
        cap,
        const PublicCommentInput(content: 'Actual body'),
      );
      await repo.remove(context(), value);
      expect(methods, ['GET', 'POST', 'DELETE']);
      client.close();
    },
  );
  test(
    'actual capability page is fixed, bounded and never executes scripts',
    () async {
      final client = BookstarkClient(
        server.toString(),
        transport: MockClient((r) async {
          expect(r.url.pathSegments, ['base', 'shares', '实际%2F+']);
          expect(r.url.hasQuery, isFalse);
          return http.Response.bytes(
            utf8.encode('''<script>
var shareContent = "";
var shareIdentify = ${jsonEncode('实际%2F+')};
window.__SHARE_COMMENTS_ENABLED__ = false;
window.__SHARE_COMMENT_ACCOUNT__ = "Actual account";
window.__SHARE_COMMENT_MAX_LENGTH__ = 5000;
throw new Error('never execute');
</script>'''),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      final capabilities = await RemoteShareCommentsRepository(
        client,
      ).capabilities(context());
      expect(capabilities.enabled, isFalse);
      expect(capabilities.maxLength, 5000);
      expect(capabilities.account, 'Actual account');
      client.close();
    },
  );
  test(
    'unknown or acknowledged submission cannot repeat; definite rejection can be corrected',
    () async {
      final repo = Repository()..failure = StateError('connection lost');
      final submit = PublicCommentSubmission(repo, context());
      const input = PublicCommentInput(content: 'Actual body');
      await expectLater(submit.submit(cap, input), throwsStateError);
      expect(submit.phase, PublicCommentSubmissionPhase.unknown);
      await expectLater(submit.submit(cap, input), throwsStateError);
      expect(repo.creates, 1);
      expect(() => submit.reset(acknowledgeUnknown: false), throwsStateError);
      submit.reset(acknowledgeUnknown: true);
      repo.failure = const ApiFailure(429, 'rate limit');
      await expectLater(submit.submit(cap, input), throwsA(isA<ApiFailure>()));
      repo.failure = null;
      expect((await submit.submit(cap, input)).id, 31);
      await expectLater(submit.submit(cap, input), throwsStateError);
      expect(repo.creates, 3);
      expect(submit.receipt!.id, 31);
    },
  );
  test('invalid anonymous input performs no create', () async {
    final repo = Repository();
    const anonymous = ShareCommentCapabilities(
      enabled: true,
      maxLength: 100,
      account: '',
    );
    final actual = PublicCommentSubmission(repo, context());
    await expectLater(
      actual.submit(anonymous, const PublicCommentInput(content: 'Body')),
      throwsFormatException,
    );
    expect(repo.creates, 0);
    expect(actual.phase, PublicCommentSubmissionPhase.editing);
  });
  test(
    'forged reply receipt blocks retry instead of creating another comment',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        server.toString(),
        transport: MockClient((_) async {
          calls++;
          return json({'code': 0, 'data': row()});
        }),
      );
      client.restoreSession({'csrf_token': 'csrf'});
      final submit = PublicCommentSubmission(
        RemoteShareCommentsRepository(client),
        context(),
      );
      const input = PublicCommentInput(
        content: 'Actual body',
        parentId: 2,
        replyToId: 2,
      );
      await expectLater(submit.submit(cap, input), throwsFormatException);
      expect(submit.phase, PublicCommentSubmissionPhase.unknown);
      await expectLater(submit.submit(cap, input), throwsStateError);
      expect(calls, 1);
      client.close();
    },
  );
}
