import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class AssetTransport extends http.BaseClient {
  final calls = <http.BaseRequest>[];
  final bodies = <String>[];
  final events = <String>[];
  int status = 200;
  Object payload = {'code': 0, 'data': <Object?>[]};
  List<int>? raw;
  bool responseCancelled = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    events.add('transport');
    calls.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final bytes = raw ?? utf8.encode(jsonEncode(payload));
    final stream = StreamController<List<int>>();
    stream.onListen = () {
      stream.add(bytes);
      stream.close();
    };
    stream.onCancel = () {
      responseCancelled = true;
    };
    return http.StreamedResponse(
      stream.stream,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class Harness {
  Harness() {
    client = BookstarkClient(
      'https://example.invalid/mount',
      transport: transport,
    );
    client.restoreSession({
      'token': 'owned-api-session',
      'csrf_token': 'owned-api-csrf',
    });
  }
  final transport = AssetTransport();
  late final BookstarkClient client;
}

Map<String, Object?> host() => {
  'name': 'owned host',
  'host': 'host.example.invalid',
  'port': 22,
  'shell': '/bin/sh',
  'cwd': '/workspace',
  'docker_socket_path': '/var/run/docker.sock',
  'credential_id': 9,
  'username': 'fixture-user',
  'auth_type': 'password',
};
Map<String, Object?> credential([String value = 'owned synthetic password']) =>
    {
      'name': 'owned credential',
      'username': 'fixture-user',
      'auth_type': 'password',
      'credential': value,
    };
Map<String, Object?> settings([String value = 'owned synthetic key']) => {
  'terminal_idle_timeout_seconds': 1800,
  'terminal_scrollback_lines': 5000,
  'credential_secret': value,
};
Future<void> rejects(Future<Object?> Function() action) =>
    expectLater(Future<Object?>.sync(action), throwsFormatException);

void main() {
  late Harness h;
  setUp(() {
    h = Harness();
  });
  tearDown(() {
    h.client.close();
  });
  test(
    'Go considers BOM a real credential rather than blank whitespace',
    () async {
      await h.client.adminSaveAssetCredentialJson(credential('\ufeff'));
      expect(
        (jsonDecode(h.transport.bodies.single) as Map)['credential'],
        '\ufeff',
      );
      await rejects(
        () => h.client.adminSaveAssetCredentialJson(
          credential('\u0085\u00a0\u3000'),
        ),
      );
      expect(h.transport.calls, hasLength(1));
    },
  );

  test(
    'host search preserves mount and real q/status query without fake pagination',
    () async {
      const query = '中文 %_ &/ ?';
      await h.client.adminAssetHostsJson(query: query, status: 'offline');
      final request = h.transport.calls.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/mount/api/admin/assets/ssh-hosts');
      expect(request.url.queryParameters, {'q': query, 'status': 'offline'});
      expect(request.followRedirects, false);
      expect(request.headers['cache-control'], 'no-store');
      expect(h.transport.bodies.single, isEmpty);
    },
  );
  test(
    'credentials list is one fixed GET without unsupported filters or tests',
    () async {
      await h.client.adminAssetCredentialsJson();
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/credentials',
      );
      expect(h.transport.calls.single.url.hasQuery, false);
      expect(h.transport.calls.single.method, 'GET');
      expect(h.transport.calls.single.followRedirects, false);
    },
  );
  test(
    'host create sends explicit metadata and existing credential before transport',
    () async {
      await h.client.adminSaveAssetHostJson(
        host(),
        onSubmitted: () {
          h.transport.events.add('submitted');
        },
      );
      expect(h.transport.events, ['submitted', 'transport']);
      expect(h.transport.calls.single.method, 'POST');
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/ssh-hosts',
      );
      expect(jsonDecode(h.transport.bodies.single), host());
      expect(
        h.transport.calls.single.headers['x-csrf-token'],
        'owned-api-csrf',
      );
      expect(h.transport.calls.single.followRedirects, false);
    },
  );
  test(
    'host update preserves legacy inline authentication without sending its secret',
    () async {
      final value = host()..['credential_id'] = 0;
      await h.client.adminSaveAssetHostJson(value, id: 5);
      expect(h.transport.calls.single.method, 'PUT');
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/ssh-hosts/5',
      );
      final body = jsonDecode(h.transport.bodies.single) as Map;
      expect(body['credential_id'], 0);
      expect(body.containsKey('credential'), false);
    },
  );
  test(
    'host API forbids inline/shared-secret replacement and fake status writes',
    () async {
      await rejects(
        () => h.client.adminSaveAssetHostJson({
          ...host(),
          'credential': 'must not be sent',
        }),
      );
      await rejects(
        () => h.client.adminSaveAssetHostJson({
          ...host(),
          'status': 'online',
        }, id: 5),
      );
      await rejects(
        () => h.client.adminSaveAssetHostJson(host()..['credential_id'] = 0),
      );
      expect(h.transport.calls, isEmpty);
    },
  );
  test(
    'host invalid identifiers, port, line breaks and socket fail before HTTP',
    () async {
      for (final id in [0, -1, 9007199254740992]) {
        await rejects(() => h.client.adminSaveAssetHostJson(host(), id: id));
      }
      for (final port in [0, -1, 65536, '22', 22.5, null]) {
        await rejects(
          () => h.client.adminSaveAssetHostJson(host()..['port'] = port),
        );
      }
      for (final key in ['shell', 'cwd', 'docker_socket_path']) {
        await rejects(
          () => h.client.adminSaveAssetHostJson(
            host()..[key] = '/owned\ninjected',
          ),
        );
      }
      await rejects(
        () => h.client.adminSaveAssetHostJson(
          host()..['docker_socket_path'] = 'relative.sock',
        ),
      );
      expect(h.transport.calls, isEmpty);
    },
  );
  test(
    'credential request preserves exact new secret spaces Unicode and line breaks',
    () async {
      const secret = ' \nowned synthetic 密码 🐋\n ';
      await h.client.adminSaveAssetCredentialJson(
        credential(secret),
        onSubmitted: () {
          h.transport.events.add('submitted');
        },
      );
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/credentials',
      );
      expect(h.transport.calls.single.method, 'POST');
      expect(
        (jsonDecode(h.transport.bodies.single) as Map)['credential'],
        secret,
      );
      expect(h.transport.events, ['submitted', 'transport']);
    },
  );
  test(
    'credential update empty secret explicitly means preserve; create empty is refused',
    () async {
      await h.client.adminSaveAssetCredentialJson(credential(''), id: 9);
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/credentials/9',
      );
      expect(h.transport.calls.single.method, 'PUT');
      expect((jsonDecode(h.transport.bodies.single) as Map)['credential'], '');
      await rejects(
        () => h.client.adminSaveAssetCredentialJson(credential(' \n ')),
      );
      expect(h.transport.calls, hasLength(1));
    },
  );
  test('credential invalid fields or oversized secret do not submit', () async {
    var submitted = 0;
    await rejects(
      () => h.client.adminSaveAssetCredentialJson(
        credential()..['auth_type'] = 'agent',
      ),
    );
    await rejects(
      () => h.client.adminSaveAssetCredentialJson({
        ...credential(),
        'unexpected': true,
      }),
    );
    await rejects(
      () => h.client.adminSaveAssetCredentialJson(
        credential(List.filled(1024 * 1024, 'x').join()),
        onSubmitted: () {
          submitted++;
        },
      ),
    );
    expect(submitted, 0);
    expect(h.transport.calls, isEmpty);
  });
  test(
    'delete is fixed resource and exact ID; receipt does not fabricate affected rows',
    () async {
      h.transport.payload = {'code': 0, 'message': 'owned receipt'};
      final response = await h.client.adminDeleteAssetRecordJson(
        'credentials',
        9,
      );
      expect(response.containsKey('deleted'), false);
      expect(h.transport.calls.single.method, 'DELETE');
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/credentials/9',
      );
      for (final resource in [
        '../settings',
        'ssh-hosts/1/test',
        'webdav-servers',
      ]) {
        await rejects(() => h.client.adminDeleteAssetRecordJson(resource, 1));
      }
      expect(h.transport.calls, hasLength(1));
    },
  );
  test(
    'connection test is only one explicit POST with an actual submission callback',
    () async {
      var submitted = 0;
      await h.client.adminTestAssetHostJson(
        5,
        onSubmitted: () {
          submitted++;
        },
      );
      expect(submitted, 1);
      expect(h.transport.calls.single.method, 'POST');
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/ssh-hosts/5/test',
      );
      expect(h.transport.bodies.single, isEmpty);
    },
  );
  test(
    'settings require all three fields and never turn omitted secret into empty',
    () async {
      await rejects(
        () => h.client.adminAssetSettingsJson(
          update: {
            'terminal_idle_timeout_seconds': 1800,
            'terminal_scrollback_lines': 5000,
          },
        ),
      );
      expect(h.transport.calls, isEmpty);
      await h.client.adminAssetSettingsJson(update: settings(''));
      expect(
        (jsonDecode(h.transport.bodies.single) as Map)['credential_secret'],
        '',
      );
      expect(h.transport.calls.single.method, 'PUT');
      expect(
        h.transport.calls.single.url.path,
        '/mount/api/admin/assets/settings',
      );
    },
  );
  test(
    'settings read ignores write callback and invalid ranges do not submit',
    () async {
      var submitted = 0;
      await h.client.adminAssetSettingsJson(
        onSubmitted: () {
          submitted++;
        },
      );
      expect(submitted, 0);
      expect(h.transport.calls.single.method, 'GET');
      await rejects(
        () => h.client.adminAssetSettingsJson(
          update: settings()..['terminal_idle_timeout_seconds'] = 0,
        ),
      );
      await rejects(
        () => h.client.adminAssetSettingsJson(
          update: settings()..['terminal_scrollback_lines'] = 50001,
        ),
      );
      expect(h.transport.calls, hasLength(1));
    },
  );
  test(
    'HTTP errors and redirects never expose private upstream messages',
    () async {
      h.transport.status = 302;
      h.transport.payload = {
        'code': 1,
        'message': 'owned private upstream material',
      };
      Object? failure;
      try {
        await h.client.adminAssetCredentialsJson();
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<ApiFailure>());
      expect(failure.toString(), isNot(contains('owned private')));
      expect(h.transport.calls.single.followRedirects, false);
    },
  );
  test(
    'malformed or oversized successful receipts are bounded without body disclosure',
    () async {
      h.transport.raw = [255];
      await rejects(() => h.client.adminAssetCredentialsJson());
      h.transport.raw = null;
      h.transport.payload = {
        'code': 0,
        'data': {'credential_secret': List.filled(2 * 1024 * 1024, 'x').join()},
      };
      await expectLater(
        h.client.adminAssetSettingsJson(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'controlled read bound',
            contains('exceeds'),
          ),
        ),
      );
      expect(h.transport.responseCancelled, true);
    },
  );
  test(
    'terminal-policy-only endpoint sends exactly two string keys with submission and no redirect',
    () async {
      await h.client.adminAssetTerminalPolicyJson(
        idleSeconds: 2400,
        scrollbackLines: 7000,
        onSubmitted: () {
          h.transport.events.add('submitted');
        },
      );
      expect(h.transport.calls.single.url.path, '/mount/api/admin/settings');
      expect(h.transport.calls.single.method, 'PUT');
      expect(h.transport.calls.single.followRedirects, isFalse);
      expect(jsonDecode(h.transport.bodies.single), {
        'asset_terminal_idle_timeout_seconds': '2400',
        'asset_terminal_scrollback_lines': '7000',
      });
      expect(h.transport.events, ['submitted', 'transport']);
      for (final pair in [
        (0, 5000),
        (86401, 5000),
        (1800, 499),
        (1800, 50001),
      ]) {
        await rejects(
          () => h.client.adminAssetTerminalPolicyJson(
            idleSeconds: pair.$1,
            scrollbackLines: pair.$2,
          ),
        );
      }
      expect(h.transport.calls, hasLength(1));
    },
  );
}
