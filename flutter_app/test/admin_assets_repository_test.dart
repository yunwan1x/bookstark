import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const owner = AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0);
Map<String, Object?> credential(int id) => {
  'id': id,
  'name': 'owned credential',
  'username': 'fixture-user',
  'auth_type': 'password',
  'credential_hint': 'password',
  'created_by': 1,
  'create_time': '2026-11-07T00:00:00.123456789Z',
  'modify_time': '2026-11-07T00:00:00.123456789Z',
  'credential': 'owned synthetic response secret',
};
Map<String, Object?> host(int id) => {
  ...credential(id),
  'name': 'owned host',
  'host': 'host.example.invalid',
  'port': 22,
  'shell': '/bin/sh',
  'cwd': '/workspace',
  'docker_socket_path': '/var/run/docker.sock',
  'credential_id': 9,
  'credential_name': 'owned credential',
  'status': 'unknown',
};

class Transport extends http.BaseClient {
  Transport(this.handle) : _inner = MockClient(handle);
  final Future<http.Response> Function(http.Request) handle;
  final MockClient _inner;
  final raw = <http.BaseRequest>[];
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    raw.add(request);
    return _inner.send(request);
  }

  @override
  void close() {
    closes++;
    _inner.close();
  }
}

class Harness {
  Harness() {
    transport = Transport(handle);
    client = BookstarkClient(
      'https://example.invalid/root',
      transport: transport,
    );
    client.restoreSession({
      'token': 'owned-repo-token',
      'csrf_token': 'owned-repo-csrf',
    });
    repo = AdminAssetsRepository(client);
  }
  late final Transport transport;
  late final BookstarkClient client;
  late final AdminAssetsRepository repo;
  final calls = <http.Request>[];
  Object? role = 0;
  int memberId = 1,
      profileStatus = 200,
      hostStatus = 200,
      credentialsStatus = 200;
  String account = 'owned-owner';
  bool malformedHosts = false;
  Completer<void>? oldHostGate, credentialsGate, profileGate;
  final oldHostReached = Completer<void>();
  final credentialsReached = Completer<void>();
  final profileReached = Completer<void>();
  http.Response reply(Object value, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    if (request.url.path.endsWith('/api/profile')) {
      if (!profileReached.isCompleted) profileReached.complete();
      if (profileGate != null) await profileGate!.future;
      if (profileStatus != 200) {
        return reply({
          'code': 1,
          'message': 'owned-private-upstream',
        }, profileStatus);
      }
      return reply({
        'code': 0,
        'data': {'member_id': memberId, 'account': account, 'role': role},
      }, 200);
    }
    if (request.url.path.endsWith('/ssh-hosts')) {
      final query = request.url.queryParameters['q'];
      final responseStatus = hostStatus;
      final id = query == 'old'
          ? 11
          : query == 'new'
          ? 12
          : 5;
      if (query == 'old' && oldHostGate != null) {
        if (!oldHostReached.isCompleted) oldHostReached.complete();
        await oldHostGate!.future;
      }
      if (responseStatus != 200) {
        return reply({
          'code': 1,
          'message': 'owned-private-upstream',
        }, responseStatus);
      }
      return reply({
        'code': 0,
        'data': malformedHosts
            ? <Object?>[
                {'id': id},
              ]
            : [host(id)],
      }, 200);
    }
    if (request.url.path.endsWith('/credentials')) {
      if (!credentialsReached.isCompleted) credentialsReached.complete();
      if (credentialsGate != null) await credentialsGate!.future;
      if (credentialsStatus != 200) {
        return reply({
          'code': 1,
          'message': 'owned-private-upstream',
        }, credentialsStatus);
      }
      return reply({
        'code': 0,
        'data': [credential(9)],
      }, 200);
    }
    throw StateError('Unexpected owned repository route');
  }

  int get assets => calls.where((r) => r.url.path.contains('/assets/')).length;
  void close() {
    repo.dispose();
    client.close();
  }
}

void main() {
  late Harness h;
  setUp(() {
    h = Harness();
  });
  tearDown(() {
    h.close();
  });

  test(
    'fresh administrator verification precedes each metadata read and never redirects',
    () async {
      final rows = await h.repo.readHosts(owner);
      expect(rows.single.id, 5);
      expect(h.calls.map((r) => r.url.path), [
        '/root/api/profile',
        '/root/api/admin/assets/ssh-hosts',
      ]);
      expect(h.transport.raw.every((r) => !r.followRedirects), true);
      expect(rows.single.secretPresence, AdminAssetSecretPresence.supplied);
      expect(
        rows.single.reviewFingerprint,
        isNot(contains('synthetic response secret')),
      );
      expect(
        h.repo.reviewedHosts!.single.toString(),
        isNot(contains('synthetic response secret')),
      );
      expect(() => rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'host and credential reads can complete independently without cancelling each other',
    () async {
      final hosts = h.repo.readHosts(owner);
      final credentials = h.repo.readCredentials(owner);
      await hosts;
      await credentials;
      expect(h.repo.reviewedHosts!.single.id, 5);
      expect(h.repo.reviewedCredentials!.single.id, 9);
      expect(
        h.calls.where((r) => r.url.path.endsWith('/api/profile')),
        hasLength(2),
      );
      expect(
        h.repo.reviewedCredentials!.single.reviewFingerprint,
        isNot(contains('synthetic response secret')),
      );
    },
  );
  test(
    'applied host query uses Go whitespace while preserving wildcard and BOM bytes',
    () async {
      await h.repo.readHosts(
        owner,
        query: '\u0085 \ufeff%_ \u3000',
        status: AdminAssetStatus.offline,
      );
      // Uri.queryParameters itself drops a leading UTF-8 BOM while decoding.
      // Verify the exact outgoing query bytes, which Go receives unchanged.
      expect(h.calls.last.url.query, 'q=%EF%BB%BF%25_&status=offline');
      expect(h.repo.reviewedHostQuery, '\ufeff%_');
      expect(h.repo.reviewedHostStatus, AdminAssetStatus.offline);
    },
  );
  test(
    'ordinary principal cannot initiate even a profile or asset read',
    () async {
      await expectLater(
        h.repo.readHosts(
          const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 1),
        ),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(h.calls, isEmpty);
    },
  );
  test(
    'fresh demotion clears both catalogs before any further asset request',
    () async {
      await h.repo.readHosts(owner);
      await h.repo.readCredentials(owner);
      final before = h.assets;
      h.role = 1;
      await expectLater(
        h.repo.readHosts(owner),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(h.assets, before);
      expect(h.repo.reviewedHosts, isNull);
      expect(h.repo.reviewedCredentials, isNull);
    },
  );
  test(
    'changed principal cannot reuse catalogs from the same session token',
    () async {
      await h.repo.readCredentials(owner);
      await expectLater(
        h.repo.readHosts(
          const AdminPrincipal(memberId: 2, account: 'other-owner', role: 0),
        ),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(h.repo.reviewedCredentials, isNull);
      expect(h.assets, 1);
    },
  );
  test(
    'session replacement retires getters and old repository does not follow new token',
    () async {
      await h.repo.readCredentials(owner);
      final before = h.calls.length;
      h.client.restoreSession({'token': 'owned-new-session'});
      expect(h.repo.reviewedCredentials, isNull);
      await expectLater(
        h.repo.readCredentials(owner),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(h.calls, hasLength(before));
    },
  );
  test(
    'session replacement during profile verification never starts an asset read',
    () async {
      final gate = Completer<void>();
      h.profileGate = gate;
      final read = h.repo.readHosts(owner);
      await h.profileReached.future;
      final result = expectLater(read, throwsA(isA<AdminAssetOwnerLost>()));
      h.client.restoreSession({'token': 'owned-other-session'});
      gate.complete();
      await result;
      expect(h.assets, 0);
      expect(h.repo.reviewedHosts, isNull);
    },
  );
  test(
    'late secret-bearing response after disposal is discarded without closing shared transport',
    () async {
      final gate = Completer<void>();
      h.credentialsGate = gate;
      final read = h.repo.readCredentials(owner);
      await h.credentialsReached.future;
      final result = expectLater(read, throwsA(isA<AdminAssetOwnerLost>()));
      h.repo.dispose();
      expect(h.transport.closes, 0);
      gate.complete();
      await result;
      expect(h.repo.reviewedCredentials, isNull);
      expect((await h.client.adminAssetPrincipalJson())['member_id'], 1);
    },
  );
  test('new host filter wins over a late older response', () async {
    final gate = Completer<void>();
    h.oldHostGate = gate;
    final old = h.repo.readHosts(owner, query: 'old');
    await h.oldHostReached.future;
    final result = expectLater(old, throwsA(isA<AdminAssetReadSuperseded>()));
    expect((await h.repo.readHosts(owner, query: 'new')).single.id, 12);
    gate.complete();
    await result;
    expect(h.repo.reviewedHosts!.single.id, 12);
    expect(h.repo.reviewedHostQuery, 'new');
  });
  test('late older failure cannot erase the newer host catalog', () async {
    final gate = Completer<void>();
    h.oldHostGate = gate;
    h.hostStatus = 503;
    final old = h.repo.readHosts(owner, query: 'old');
    await h.oldHostReached.future;
    final result = expectLater(old, throwsA(isA<ApiFailure>()));
    h.hostStatus = 200;
    await h.repo.readHosts(owner, query: 'new');
    gate.complete();
    await result;
    expect(h.repo.reviewedHosts!.single.id, 12);
  });
  test(
    'host service failure does not invent empty list or erase credentials catalog',
    () async {
      await h.repo.readHosts(owner);
      await h.repo.readCredentials(owner);
      h.hostStatus = 503;
      await expectLater(
        h.repo.readHosts(owner),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.toString(),
            'no raw upstream',
            isNot(contains('owned-private-upstream')),
          ),
        ),
      );
      expect(h.repo.reviewedHosts, isNull);
      expect(h.repo.reviewedCredentials!.single.id, 9);
    },
  );
  test(
    'asset403 clears catalogs even if profile still reports role0',
    () async {
      await h.repo.readHosts(owner);
      await h.repo.readCredentials(owner);
      h.credentialsStatus = 403;
      await expectLater(
        h.repo.readCredentials(owner),
        throwsA(isA<ApiFailure>()),
      );
      expect(h.repo.reviewedHosts, isNull);
      expect(h.repo.reviewedCredentials, isNull);
    },
  );
  test(
    'malformed asset rows never become success or a fabricated zero count',
    () async {
      await h.repo.readHosts(owner);
      h.malformedHosts = true;
      await expectLater(h.repo.readHosts(owner), throwsFormatException);
      expect(h.repo.reviewedHosts, isNull);
    },
  );
  test(
    'profile errors are sanitized before asset HTTP and no private body is exposed',
    () async {
      h.profileStatus = 500;
      await expectLater(
        h.repo.readHosts(owner),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.toString(),
            'controlled profile error',
            isNot(contains('owned-private-upstream')),
          ),
        ),
      );
      expect(h.assets, 0);
    },
  );
}
