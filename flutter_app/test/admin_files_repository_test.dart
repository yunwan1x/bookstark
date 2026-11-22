import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'package:bookstark_flutter/features/admin/admin_files_repository.dart';
import 'admin_terminal_access_test.dart' as terminal;
import 'admin_files_models_test.dart' as models;

void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late AdminFilesRepository repo;
  late Map<String, dynamic> host, entry;
  late String content;
  late int role, mutations, writeStatus;
  late bool dropped, changedTarget, truncated, destinationExists;
  late List<http.Request> requests;
  setUp(() {
    host = terminal.host();
    entry = models.row(name: 'a', path: '/work/a', size: 13);
    content = '\ufeffa\r\n中文\n';
    role = 0;
    mutations = 0;
    writeStatus = 200;
    dropped = false;
    changedTarget = false;
    truncated = false;
    destinationExists = false;
    requests = [];
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, false);
        expect(request.url.host, 'owned.invalid');
        expect(request.url.path, startsWith('/root/api/'));
        expect(request.headers['cookie'], contains('token=owned-file-token'));
        Object? data;
        if (request.url.path.endsWith('/api/profile')) {
          if (role < 0) return http.Response('private error', 401);
          data = {'member_id': 1, 'account': 'owned-owner', 'role': role};
        } else if (request.url.path.endsWith('/ssh-hosts')) {
          data = [
            {...host, if (changedTarget) 'port': 2200},
          ];
        } else if (request.method == 'GET' &&
            request.url.path.endsWith('/files')) {
          final path = request.url.queryParameters['path'];
          data = {
            'items': path == '/work'
                ? [
                    entry,
                    if (destinationExists)
                      models.row(name: 'new', path: '/work/new'),
                  ]
                : [],
            'limit': 1000,
            'truncated': truncated,
          };
        } else if (request.method == 'GET' &&
            request.url.path.endsWith('/content')) {
          data = {'path': '/work/a', 'content': content};
        } else {
          mutations++;
          expect(request.headers['x-csrf-token'], 'owned-file-csrf');
          if (dropped) throw http.ClientException('owned lost response');
          if (writeStatus != 200) {
            return http.Response('owned private error', writeStatus);
          }
          data = null;
        }
        return http.Response(
          jsonEncode({'code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client.restoreSession({
      'token': 'owned-file-token',
      'csrf_token': 'owned-file-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    repo = AdminFilesRepository(scope, AdminAssetHostMetadata.parse(host));
  });
  tearDown(() {
    repo.dispose();
    scope.dispose();
    client.close();
  });
  AdminFileEntry baseline() => AdminFileEntry.parse(entry, '/work');
  test(
    'Fresh owner and full host checked; read preserves exact source',
    () async {
      final text = await repo.read(baseline());
      expect(text.content, content);
      expect(mutations, 0);
      expect(requests.where((r) => r.url.path.endsWith('/files')).length, 2);
      expect(requests.last.url.queryParameters['path'], '/work');
    },
  );
  test(
    'Owner loss and metadata change never dispatch file operations',
    () async {
      changedTarget = true;
      await expectLater(
        repo.list('/work'),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(requests.where((r) => r.url.path.contains('/files')), isEmpty);
      changedTarget = false;
      role = -1;
      await expectLater(
        repo.list('/work'),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(scope.closed, true);
      expect(mutations, 0);
    },
  );
  test(
    'Save rereads exact original text and metadata before one PUT',
    () async {
      final plan = AdminFileWritePlan(
        action: AdminFileAction.save,
        path: '/work/a',
        baseline: baseline(),
        content: '\ufeffnew\r\n',
      );
      await repo.submit(plan, baselineContent: content);
      expect(mutations, 1);
      final write = requests.last;
      expect(write.method, 'PUT');
      expect(
        write.url.path,
        '/root/api/admin/assets/ssh-hosts/17/files/content',
      );
      expect(jsonDecode(write.body), {
        'path': '/work/a',
        'content': '\ufeffnew\r\n',
      });
    },
  );
  test('Changed bytes with same stat metadata block save', () async {
    final plan = AdminFileWritePlan(
      action: AdminFileAction.save,
      path: '/work/a',
      baseline: baseline(),
      content: 'new',
    );
    await expectLater(
      repo.submit(plan, baselineContent: 'older'),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(mutations, 0);
  });
  test(
    'Unknown write blocks replay; observations never claim old receipt',
    () async {
      final plan = AdminFileWritePlan(
        action: AdminFileAction.save,
        path: '/work/a',
        baseline: baseline(),
        content: 'new',
      );
      dropped = true;
      await expectLater(
        repo.submit(plan, baselineContent: content),
        throwsA(isA<AdminFileResultUnknown>()),
      );
      expect(mutations, 1);
      expect(repo.unknown?.observationRead, false);
      expect(
        () => repo.finishUnknownReview(),
        throwsA(isA<AdminFileReviewRequired>()),
      );
      await expectLater(
        repo.submit(plan, baselineContent: content),
        throwsA(isA<AdminFileReviewRequired>()),
      );
      expect(mutations, 1);
      final observed = await repo.observeUnknown();
      expect(observed.directories.single.path, '/work');
      expect(mutations, 1);
      repo.finishUnknownReview();
      expect(repo.unknown, isNull);
    },
  );
  test(
    'Explicit server refusal remains distinct from uncertain write',
    () async {
      writeStatus = 400;
      final plan = AdminFileWritePlan(
        action: AdminFileAction.chmod,
        path: '/work/a',
        baseline: baseline(),
        mode: '0600',
      );
      await expectLater(repo.submit(plan), throwsA(isA<ApiFailure>()));
      expect(mutations, 1);
      expect(repo.unknown, isNull);
    },
  );
  test(
    'Destination existing or truncated listing blocks rename before mutation',
    () async {
      final plan = AdminFileWritePlan(
        action: AdminFileAction.rename,
        path: '/work/a',
        baseline: baseline(),
        target: '/work/new',
      );
      destinationExists = true;
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      destinationExists = false;
      truncated = true;
      await expectLater(
        repo.submit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(mutations, 0);
    },
  );
  test(
    'Session token switch blocks file access and clears owner scope',
    () async {
      client.restoreSession({'token': 'other-session'});
      await expectLater(
        repo.list('/work'),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(requests, isEmpty);
      expect(scope.closed, true);
    },
  );
}
