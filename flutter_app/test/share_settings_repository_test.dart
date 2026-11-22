import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';

http.Response reply(Map<String, Object?> data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': data})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
final token = List.filled(64, 'a').join();
OwnerShareTarget target({
  PublicShareKind kind = PublicShareKind.blog,
  int id = 7,
}) => OwnerShareTarget(kind: kind, id: id, title: 'Actual owner content');
void main() {
  test(
    'status is a read only boolean map, never a publication or fabricated link',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          calls++;
          expect(r.method, 'GET');
          expect(r.followRedirects, isFalse);
          expect(r.url.path, '/base/api/shares/status');
          expect(r.url.queryParameters, {'type': 'blog', 'ids': '7'});
          expect(r.headers['cache-control'], 'no-store');
          return reply(calls == 1 ? {} : {'7': true});
        }),
      );
      final repo = RemoteShareSettingsRepository(client);
      expect(await repo.status(target()), isFalse);
      expect(await repo.status(target()), isTrue);
      expect(calls, 2);
      client.close();
    },
  );
  test(
    'actual publish receipt encodes identifiers once and separates public and edit links',
    () async {
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/base/api/shares');
          expect(r.url.hasQuery, isFalse);
          expect(r.headers['x-csrf-token'], 'csrf');
          expect(jsonDecode(r.body), {
            'share_type': 'blog',
            'target_id': 7,
            'enable_edit': false,
          });
          return reply({'share_identify': 'literal%2F+', 'edit_token': token});
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final result = await RemoteShareSettingsRepository(
        client,
      ).publish(target());
      expect(
        result.reference.canonicalUri.toString(),
        'https://example.test/base/shares/literal%252F%2B',
      );
      expect(result.reference.canonicalUri.hasQuery, isFalse);
      expect(result.editingUri!.queryParameters['token'], token);
      expect(result.toString(), isNot(contains(token)));
      client.close();
    },
  );
  test(
    'token actions and revoke use only the real typed owner endpoint',
    () async {
      final seen = <String>[];
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          seen.add('${r.method} ${r.url.path}');
          expect(r.url.hasQuery, isFalse);
          final body = jsonDecode(r.body) as Map;
          return reply({
            'edit_token': body['action'] == 'disable' ? '' : token,
          });
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteShareSettingsRepository(client), resource = target();
      var current = OwnerShareReceipt(
        resource,
        PublicShareReference(client.baseUri, 'actual'),
        token,
      );
      for (final action in ShareTokenAction.values) {
        current = await repo.changeToken(resource, current, action);
        expect(current.editingEnabled, action != ShareTokenAction.disable);
      }
      await repo.unpublish(resource);
      expect(seen, [
        'PATCH /api/shares/blog/7/edit-token',
        'PATCH /api/shares/blog/7/edit-token',
        'PATCH /api/shares/blog/7/edit-token',
        'DELETE /api/shares/blog/7',
      ]);
      client.close();
    },
  );
  test(
    'reject foreign receipts, other target membership, whole book edit and malformed capability/status',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          requests++;
          return reply({'7': 'true'});
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteShareSettingsRepository(client), resource = target();
      final foreign = OwnerShareReceipt(
        resource,
        PublicShareReference(Uri.parse('https://other.test'), 'x'),
        token,
      );
      await expectLater(
        repo.changeToken(resource, foreign, ShareTokenAction.reset),
        throwsStateError,
      );
      final wrong = OwnerShareReceipt(
        target(id: 8),
        PublicShareReference(client.baseUri, 'x'),
        token,
      );
      await expectLater(
        repo.changeToken(resource, wrong, ShareTokenAction.reset),
        throwsStateError,
      );
      final book = target(kind: PublicShareKind.book);
      await expectLater(
        repo.changeToken(
          book,
          OwnerShareReceipt(
            book,
            PublicShareReference(client.baseUri, 'x'),
            '',
          ),
          ShareTokenAction.enable,
        ),
        throwsStateError,
      );
      expect(requests, 0);
      await expectLater(repo.status(resource), throwsFormatException);
      expect(requests, 1);
      expect(
        () => OwnerShareReceipt(
          resource,
          PublicShareReference(client.baseUri, 'x'),
          'bad',
        ),
        throwsFormatException,
      );
      client.close();
    },
  );
  test(
    'owner sharing rejects oversized and redirected non JSON receipts without decoding tokens',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => http.Response(
            'x' * (128 * 1024 + 1),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      )..restoreSession({'csrf_token': 'csrf'});
      await expectLater(
        RemoteShareSettingsRepository(client).publish(target()),
        throwsFormatException,
      );
      client.close();
    },
  );
}
