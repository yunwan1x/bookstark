import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_community_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_friend_links_models.dart';
import 'package:bookstark_flutter/features/admin/admin_comment_models.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture-owner', role: 0);
Map<String, Object?> link() => {
  'link_id': 1,
  'link_name': 'fixture-link',
  'link_url': 'https://example.invalid/docs',
  'group_name': 'fixture',
  'group_order': 0,
  'sort_weight': 10,
  'is_enabled': 1,
  'qr_code': '/upload-files/a%25.png',
  'description': 'unchanged note',
  'future': {'keep': true},
};
Map<String, Object?> comment(int id) => {
  'comment_id': id,
  'target_type': 'document',
  'target_id': 5,
  'share_identify': 'fixture-share',
  'parent_comment_id': 0,
  'root_comment_id': id,
  'reply_to_comment_id': 0,
  'reply_to_author_name': '',
  'author_member_id': 0,
  'author_name': 'fixture-author',
  'content': 'fixture-body',
  'status': 'visible',
  'create_time': '2026-11-07T00:00:00Z',
  'modify_time': '2026-11-07T00:00:00Z',
};

class Harness {
  Harness() {
    client = BookstarkClient(
      'https://example.invalid/root',
      transport: MockClient(handle),
    );
    client.restoreSession({
      'token': 'owned-test-session',
      'csrf_token': 'owned-test-csrf',
    });
    links = AdminFriendLinksRepository(client);
    comments = AdminCommentsRepository(client);
  }
  late final BookstarkClient client;
  late final AdminFriendLinksRepository links;
  late final AdminCommentsRepository comments;
  final calls = <http.Request>[];
  List<Map<String, Object?>> friendRows = [link()],
      commentRows = [comment(2), comment(1)];
  int profileRole = 0, writeStatus = 200, deleted = 3;
  bool loseReply = false,
      badReceipt = false,
      failProfile = false,
      changeLinks = false,
      changeComment = false,
      invalidRead = false,
      redirect = false;
  Completer<void>? profileGate;
  int get puts => calls.where((r) => r.method == 'PUT').length;
  int get posts => calls.where((r) => r.method == 'POST').length;
  http.Response reply(Object? data, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path;
    if (path == '/root/api/profile') {
      if (profileGate != null) await profileGate!.future;
      if (failProfile) throw http.ClientException('owned preflight fault');
      return reply({
        'code': 0,
        'data': {
          'member_id': 1,
          'account': 'fixture-owner',
          'role': profileRole,
        },
      });
    }
    if (path == '/root/api/csrf-token') return reply({'code': 0, 'data': {}});
    if (path == '/root/api/admin/friend-links' && request.method == 'GET') {
      if (redirect) return reply({'message': 'fixture-private'}, 302);
      if (invalidRead) {
        return http.Response.bytes(
          [255],
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return reply({
        'code': 0,
        'data': {
          'items': [
            for (final row in friendRows)
              {...row, if (changeLinks) 'link_name': 'other-admin-change'},
          ],
          'simple_mode': false,
        },
      });
    }
    if (path == '/root/api/admin/share-comments' && request.method == 'GET') {
      final page = int.parse(request.url.queryParameters['page']!);
      return reply({
        'code': 0,
        'data': page == 1
            ? [
                for (final row in commentRows)
                  {...row, if (changeComment) 'content': 'other-content'},
              ]
            : [],
        'total': commentRows.length,
        'page': page,
        'page_size': 20,
        'total_pages': 1,
      });
    }
    if ((path == '/root/api/admin/friend-links' && request.method == 'PUT') ||
        (path == '/root/api/admin/share-comments/delete' &&
            request.method == 'POST')) {
      if (loseReply) {
        throw http.ClientException('owned dropped reply after commit');
      }
      if (writeStatus != 200) {
        return reply({
          'code': writeStatus,
          'message': 'fixture-private',
        }, writeStatus);
      }
      if (badReceipt) {
        return reply({
          'data': {'deleted': 3},
        });
      }
      if (request.method == 'PUT') {
        return reply({'code': 0, 'message': 'saved'});
      }
      return reply({
        'code': 0,
        'data': {'deleted': deleted},
      });
    }
    throw StateError('Unexpected fixed-route request');
  }

  void dispose() {
    links.dispose();
    comments.dispose();
    client.close();
  }
}

AdminFriendLinksSnapshot draft(AdminFriendLinksSnapshot baseline) =>
    AdminFriendLinksSnapshot(
      items: [
        for (final item in baseline.items) item.edit(name: 'changed fixture'),
      ],
      simpleMode: true,
    );

void main() {
  test(
    'links fresh owner and exact full replacement preserve QR and unknown fields',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final baseline = await h.links.read(owner);
      expect(h.calls.map((r) => r.url.path).toList(), [
        '/root/api/profile',
        '/root/api/admin/friend-links',
      ]);
      var submitted = 0;
      await h.links.replace(
        owner,
        baseline,
        draft(baseline),
        onSubmitted: () => submitted++,
      );
      expect(submitted, 1);
      expect(h.puts, 1);
      final request = h.calls.last;
      expect(request.headers['x-csrf-token'], 'owned-test-csrf');
      expect(request.followRedirects, isFalse);
      final body = jsonDecode(request.body) as Map;
      expect(body['simple_mode'], true);
      expect(body['items'][0]['qr_code'], '/upload-files/a%25.png');
      expect(body['items'][0]['future'], {'keep': true});
      expect(h.calls.where((r) => r.method == 'GET').length, 4);
      await expectLater(
        h.links.replace(owner, baseline, draft(baseline)),
        throwsA(isA<AdminCommunityTargetChanged>()),
      );
      expect(h.puts, 1);
    },
  );
  test('friend semantic preflight change sends no write', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final base = await h.links.read(owner);
    h.changeLinks = true;
    await expectLater(
      h.links.replace(owner, base, draft(base)),
      throwsA(isA<AdminCommunityTargetChanged>()),
    );
    expect(h.puts, 0);
  });
  test(
    'invalid whole-link draft never starts preflight or transport',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final base = await h.links.read(owner);
      final count = h.calls.length;
      await expectLater(
        h.links.replace(
          owner,
          base,
          AdminFriendLinksSnapshot(
            items: [AdminFriendLink.create()],
            simpleMode: false,
          ),
        ),
        throwsFormatException,
      );
      expect(h.calls.length, count);
    },
  );
  test(
    'lost friend reply is unknown, invalidates prior review and never auto replays',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final base = await h.links.read(owner);
      h.loseReply = true;
      await expectLater(
        h.links.replace(owner, base, draft(base)),
        throwsA(isA<AdminCommunityWriteUnknown>()),
      );
      expect(h.puts, 1);
      await expectLater(
        h.links.replace(owner, base, draft(base)),
        throwsA(isA<AdminCommunityTargetChanged>()),
      );
      await h.links.read(owner);
      expect(h.puts, 1);
    },
  );
  test(
    'friend malformed success is unknown rather than a fabricated acknowledgement',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final base = await h.links.read(owner);
      h.badReceipt = true;
      await expectLater(
        h.links.replace(owner, base, draft(base)),
        throwsA(isA<AdminCommunityWriteUnknown>()),
      );
      expect(h.puts, 1);
    },
  );
  test(
    'preflight failure is distinct from a submitted unknown write',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final base = await h.links.read(owner);
      h.failProfile = true;
      await expectLater(
        h.links.replace(owner, base, draft(base)),
        throwsA(isA<http.ClientException>()),
      );
      expect(h.puts, 0);
    },
  );
  for (final status in [400, 404, 429]) {
    test(
      'member administration write refusal HTTP$status retains only controlled diagnostics',
      () async {
        final h = Harness();
        addTearDown(h.dispose);
        final base = await h.links.read(owner);
        h.writeStatus = status;
        await expectLater(
          h.links.replace(owner, base, draft(base)),
          throwsA(
            isA<AdminCommunityOperationRefused>().having(
              (e) => e.status,
              'status',
              status,
            ),
          ),
        );
        expect(h.puts, 1);
      },
    );
  }
  for (final status in [401, 403]) {
    test(
      'administration HTTP$status clears review and remains authorization failure',
      () async {
        final h = Harness();
        addTearDown(h.dispose);
        final base = await h.links.read(owner);
        h.writeStatus = status;
        await expectLater(
          h.links.replace(owner, base, draft(base)),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', status)),
        );
        await expectLater(
          h.links.replace(owner, base, draft(base)),
          throwsA(isA<AdminCommunityTargetChanged>()),
        );
        expect(h.puts, 1);
      },
    );
  }
  test('fresh operator demotion stops before friend write', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final base = await h.links.read(owner);
    h.profileRole = 1;
    await expectLater(
      h.links.replace(owner, base, draft(base)),
      throwsA(isA<AdminCommunityOwnerLost>()),
    );
    expect(h.puts, 0);
  });
  test(
    'same account new session cannot reuse old repository even for a read',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.links.read(owner);
      final count = h.calls.length;
      h.client.restoreSession({
        'token': 'replacement-session',
        'csrf_token': 'owned-test-csrf',
      });
      await expectLater(
        h.links.read(owner),
        throwsA(isA<AdminCommunityOwnerLost>()),
      );
      expect(h.calls.length, count);
    },
  );
  test(
    'disposed pending owner read cannot populate a reusable review',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.profileGate = Completer<void>();
      final pending = h.links.read(owner);
      await Future<void>.delayed(Duration.zero);
      h.links.dispose();
      h.profileGate!.complete();
      await expectLater(pending, throwsA(isA<AdminCommunityOwnerLost>()));
      expect(h.calls.length, 1);
    },
  );
  test('missing CSRF prevents submission callback and actual write', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final base = await h.links.read(owner);
    h.client.restoreSession({'token': 'owned-test-session'});
    var submitted = 0;
    await expectLater(
      h.links.replace(owner, base, draft(base), onSubmitted: () => submitted++),
      throwsA(isA<ApiFailure>()),
    );
    expect(h.puts, 0);
    expect(submitted, 0);
  });
  test(
    'comment query encoding preserves LIKE input and real API filter names',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      const filter = AdminCommentFilter(
        keyword: ' _% /?& 😀 ',
        status: AdminCommentStatus.deleted,
        target: AdminCommentTarget.book,
      );
      await h.comments.read(owner, filter, 1);
      expect(h.calls.last.url.path, '/root/api/admin/share-comments');
      expect(h.calls.last.url.queryParameters, {
        'page': '1',
        'page_size': '20',
        'keyword': filter.keyword,
        'status': 'deleted',
        'target_type': 'book',
      });
      expect(h.calls.last.followRedirects, isFalse);
    },
  );
  for (final affected in [0, 1, 3]) {
    test(
      'comment delete uses actual affected count $affected from unwrapped data',
      () async {
        final h = Harness();
        addTearDown(h.dispose);
        h.deleted = affected;
        final page = await h.comments.read(
          owner,
          const AdminCommentFilter(),
          1,
        );
        var submitted = 0;
        final receipt = await h.comments.delete(owner, [
          page.items.first,
        ], onSubmitted: () => submitted++);
        expect(receipt.deleted, affected);
        expect(h.posts, 1);
        expect(submitted, 1);
        expect(jsonDecode(h.calls.last.body), {
          'comment_ids': [2],
        });
        expect(h.calls.last.url.path, '/root/api/admin/share-comments/delete');
        expect(h.calls.where((r) => r.method == 'GET').length, 4);
      },
    );
  }
  test(
    'comment review must contain only selected current-page identities',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final page = await h.comments.read(owner, const AdminCommentFilter(), 1);
      await expectLater(
        h.comments.delete(owner, [page.items.first, page.items.first]),
        throwsA(isA<AdminCommunityTargetChanged>()),
      );
      final hidden = AdminCommentRecord.parse(comment(99));
      await expectLater(
        h.comments.delete(owner, [hidden]),
        throwsA(isA<AdminCommunityTargetChanged>()),
      );
      expect(h.posts, 0);
    },
  );
  test('comment changed in preflight never sends a destructive POST', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final page = await h.comments.read(owner, const AdminCommentFilter(), 1);
    h.changeComment = true;
    await expectLater(
      h.comments.delete(owner, [page.items.first]),
      throwsA(isA<AdminCommunityTargetChanged>()),
    );
    expect(h.posts, 0);
  });
  test('old-page comment selection is retired by a new page read', () async {
    final h = Harness();
    addTearDown(h.dispose);
    final page = await h.comments.read(owner, const AdminCommentFilter(), 1);
    await h.comments.read(owner, const AdminCommentFilter(), 2);
    await expectLater(
      h.comments.delete(owner, [page.items.first]),
      throwsA(isA<AdminCommunityTargetChanged>()),
    );
    expect(h.posts, 0);
  });
  test(
    'lost comment delete reply remains unknown and read never repeats it',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final page = await h.comments.read(owner, const AdminCommentFilter(), 1);
      h.loseReply = true;
      await expectLater(
        h.comments.delete(owner, [page.items.first]),
        throwsA(isA<AdminCommunityWriteUnknown>()),
      );
      await expectLater(
        h.comments.delete(owner, [page.items.first]),
        throwsA(isA<AdminCommunityTargetChanged>()),
      );
      await h.comments.read(owner, const AdminCommentFilter(), 1);
      expect(h.posts, 1);
    },
  );
  test('invalid direct API actions are refused before transport', () {
    final h = Harness();
    addTearDown(h.dispose);
    expect(
      () => h.client.adminDeleteShareCommentsJson([1, 1]),
      throwsFormatException,
    );
    expect(
      () => h.client.adminDeleteShareCommentsJson([-1]),
      throwsFormatException,
    );
    expect(
      () => h.client.adminShareCommentsJson(1, status: 'approved'),
      throwsFormatException,
    );
    expect(
      () => h.client.adminShareCommentsJson(1, targetType: 'note'),
      throwsFormatException,
    );
    expect(
      () => h.client.adminFriendLinksJson(
        replacement: {'items': [], 'simple_mode': false, 'extra': true},
      ),
      throwsFormatException,
    );
    expect(h.calls, isEmpty);
  });
  test(
    'redirect and malformed UTF8 are rejected without exposing raw response',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.redirect = true;
      await expectLater(
        h.links.read(owner),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.toString().contains('fixture-private'),
            'redacted',
            false,
          ),
        ),
      );
      h.redirect = false;
      h.invalidRead = true;
      await expectLater(h.links.read(owner), throwsFormatException);
      expect(h.puts, 0);
    },
  );
}
