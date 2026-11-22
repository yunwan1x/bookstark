import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'profile_repository_test.dart' as profile;

Map<String, Object?> item(int id, {int owner = 7, String type = 'blog'}) => {
  'trash_id': id,
  'member_id': owner,
  'resource_type': type,
  'resource_name': 'note$id',
  'delete_time': '2026-11-05T08:00:00Z',
};
http.Response page(
  List<Object?> rows, {
  int total = 1,
  int page = 1,
  int size = 20,
}) => http.Response(
  jsonEncode({
    'code': 0,
    'data': rows,
    'total': total,
    'page': page,
    'page_size': size,
    'total_pages': total == 0 ? 1 : (total + 19) ~/ 20,
  }),
  200,
  headers: {'content-type': 'application/json'},
);
BookstarkClient client(Future<http.Response> Function(http.Request) handle) =>
    BookstarkClient(
      'https://example.test/base',
      transport: MockClient(
        (r) async => r.url.path == '/base/api/profile'
            ? profile.data(profile.profile())
            : handle(r),
      ),
    )..restoreSession({'token': 'owner', 'csrf_token': 'csrf'});
void main() {
  test(
    'fixed own paginated list and confirmed single restore use exact endpoint and CSRF without all-scope',
    () async {
      var removed = false, writes = 0;
      final c = client((r) async {
        expect(r.followRedirects, false);
        expect(r.headers['cache-control'], 'no-store');
        if (r.method == 'GET') {
          expect(r.url.path, '/base/api/trash');
          expect(r.url.queryParameters['type'], anyOf('', 'blog'));
          expect(r.url.queryParameters['all'], isNull);
          expect(r.url.queryParameters['page'], '1');
          expect(r.url.queryParameters['page_size'], '20');
          return page(removed ? [] : [item(1)], total: removed ? 0 : 1);
        }
        writes++;
        expect(r.method, 'POST');
        expect(r.url.path, '/base/api/trash/1/restore');
        expect(r.headers['x-csrf-token'], 'csrf');
        removed = true;
        return http.Response(
          '{"code":0,"message":"restored"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = RemoteTrashRepository(c, memberId: 7);
      final entry = (await repo.read()).entries.single;
      // The preflight deliberately changes from the visible all-types page to
      // a complete same-type scan, while retaining owner scope.
      // Assertions below inspect all requests independently of pagination order.
      await expectLater(
        repo.apply(
          TrashEntry(
            id: 99,
            memberId: 7,
            type: 'blog',
            name: 'other',
            deletedAt: entry.deletedAt,
          ),
          TrashOperation.delete,
        ),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(writes, 0);
      await repo.apply(entry, TrashOperation.restore);
      expect(writes, 1);
      expect(await repo.isAbsent(entry), true);
      repo.dispose();
      c.close();
    },
  );
  test(
    'same-type complete scan prevents hidden second-page ID from being treated as absent',
    () async {
      var writes = 0, removed = false;
      final c = client((r) async {
        if (r.method != 'GET') {
          writes++;
          removed = true;
          return http.Response(
            '{"code":0,"message":"deleted"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final p = int.parse(r.url.queryParameters['page']!);
        expect(r.url.queryParameters.containsKey('all'), false);
        final rows = List.generate(
          21,
          (i) => item(i + 1),
        ).where((v) => !removed || v['trash_id'] != 21).toList();
        return page(
          rows.skip((p - 1) * 20).take(20).toList(),
          total: rows.length,
          page: p,
        );
      });
      final repo = RemoteTrashRepository(c, memberId: 7);
      final row = (await repo.read(type: 'blog', page: 2)).entries.single;
      expect(await repo.isAbsent(row), false);
      await repo.apply(row, TrashOperation.delete);
      expect(writes, 1);
      expect(await repo.isAbsent(row), true);
      repo.dispose();
      c.close();
    },
  );
  test(
    'owner, type, duplicate and pagination inconsistencies are rejected',
    () async {
      for (final response in [
        page([item(1, owner: 8)]),
        page([item(1, type: 'made-up')]),
        page([item(1), item(1)], total: 2),
        page([item(1)], size: 200),
        page([item(1)], page: 2),
      ]) {
        final c = client((_) async => response);
        final r = RemoteTrashRepository(c, memberId: 7);
        await expectLater(r.read(), throwsFormatException);
        r.dispose();
        c.close();
      }
    },
  );
  test(
    'changing total during verification and disposed repository never claim absence',
    () async {
      var reads = 0;
      final c = client((r) async {
        reads++;
        return page(
          List.generate(20, (i) => item(i + 1)),
          total: reads == 1 ? 21 : 22,
          page: int.parse(r.url.queryParameters['page']!),
        );
      });
      final r = RemoteTrashRepository(c, memberId: 7);
      final row = TrashEntry.fromJson(item(99), 7);
      await expectLater(r.isAbsent(row), throwsStateError);
      r.dispose();
      await expectLater(r.read(), throwsA(isA<TrashPreflightFailure>()));
      c.close();
    },
  );
}
