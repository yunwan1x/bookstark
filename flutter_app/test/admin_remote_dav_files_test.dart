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
import 'package:bookstark_flutter/features/admin/admin_remote_dav_files_repository.dart';
import 'admin_remote_dav_models_test.dart' show davServer, davEntry;

void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late AdminDavFilesRepository repo;
  late Map<String, dynamic> server, credential;
  late String content;
  late int writes, role;
  late bool drop, truncated, destinationExists, contentReadFails;
  late List<http.Request> requests;
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  Map<String, dynamic> row() => davEntry(size: utf8.encode(content).length);
  AdminDavEntry entry() => AdminDavEntry.parse(row(), '.');
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
    content = '\ufeffone\r\n中文\nlast\r';
    writes = 0;
    role = 0;
    drop = false;
    truncated = false;
    destinationExists = false;
    contentReadFails = false;
    requests = [];
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, false);
        expect(request.url.host, 'owned.invalid');
        expect(request.url.path, isNot(contains('ssh-hosts')));
        if (request.url.path.endsWith('/profile')) {
          if (role < 0) {
            return http.Response('private error', 401);
          }
          return json({'member_id': 1, 'account': 'owned-owner', 'role': role});
        }
        if (request.url.path.endsWith('/credentials')) {
          return json([credential]);
        }
        if (request.url.path.endsWith('/webdav-servers')) {
          return json([server]);
        }
        if (request.method == 'GET' && request.url.path.endsWith('/files')) {
          expect(
            request.url.path,
            '/root/api/admin/assets/webdav-servers/42/files',
          );
          expect(request.url.queryParameters['path'], '.');
          return json({
            'items': [row(), if (destinationExists) davEntry(name: 'new.txt')],
            'limit': 1000,
            'truncated': truncated,
          });
        }
        if (request.method == 'GET' && request.url.path.endsWith('/content')) {
          if (contentReadFails) {
            return http.Response('owned unreadable body', 503);
          }
          return json({'path': 'a.txt', 'content': content});
        }
        writes++;
        if (request.method == 'PUT') {
          content = (jsonDecode(request.body) as Map)['content'] as String;
        }
        if (drop) {
          throw http.ClientException('owned applied response lost');
        }
        return json(null);
      }),
    );
    client.restoreSession({
      'token': 'owned-dav-files-token',
      'csrf_token': 'owned-dav-files-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    repo = AdminDavFilesRepository(
      scope,
      AdminDavBinding(
        AdminDavServer.parse(server),
        AdminAssetCredentialMetadata.parse(credential),
      ),
    );
  });
  tearDown(() {
    repo.dispose();
    scope.dispose();
    client.close();
  });
  test(
    'DAV source preserves BOM and mixed line endings with correct API-relative path',
    () async {
      final result = await repo.read(entry());
      expect(result.content, content);
      expect(result.content.codeUnitAt(0), 0xfeff);
      expect(writes, 0);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/content'))
            .single
            .url
            .queryParameters['path'],
        'a.txt',
      );
    },
  );
  test('save verifies original content before one exact PUT', () async {
    final baseline = entry(), original = content, next = '${content}added\r\n';
    await repo.submit(
      AdminDavFilePlan(
        action: AdminDavFileAction.save,
        path: baseline.path,
        baseline: baseline,
        content: next,
      ),
      baselineContent: original,
    );
    expect(content, next);
    expect(writes, 1);
    final write = requests.singleWhere((r) => r.method == 'PUT');
    expect(
      write.url.path,
      '/root/api/admin/assets/webdav-servers/42/files/content',
    );
    expect(jsonDecode(write.body), {'path': 'a.txt', 'content': next});
  });
  test(
    'changed exact source is not overwritten even if byte size is unchanged',
    () async {
      final baseline = entry(), original = content;
      content = content.replaceFirst('one', 'two');
      await expectLater(
        repo.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.save,
            path: baseline.path,
            baseline: baseline,
            content: 'new',
          ),
          baselineContent: original,
        ),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'password metadata rotation invalidates file binding before request',
    () async {
      credential['modify_time'] = '2026-11-08T00:00:00.000000003Z';
      await expectLater(
        repo.list('.'),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(requests.any((r) => r.url.path.endsWith('/files')), false);
      expect(writes, 0);
    },
  );
  test('truncated directory never proves copy destination absent', () async {
    truncated = true;
    await expectLater(
      repo.submit(
        AdminDavFilePlan(
          action: AdminDavFileAction.copy,
          path: 'a.txt',
          baseline: entry(),
          target: 'new.txt',
        ),
      ),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(writes, 0);
  });
  test('existing destination blocks copy without mutation', () async {
    destinationExists = true;
    await expectLater(
      repo.submit(
        AdminDavFilePlan(
          action: AdminDavFileAction.copy,
          path: 'a.txt',
          baseline: entry(),
          target: 'new.txt',
        ),
      ),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(writes, 0);
  });
  test(
    'applied save with dropped receipt requires current readable body, no replay',
    () async {
      final original = content,
          baseline = entry(),
          next = '${content}owned applied\n';
      final plan = AdminDavFilePlan(
        action: AdminDavFileAction.save,
        path: 'a.txt',
        baseline: baseline,
        content: next,
      );
      drop = true;
      await expectLater(
        repo.submit(plan, baselineContent: original),
        throwsA(isA<AdminDavFileResultUnknown>()),
      );
      expect(content, next);
      expect(writes, 1);
      await expectLater(
        repo.submit(plan, baselineContent: original),
        throwsA(isA<AdminDavFileReviewRequired>()),
      );
      contentReadFails = true;
      final failed = await repo.observeUnknown();
      expect(failed.contentUnavailable, true);
      expect(
        () => repo.finishUnknownReview(),
        throwsA(isA<AdminDavFileReviewRequired>()),
      );
      contentReadFails = false;
      final current = await repo.observeUnknown();
      expect(current.currentText?.content, next);
      expect(repo.unknown, isNotNull);
      repo.finishUnknownReview();
      expect(repo.unknown, isNull);
      expect(writes, 1);
    },
  );
  test(
    'reported-zero metadata does not silently adopt a nonempty body',
    () async {
      final zero = AdminDavEntry.parse(davEntry(size: 0), '.');
      await expectLater(
        repo.read(zero),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'administrator revocation blocks file access and closes shared scope',
    () async {
      role = -1;
      await expectLater(repo.list('.'), throwsA(isA<AdminAssetOwnerLost>()));
      expect(scope.closed, true);
      expect(writes, 0);
    },
  );
}
