import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_access.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> host() => {
  'id': 17,
  'name': 'owned terminal',
  'host': 'ssh.example.invalid',
  'port': 22,
  'username': 'owned-user',
  'auth_type': 'key',
  'credential_id': 28,
  'credential_name': 'owned key',
  'credential_hint': 'key',
  'shell': '/bin/sh',
  'cwd': '/workspace',
  'docker_socket_path': '/var/run/docker.sock',
  'status': 'unknown',
  'created_by': 1,
  'create_time': '2026-11-07T00:00:00.123456789Z',
  'modify_time': '2026-11-07T00:00:00.123456789Z',
};
void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late AdminTerminalAccess access;
  late List<String> reads;
  late Map<String, dynamic> current;
  late int role, profileStatus;
  late String account;
  late bool missing;
  Completer<void>? profileGate;
  late Completer<void> reached;
  setUp(() {
    reads = [];
    current = host();
    role = 0;
    profileStatus = 200;
    account = 'owned-owner';
    missing = false;
    profileGate = null;
    reached = Completer<void>();
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient((request) async {
        reads.add(request.url.path);
        expect(request.method, 'GET');
        expect(request.url.queryParameters.containsKey('token'), isFalse);
        Object data;
        if (request.url.path.endsWith('/api/profile')) {
          if (!reached.isCompleted) reached.complete();
          if (profileGate != null) await profileGate!.future;
          if (profileStatus != 200) {
            return http.Response(
              '{"code":1,"message":"owned remote private error"}',
              profileStatus,
            );
          }
          data = {'member_id': 1, 'account': account, 'role': role};
        } else if (request.url.path.endsWith('/settings')) {
          data = {
            'terminal_idle_timeout_seconds': 1800,
            'terminal_scrollback_lines': 1234,
            'credential_secret': 'owned synthetic key never sent to WebView',
          };
        } else if (request.url.path.endsWith('/ssh-hosts')) {
          data = missing ? [] : [current];
        } else {
          fail('unexpected endpoint');
        }
        return http.Response(
          jsonEncode({'code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client.restoreSession({'token': 'owned-test-token'});
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    access = AdminTerminalAccess(scope, AdminAssetHostMetadata.parse(host()));
  });
  tearDown(() {
    access.dispose();
    scope.dispose();
    client.close();
  });
  test(
    'preflight reads fresh policy, full host metadata and final identity; no SSH test or mutation',
    () async {
      await access.prepare();
      expect(access.scrollbackLines, 1234);
      expect(reads, [
        '/root/api/profile',
        '/root/api/admin/assets/settings',
        '/root/api/profile',
        '/root/api/admin/assets/ssh-hosts',
        '/root/api/profile',
      ]);
    },
  );
  for (final field in [
    'host',
    'port',
    'username',
    'shell',
    'cwd',
    'credential_id',
    'modify_time',
  ]) {
    test(
      'target change in $field cannot connect against a stale review',
      () async {
        current[field] = switch (field) {
          'port' => 2222,
          'credential_id' => 29,
          'modify_time' => '2026-11-07T00:00:00.123456788Z',
          _ => 'changed',
        };
        await expectLater(
          access.prepare(),
          throwsA(
            isA<TerminalException>().having(
              (e) => e.kind,
              'failure',
              TerminalFailure.targetChanged,
            ),
          ),
        );
      },
    );
  }
  test('missing host refuses rather than adopting a same-name row', () async {
    current['id'] = 18;
    await expectLater(
      access.prepare(),
      throwsA(
        isA<TerminalException>().having(
          (e) => e.kind,
          'failure',
          TerminalFailure.targetChanged,
        ),
      ),
    );
  });
  for (final status in [401, 403]) {
    test('fresh HTTP $status is sanitized ownership loss', () async {
      profileStatus = status;
      await expectLater(
        access.verifyOwner(),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.kind,
            'failure',
            TerminalFailure.unauthorized,
          ),
        ),
      );
    });
  }
  test(
    'role/account changes revoke ownership despite an unchanged token',
    () async {
      role = 1;
      await expectLater(
        access.verifyOwner(),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.kind,
            'failure',
            TerminalFailure.unauthorized,
          ),
        ),
      );
      role = 0;
      account = 'different owner';
      await expectLater(
        access.verifyOwner(),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.kind,
            'failure',
            TerminalFailure.unauthorized,
          ),
        ),
      );
    },
  );
  test(
    'token replacement while profile pending prevents later reads',
    () async {
      profileGate = Completer<void>();
      final pending = access.prepare();
      final assertion = expectLater(
        pending,
        throwsA(
          isA<TerminalException>().having(
            (e) => e.kind,
            'failure',
            TerminalFailure.unauthorized,
          ),
        ),
      );
      await reached.future;
      client.restoreSession({'token': 'new-owned-token'});
      profileGate!.complete();
      await assertion;
      expect(reads, ['/root/api/profile']);
    },
  );
}
