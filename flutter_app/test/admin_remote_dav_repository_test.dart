import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_models.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_repository.dart';
import 'admin_remote_dav_models_test.dart' show davServer;

void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late AdminDavRepository repo;
  late Map<String, dynamic> server, credential;
  late List<http.Request> requests;
  late int mutations, role;
  late bool drop, serverPresent;
  Future<http.Response?> Function(http.Request)? intercept;
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  setUp(() {
    server = davServer();
    credential = {
      'id': 7,
      'name': 'Owned password',
      'username': 'fixture',
      'auth_type': 'password',
      'credential_hint': 'hidden',
      'created_by': 1,
      'create_time': '2026-11-08T00:00:00.000000001Z',
      'modify_time': '2026-11-08T00:00:00.000000002Z',
    };
    requests = [];
    mutations = 0;
    role = 0;
    drop = false;
    serverPresent = true;
    intercept = null;
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, false);
        expect(request.url.host, 'owned.invalid');
        expect(request.url.path, startsWith('/root/api/'));
        final special = await intercept?.call(request);
        if (special != null) return special;
        if (request.url.path.endsWith('/profile')) {
          if (role < 0) return http.Response('private upstream URL', 401);
          return json({'member_id': 1, 'account': 'owned-owner', 'role': role});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/credentials')) {
          return json([credential]);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/webdav-servers')) {
          return json([
            {'id': 'local', 'built_in': true, 'name': 'BookStark'},
            if (serverPresent) server,
          ]);
        }
        mutations++;
        expect(request.headers['x-csrf-token'], 'owned-dav-csrf');
        if (request.method == 'DELETE') serverPresent = false;
        if (drop) throw http.ClientException('owned dropped response');
        if (request.url.path.endsWith('/test')) {
          return json({
            'status': 'offline',
            'message': 'https://user:secret@private.invalid',
            'checked_at': '2026-11-08T01:00:00Z',
          });
        }
        if (request.method == 'DELETE') return json(null);
        server = {
          ...server,
          ...jsonDecode(request.body) as Map<String, dynamic>,
        };
        return json(server);
      }),
    );
    client.restoreSession({
      'token': 'owned-dav-token',
      'csrf_token': 'owned-dav-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    repo = AdminDavRepository(scope);
  });
  tearDown(() {
    repo.dispose();
    scope.dispose();
    client.close();
  });
  AdminDavServer baseline() => AdminDavServer.parse(server);
  AdminDavDraft draft() => AdminDavDraft(
    name: 'Reviewed',
    url: 'https://dav.invalid/prefix',
    root: '/root',
    credentialId: 7,
  );
  test('builtin and remote catalog identities remain distinct', () async {
    final rows = await repo.list();
    expect(rows.whereType<AdminDavBuiltin>().length, 1);
    expect(rows.whereType<AdminDavServer>().single.id, 42);
    expect(mutations, 0);
  });
  test(
    'credential rotation between review and confirmation blocks write',
    () async {
      final plan = await repo.review(
        AdminDavMutation.update,
        server: baseline(),
        draft: draft(),
      );
      credential['modify_time'] = '2026-11-08T00:00:00.000000003Z';
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(mutations, 0);
    },
  );
  test('review binds full server metadata, not just identifier', () async {
    final plan = await repo.review(AdminDavMutation.delete, server: baseline());
    server['root_path'] = '/another-root';
    await expectLater(
      repo.submit(plan),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(mutations, 0);
  });
  test('private key credential is never accepted for DAV', () async {
    credential['auth_type'] = 'key';
    await expectLater(
      repo.review(AdminDavMutation.create, draft: draft()),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(mutations, 0);
    expect(await repo.credentials(), isEmpty);
  });
  test(
    'actual acknowledged save matches reviewed metadata and is single use',
    () async {
      final plan = await repo.review(
        AdminDavMutation.update,
        server: baseline(),
        draft: draft(),
      );
      final result = await repo.submit(plan);
      expect((result as AdminDavServer).name, 'Reviewed');
      expect(mutations, 1);
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(mutations, 1);
    },
  );
  test(
    'lost delete response is unknown, no replay and observed absence is not receipt',
    () async {
      final plan = await repo.review(
        AdminDavMutation.delete,
        server: baseline(),
      );
      drop = true;
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetWriteUnknown>()),
      );
      expect(serverPresent, false);
      expect(mutations, 1);
      expect(repo.unknown, isNotNull);
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(
        () => repo.finishUnknownReview(),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      final rows = await repo.observeUnknown();
      expect(rows.whereType<AdminDavServer>(), isEmpty);
      expect(repo.unknown, isNotNull);
      expect(mutations, 1);
      repo.background();
      expect(
        () => repo.finishUnknownReview(),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      await repo.observeUnknown();
      repo.finishUnknownReview();
      expect(repo.unknown, isNull);
      expect(mutations, 1);
    },
  );
  test(
    'test receipt retains only status/time and discards raw upstream message',
    () async {
      final plan = await repo.review(AdminDavMutation.test, server: baseline());
      final result = await repo.submit(plan) as AdminDavTestReceipt;
      expect(result.status, AdminAssetStatus.offline);
      expect(result.toString(), isNot(contains('secret')));
      expect(mutations, 1);
    },
  );
  test('revoked administrator closes scope before any mutation', () async {
    final plan = await repo.review(AdminDavMutation.delete, server: baseline());
    role = -1;
    await expectLater(repo.submit(plan), throwsA(isA<AdminAssetOwnerLost>()));
    expect(scope.closed, true);
    expect(mutations, 0);
  });
  test('session replacement invalidates prior review locally', () async {
    final plan = await repo.review(AdminDavMutation.delete, server: baseline());
    client.restoreSession({
      'token': 'another-owned-session',
      'csrf_token': 'another-owned-csrf',
    });
    await expectLater(repo.submit(plan), throwsA(isA<AdminAssetOwnerLost>()));
    expect(mutations, 0);
  });
  test(
    'background aborts pending GET and prevents a stale result being adopted',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      intercept = (request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/webdav-servers')) {
          entered.complete();
          await release.future;
          return json([server]);
        }
        return null;
      };
      final task = repo.list();
      final expectation = expectLater(task, throwsA(anything));
      await entered.future;
      repo.background();
      release.complete();
      await expectation;
      expect(mutations, 0);
    },
  );
  test(
    'fresh file binding catches same-id credential metadata changes',
    () async {
      final binding = await repo.bind(baseline());
      credential['username'] = 'changed-owner';
      await expectLater(
        repo.verifyBinding(binding),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(mutations, 0);
    },
  );
}
