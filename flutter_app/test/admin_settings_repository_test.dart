import 'dart:async';
import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';

class _Reply {
  const _Reply(
    this.status,
    this.body, {
    this.headers = const {},
    this.stream,
    this.contentLength,
  });
  final int status;
  final Object? body;
  final Map<String, String> headers;
  final Stream<List<int>>? stream;
  final int? contentLength;
}

class _Recorded {
  const _Recorded(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _FakeTransport extends http.BaseClient {
  _FakeTransport(this.handler);
  final Future<_Reply> Function(http.BaseRequest request, String body) handler;
  final requests = <_Recorded>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.decode(await request.finalize().toBytes());
    requests.add(
      _Recorded(
        request.method,
        request.url,
        Map.unmodifiable(request.headers),
        body,
      ),
    );
    final reply = await handler(request, body);
    final bytes = utf8.encode(jsonEncode(reply.body));
    return http.StreamedResponse(
      reply.stream ?? Stream<List<int>>.value(bytes),
      reply.status,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        ...reply.headers,
      },
      request: request,
      contentLength: reply.stream == null ? bytes.length : reply.contentLength,
    );
  }
}

const _admin = AdminPrincipal(memberId: 41, account: 'admin-fixture', role: 0);
const _profile = {
  'code': 0,
  'data': {
    'member_id': 41,
    'account': 'admin-fixture',
    'role': 0,
    'email': 'admin@example.invalid',
    'default_home': 'books',
  },
};

List<Map<String, Object?>> _settings() =>
    [
          {'key': 'ai_enabled', 'value': '1'},
          {'key': 'ai_provider', 'value': 'openai'},
          {'key': 'ai_base_url', 'value': 'https://ai.example.invalid/v1'},
          {'key': 'ai_api_key', 'value': 'fixture-secret-do-not-print'},
          {'key': 'ai_model', 'value': 'fixture-model'},
          {'key': 'ai_temperature', 'value': '0.7'},
          {'key': 'ai_max_tokens', 'value': '2048'},
          {'key': 'ai_total_prompt_tokens', 'value': '12'},
          {'key': 'ai_total_completion_tokens', 'value': '8'},
          {'key': 'ai_total_requests', 'value': '2'},
          {'key': 'smtp_host', 'value': 'mail.example.invalid'},
          {'key': 'smtp_port', 'value': '587'},
          {'key': 'smtp_encryption', 'value': 'starttls'},
          {'key': 'smtp_username', 'value': 'smtp-user'},
          {'key': 'smtp_password', 'value': ''},
          {'key': 'mail_timeout_seconds', 'value': '10'},
          {'key': 'mail_from_name', 'value': 'Fixture'},
          {'key': 'mail_from_address', 'value': 'from@example.invalid'},
          {'key': 'mail_enabled', 'value': '0'},
          {'key': 'task_email_reminder_enabled', 'value': '0'},
          {'key': 'password_reset_enabled', 'value': '1'},
          {'key': 'mail_public_url', 'value': ''},
          {'key': 'password_reset_expiry_minutes', 'value': '30'},
          {'key': 'future_private_setting', 'value': 'future-secret-value'},
        ]
        .map(
          (row) => <String, Object?>{
            'description': 'fixture',
            'update_time': '2026-11-07T00:00:00Z',
            ...row,
          },
        )
        .toList();

_FakeTransport _transport({
  required Future<_Reply> Function(http.BaseRequest request, String body)?
  override,
  Map<String, Object?>? profile,
}) => _FakeTransport((request, body) async {
  if (override != null) {
    final reply = await override(request, body);
    if (reply.status != -1) return reply;
  }
  final path = request.url.path;
  if (path.endsWith('/api/profile')) {
    return _Reply(200, profile ?? _profile);
  }
  if (path.endsWith('/api/admin/settings') && request.method == 'GET') {
    return _Reply(200, {'code': 0, 'data': _settings()});
  }
  if (path.endsWith('/api/admin/settings') && request.method == 'PUT') {
    return const _Reply(200, {'code': 0, 'message': 'saved'});
  }
  if (path.endsWith('/api/admin/settings/ai/test')) {
    return const _Reply(200, {
      'code': 0,
      'ok': false,
      'message': 'fixture failed',
      'detail': 'fixture-secret-do-not-print',
      'sample': 'untrusted sample',
      'latency_ms': 9,
    });
  }
  if (path.endsWith('/api/admin/mail/status')) {
    return const _Reply(200, {
      'code': 0,
      'data': {
        'configured': true,
        'enabled': true,
        'task_reminder_enabled': false,
        'password_reset_enabled': true,
        'password_reset_ready': true,
        'summary': {
          'pending': 2,
          'failed': 1,
          'sent': 4,
          'last_sent': '2026-11-06T20:15:00Z',
          'last_error': 'fixture transport detail',
        },
      },
    });
  }
  if (path.endsWith('/api/admin/settings/mail/test')) {
    return const _Reply(200, {'code': 0, 'message': 'sent'});
  }
  if (path.endsWith('/api/csrf-token')) {
    return const _Reply(
      200,
      {'code': 0},
      headers: {'set-cookie': 'csrf_token=fixture-csrf; Path=/'},
    );
  }
  throw StateError('Unexpected fake request path: $path');
});

BookstarkClient _client(_FakeTransport transport, {String prefix = '/mount'}) =>
    BookstarkClient(
      'https://server.example.invalid$prefix',
      transport: transport,
    )..restoreSession({'token': 'fixture-token'});

List<Map<String, Object?>> _textSettings() => [
  ..._settings(),
  for (final field in AdminAiTextField.values)
    {
      'key': field.key,
      'value': '# original\r\nlabel | {subject}\r\n',
      'description': 'fixture',
      'update_time': '2026-11-07T00:00:00Z',
    },
];

_FakeTransport _textTransport({
  Future<_Reply> Function(http.BaseRequest, String)? override,
}) => _transport(
  override: (request, body) async {
    if (override != null) {
      final reply = await override(request, body);
      if (reply.status != -1) return reply;
    }
    if (request.url.path.endsWith('/api/admin/settings') &&
        request.method == 'GET') {
      return _Reply(200, {'code': 0, 'data': _textSettings()});
    }
    if (request.url.path.endsWith('/api/admin/settings/ai/reset')) {
      final key = (jsonDecode(body) as Map)['key'];
      return _Reply(200, {
        'code': 0,
        'message': 'reset',
        'data': {'key': key, 'value': 'server-default\r\n# kept'},
      });
    }
    return const _Reply(-1, null);
  },
);

void main() {
  group('AdminSettingsSnapshot and typed dirty patches', () {
    test(
      'retains unknown values as read-only and keeps usage typed/read-only',
      () {
        final snapshot = AdminSettingsSnapshot.parse(_settings());
        expect(
          snapshot.unknownSettings['future_private_setting']?.value,
          'future-secret-value',
        );
        expect(snapshot.ai.usage.promptTokens, 12);
        expect(snapshot.ai.usage.completionTokens, 8);
        expect(snapshot.ai.usage.requests, 2);
        expect(snapshot.ai.enabled, isTrue);
        expect(snapshot.smtp.port, 587);
        expect(snapshot.mail.passwordResetExpiryMinutes, 30);
        expect(
          snapshot.toString(),
          isNot(contains('fixture-secret-do-not-print')),
        );
        expect(snapshot.toString(), isNot(contains('future-secret-value')));
      },
    );

    test(
      'rejects duplicate or malformed rows and non-redacted SMTP secret',
      () {
        final duplicate = _settings()..add(_settings().first);
        expect(
          () => AdminSettingsSnapshot.parse(duplicate),
          throwsFormatException,
        );
        final badUsage = _settings()
          ..removeWhere((row) => row['key'] == 'ai_total_requests')
          ..add({
            'key': 'ai_total_requests',
            'value': '-1',
            'description': 'fixture',
            'update_time': '',
          });
        expect(
          () => AdminSettingsSnapshot.parse(badUsage),
          throwsFormatException,
        );
        final leaked = _settings()
          ..removeWhere((row) => row['key'] == 'smtp_password')
          ..add({
            'key': 'smtp_password',
            'value': 'must-not-surface',
            'description': 'fixture',
            'update_time': '',
          });
        expect(
          () => AdminSettingsSnapshot.parse(leaked),
          throwsFormatException,
        );
      },
    );

    test('SMTP empty password is omitted; AI explicit empty key clears', () {
      final snapshot = AdminSettingsSnapshot.parse(_settings());
      final smtp = const AdminSmtpChanges(
        host: AdminChange.set('new.example.invalid'),
        password: AdminChange.set(''),
      ).patch(snapshot);
      expect(smtp, {'smtp_host': 'new.example.invalid'});
      final ai = const AdminAiChanges(
        apiKey: AdminChange.set(''),
      ).patch(snapshot);
      expect(ai, {'ai_api_key': ''});
      final typed = const AdminAiChanges(
        enabled: AdminChange.set(false),
        maxTokens: AdminChange.set(4096),
      ).patch(snapshot);
      expect(typed, {'ai_enabled': '0', 'ai_max_tokens': '4096'});
      expect(smtp, isNot(contains('future_private_setting')));
      expect(ai, isNot(contains('ai_total_requests')));
    });
  });

  group('AdminSettingsRepository fake HTTP protocol', () {
    test(
      'reads through BookstarkClient prefix/session and writes only dirty fields',
      () async {
        final transport = _transport(
          override: (_, _) async => const _Reply(-1, null),
        );
        final client = _client(transport);
        final repo = AdminSettingsRepository(client);
        final snapshot = await repo.read(_admin);
        expect(snapshot.ai.model, 'fixture-model');
        expect(snapshot.smtp.host, 'mail.example.invalid');
        expect(transport.requests.first.uri.path, '/mount/api/profile');
        expect(
          transport.requests.first.headers['cookie'],
          'token=fixture-token',
        );

        await repo.saveAi(
          _admin,
          snapshot,
          const AdminAiChanges(
            apiKey: AdminChange.set(''),
            model: AdminChange.set('fixture-model'),
          ),
        );
        final put = transport.requests.singleWhere(
          (request) => request.method == 'PUT',
        );
        expect(put.uri.path, '/mount/api/admin/settings');
        expect(put.headers['x-csrf-token'], 'fixture-csrf');
        expect(jsonDecode(put.body), {'ai_api_key': ''});
        expect(put.body, isNot(contains('future_private_setting')));
        expect(put.body, isNot(contains('ai_total_requests')));
      },
    );

    test(
      'AI test respects HTTP 200 code 0 but requires ok=true and never PUTs',
      () async {
        final transport = _transport(
          override: (_, _) async => const _Reply(-1, null),
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final result = await repo.testAi(
          _admin,
          provider: 'openai',
          baseUrl: 'https://ai.example.invalid/v1',
          apiKey: 'fixture-secret-do-not-print',
          model: 'fixture-model',
        );
        expect(result.connected, isFalse);
        expect(result.latencyMs, 9);
        expect(
          result.toString(),
          isNot(contains('fixture-secret-do-not-print')),
        );
        final testRequest = transport.requests.singleWhere(
          (request) => request.uri.path.endsWith('/settings/ai/test'),
        );
        expect(testRequest.method, 'POST');
        expect(jsonDecode(testRequest.body), {
          'provider': 'openai',
          'base_url': 'https://ai.example.invalid/v1',
          'api_key': 'fixture-secret-do-not-print',
          'model': 'fixture-model',
        });
        expect(
          transport.requests.where((request) => request.method == 'PUT'),
          isEmpty,
        );
      },
    );

    test(
      'mail status validates counters and exposes only error presence',
      () async {
        final transport = _transport(
          override: (_, _) async => const _Reply(-1, null),
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final status = await repo.readMailStatus(_admin);
        expect(status.pending, 2);
        expect(status.failed, 1);
        expect(status.sent, 4);
        expect(status.lastSent, DateTime.utc(2026, 11, 6, 20, 15));
        expect(status.hasLastError, isTrue);
        expect(status.toString(), isNot(contains('fixture transport detail')));
        final emptyStatus = AdminMailStatus.parse(const {
          'configured': false,
          'enabled': false,
          'task_reminder_enabled': false,
          'password_reset_enabled': false,
          'password_reset_ready': false,
          'summary': {'pending': 0, 'failed': 0, 'sent': 0, 'last_error': ''},
        });
        expect(emptyStatus.lastSent, isNull);

        expect(
          () => AdminMailStatus.parse(const {
            'configured': true,
            'enabled': true,
            'task_reminder_enabled': false,
            'password_reset_enabled': true,
            'password_reset_ready': true,
            'summary': {
              'pending': -1,
              'failed': 0,
              'sent': 0,
              'last_error': '',
            },
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'mail send is explicit, uses only recipient and exposes saved-config caveat',
      () async {
        final transport = _transport(
          override: (_, _) async => const _Reply(-1, null),
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final outcome = await repo.sendMailTest(
          _admin,
          'recipient@example.invalid',
          hasUnsavedSettings: true,
        );
        expect(outcome.state, AdminMailTestState.sent);
        expect(outcome.savedConfigOnly, isTrue);
        expect(outcome.hadUnsavedChanges, isTrue);
        final request = transport.requests.singleWhere(
          (request) => request.uri.path.endsWith('/settings/mail/test'),
        );
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'email': 'recipient@example.invalid',
        });
        expect(
          transport.requests.where((request) => request.method == 'PUT'),
          isEmpty,
        );
      },
    );

    test(
      'empty mail recipient is rejected locally without a send request',
      () async {
        final transport = _transport(
          override: (_, _) async => const _Reply(-1, null),
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        await expectLater(
          repo.sendMailTest(_admin, '  '),
          throwsFormatException,
        );
        expect(
          transport.requests.where(
            (request) => request.uri.path.endsWith('/settings/mail/test'),
          ),
          isEmpty,
        );
      },
    );

    test('mail 429 is reported without retry', () async {
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/settings/mail/test')) {
            return const _Reply(429, {'code': 1, 'message': 'limited'});
          }
          return const _Reply(-1, null);
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      await repo.read(_admin);
      final result = await repo.sendMailTest(
        _admin,
        'recipient@example.invalid',
      );
      expect(result.state, AdminMailTestState.rateLimited);
      expect(
        transport.requests.where(
          (request) => request.uri.path.endsWith('/settings/mail/test'),
        ),
        hasLength(1),
      );
    });

    test('AI test success requires the explicit ok boolean', () async {
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/settings/ai/test')) {
            return const _Reply(200, {
              'code': 0,
              'ok': true,
              'latency_ms': 'invalid',
            });
          }
          return const _Reply(-1, null);
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      await repo.read(_admin);
      final outcome = await repo.testAi(
        _admin,
        provider: 'anthropic',
        baseUrl: '',
        apiKey: '',
        model: '',
      );
      expect(outcome.connected, isTrue);
      expect(outcome.latencyMs, isNull);
    });

    test('AI test rejects a code-zero response that omits ok', () async {
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/settings/ai/test')) {
            return const _Reply(200, {'code': 0, 'message': 'looks good'});
          }
          return const _Reply(-1, null);
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      await repo.read(_admin);
      await expectLater(
        repo.testAi(
          _admin,
          provider: 'openai',
          baseUrl: '',
          apiKey: '',
          model: '',
        ),
        throwsFormatException,
      );
      expect(
        transport.requests.where((request) => request.method == 'PUT'),
        isEmpty,
      );
    });

    test(
      'mail transport failure is unknown and is never automatically retried',
      () async {
        final transport = _transport(
          override: (request, _) async {
            if (request.url.path.endsWith('/settings/mail/test')) {
              throw http.ClientException('fixture network failure');
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final result = await repo.sendMailTest(
          _admin,
          'recipient@example.invalid',
        );
        expect(result.state, AdminMailTestState.unknown);
        expect(
          transport.requests.where(
            (request) => request.uri.path.endsWith('/settings/mail/test'),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'bounded settings response is cancelled as soon as it exceeds 2 MiB',
      () async {
        final cancelled = Completer<void>();
        final stream = Stream<List<int>>.multi((controller) {
          controller.add(List<int>.filled(1024 * 1024, 0x20));
          controller.add(List<int>.filled(1024 * 1024, 0x20));
          controller.add([0x20]);
          controller.onCancel = cancelled.complete;
        });
        final transport = _transport(
          override: (request, _) async {
            if (request.url.path.endsWith('/api/admin/settings') &&
                request.method == 'GET') {
              return _Reply(200, null, stream: stream, contentLength: null);
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await expectLater(repo.read(_admin), throwsFormatException);
        await cancelled.future.timeout(const Duration(seconds: 2));
        expect(
          transport.requests.where(
            (r) => r.uri.path.endsWith('/api/admin/settings'),
          ),
          hasLength(1),
        );
      },
    );

    test('known Content-Length overflow cancels the response stream', () async {
      final cancelled = Completer<void>();
      final stream = Stream<List<int>>.multi((controller) {
        controller.onCancel = cancelled.complete;
        controller.add(List<int>.filled(32, 0x20));
      });
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/api/admin/settings') &&
              request.method == 'GET') {
            return _Reply(
              200,
              null,
              stream: stream,
              contentLength: 2 * 1024 * 1024 + 1,
            );
          }
          return const _Reply(-1, null);
        },
      );

      await expectLater(
        _client(transport).adminSettingsJson(),
        throwsFormatException,
      );
      await cancelled.future.timeout(const Duration(seconds: 2));
      expect(transport.requests, hasLength(1));
    });

    test('settings writes accept up to their 2 MiB request limit', () async {
      final transport = _transport(
        override: (_, _) async => const _Reply(-1, null),
      );
      final client = _client(transport);
      await client.adminSettingsJson(
        update: {'mail_public_url': 'x' * (100 * 1024)},
      );
      final put = transport.requests.singleWhere((r) => r.method == 'PUT');
      expect(utf8.encode(put.body).length, greaterThan(64 * 1024));
      expect(utf8.encode(put.body).length, lessThan(2 * 1024 * 1024));
      expect(put.headers['x-csrf-token'], 'fixture-csrf');

      final before = transport.requests.length;
      await expectLater(
        client.adminSettingsJson(
          update: {'mail_public_url': 'x' * (2 * 1024 * 1024)},
        ),
        throwsFormatException,
      );
      expect(transport.requests, hasLength(before));
    });

    test(
      'bounded JSON rejects malformed UTF-8 and sanitizes server details',
      () async {
        final malformed = _transport(
          override: (request, _) async {
            if (request.url.path.endsWith('/api/admin/mail/status')) {
              return _Reply(
                200,
                null,
                stream: Stream<List<int>>.value([0x7b, 0xff, 0x7d]),
                contentLength: 3,
              );
            }
            return const _Reply(-1, null);
          },
        );
        final client = _client(malformed);
        await expectLater(client.adminMailStatusJson(), throwsFormatException);

        final secretInError = _transport(
          override: (request, _) async {
            if (request.url.path.endsWith('/api/admin/mail/status')) {
              return const _Reply(500, {
                'code': 1,
                'message': 'upstream credential=fixture-private',
              });
            }
            return const _Reply(-1, null);
          },
        );
        try {
          await _client(secretInError).adminMailStatusJson();
          fail('Expected sanitized API failure');
        } on ApiFailure catch (error) {
          expect(error.status, 500);
          expect(error.message, isNot(contains('fixture-private')));
          expect(
            error.message,
            'Administrator service temporarily unavailable',
          );
        }
      },
    );

    test('late settings read after session replacement is rejected', () async {
      final settingsReply = Completer<_Reply>();
      final settingsSeen = Completer<void>();
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/api/admin/settings') &&
              request.method == 'GET') {
            if (!settingsSeen.isCompleted) settingsSeen.complete();
            return settingsReply.future;
          }
          return const _Reply(-1, null);
        },
      );
      final client = _client(transport);
      final repo = AdminSettingsRepository(client);
      final pending = repo.read(_admin);
      await settingsSeen.future;
      client.restoreSession({'token': 'replacement-token'});
      settingsReply.complete(_Reply(200, {'code': 0, 'data': _settings()}));
      await expectLater(pending, throwsStateError);
    });

    test(
      'new operation supersedes a delayed write preflight without stale PUT',
      () async {
        var profiles = 0;
        final delayedProfile = Completer<_Reply>();
        final firstPreflightSeen = Completer<void>();
        final transport = _transport(
          override: (request, _) async {
            if (request.url.path.endsWith('/api/profile')) {
              profiles++;
              if (profiles == 2) {
                firstPreflightSeen.complete();
                return delayedProfile.future;
              }
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        final snapshot = await repo.read(_admin);
        final stale = repo.saveMail(
          _admin,
          snapshot,
          const AdminMailChanges(enabled: AdminChange.set(true)),
        );
        final staleCheck = expectLater(stale, throwsStateError);
        await firstPreflightSeen.future;
        await repo.read(_admin);
        delayedProfile.complete(const _Reply(200, _profile));
        await staleCheck;
        expect(transport.requests.where((r) => r.method == 'PUT'), isEmpty);
        await repo.saveMail(
          _admin,
          snapshot,
          const AdminMailChanges(enabled: AdminChange.set(true)),
        );
        expect(
          transport.requests.where((r) => r.method == 'PUT'),
          hasLength(1),
        );
      },
    );

    test('non-admin profile blocks settings and writes', () async {
      final transport = _transport(
        override: (_, _) async => const _Reply(-1, null),
        profile: const {
          'code': 0,
          'data': {
            'member_id': 41,
            'account': 'admin-fixture',
            'role': 1,
            'email': '',
            'default_home': 'books',
          },
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      await expectLater(repo.read(_admin), throwsStateError);
      expect(
        transport.requests.where(
          (request) => request.uri.path.endsWith('/api/admin/settings'),
        ),
        isEmpty,
      );
    });

    test('401/403 save clears verified write authority', () async {
      var denyPut = true;
      final transport = _transport(
        override: (request, _) async {
          if (request.method == 'PUT' && denyPut) {
            denyPut = false;
            return const _Reply(403, {'code': 1, 'message': 'expired'});
          }
          return const _Reply(-1, null);
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      final snapshot = await repo.read(_admin);
      await expectLater(
        repo.saveMail(
          _admin,
          snapshot,
          const AdminMailChanges(enabled: AdminChange.set(true)),
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        repo.saveMail(
          _admin,
          snapshot,
          const AdminMailChanges(enabled: AdminChange.set(true)),
        ),
        throwsStateError,
      );
      expect(
        transport.requests.where((request) => request.method == 'PUT'),
        hasLength(1),
      );
    });

    test('dispose rejects a response arriving after ownership ended', () async {
      final delayed = Completer<_Reply>();
      final seen = Completer<void>();
      final transport = _transport(
        override: (request, _) async {
          if (request.url.path.endsWith('/api/admin/settings') &&
              request.method == 'GET') {
            if (!seen.isCompleted) seen.complete();
            return delayed.future;
          }
          return const _Reply(-1, null);
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      final pending = repo.read(_admin);
      await seen.future;
      repo.dispose();
      delayed.complete(_Reply(200, {'code': 0, 'data': _settings()}));
      await expectLater(pending, throwsStateError);
    });
  });
  group('typed AI prompt/action protocol', () {
    test(
      'dirty text is frozen and preserves BOM CRLF comments placeholders and separators',
      () async {
        final transport = _textTransport();
        final repo = AdminSettingsRepository(_client(transport));
        final base = await repo.read(_admin);
        const raw =
            '\ufeff# fixture\r\nLabel | preserve {subject} | extra\r\n\r\n';
        final map = <AdminAiTextField, AdminChange<String>>{
          AdminAiTextField.markdown: const AdminChange.set(raw),
          AdminAiTextField.note: const AdminChange.unchanged(),
        };
        final changes = AdminTextChanges(map);
        map.clear();
        await repo.saveText(_admin, base, changes);
        final puts = transport.requests
            .where((r) => r.method == 'PUT')
            .toList();
        expect(puts, hasLength(1));
        expect(jsonDecode(puts.single.body), {'ai_system_prompt_md': raw});
        expect(
          base.unknownSettings.containsKey('ai_system_prompt_md'),
          isFalse,
        );
        expect(
          base.unknownSettings.containsKey('future_private_setting'),
          isTrue,
        );
        expect(changes.toString(), isNot(contains(raw)));
      },
    );

    test(
      'exactly ten typed fields reset immediately using only key and no PUT',
      () async {
        final transport = _textTransport();
        final client = _client(transport);
        final repo = AdminSettingsRepository(client);
        await repo.read(_admin);
        for (final field in AdminAiTextField.values) {
          final result = await repo.resetTextToDefault(_admin, field);
          expect(result.field, field);
          expect(result.value, 'server-default\r\n# kept');
          expect(result.toString(), isNot(contains('server-default')));
        }
        final resets = transport.requests
            .where((r) => r.uri.path.endsWith('/ai/reset'))
            .toList();
        expect(resets, hasLength(10));
        expect(resets.map((r) => jsonDecode(r.body)).toList(), [
          for (final field in AdminAiTextField.values) {'key': field.key},
        ]);
        expect(transport.requests.where((r) => r.method == 'PUT'), isEmpty);
        final count = transport.requests.length;
        expect(
          () => client.adminAiResetJson('smtp_password'),
          throwsFormatException,
        );
        expect(transport.requests.length, count);
      },
    );

    test(
      'reset receipt must identify the requested field and contain text',
      () async {
        final transport = _textTransport(
          override: (request, _) async {
            if (request.url.path.endsWith('/ai/reset')) {
              return const _Reply(200, {
                'code': 0,
                'data': {'key': 'ai_actions_task', 'value': false},
              });
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        await expectLater(
          repo.resetTextToDefault(_admin, AdminAiTextField.markdown),
          throwsFormatException,
        );
        expect(
          transport.requests.where(
            (r) => r.method == 'POST' && r.uri.path.endsWith('/ai/reset'),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'object data cannot hide missing string or non-success receipt codes',
      () async {
        for (final code in [null, '0', false, 1]) {
          final transport = _textTransport(
            override: (request, _) async {
              if (request.url.path.endsWith('/ai/reset')) {
                return _Reply(200, {
                  'code': code,
                  'data': {'key': 'ai_system_prompt_md', 'value': 'value'},
                });
              }
              return const _Reply(-1, null);
            },
          );
          await expectLater(
            _client(transport).adminAiResetJson('ai_system_prompt_md'),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'malformed administrator JSON never includes source text in the exception',
      () async {
        final transport = _textTransport(
          override: (request, _) async {
            if (request.url.path.endsWith('/ai/reset')) {
              return _Reply(
                200,
                null,
                stream: Stream.value(
                  utf8.encode('{"code":0,"value":"fixture-private-marker'),
                ),
              );
            }
            return const _Reply(-1, null);
          },
        );
        try {
          await _client(transport).adminAiResetJson('ai_system_prompt_md');
          fail('malformed receipt accepted');
        } on FormatException catch (error) {
          expect(error.toString(), isNot(contains('fixture-private-marker')));
          expect(error.source, isNull);
        }
      },
    );

    test(
      'malformed HTTP401 cancels its body and clears verified write authority',
      () async {
        var cancelled = false;
        final stream = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
          },
        );
        stream.add([0xff, 0xfe]);
        final transport = _textTransport(
          override: (request, _) async {
            if (request.url.path.endsWith('/ai/reset')) {
              return _Reply(401, null, stream: stream.stream);
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        await expectLater(
          repo.resetTextToDefault(_admin, AdminAiTextField.markdown),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
        );
        expect(cancelled, isTrue);
        await expectLater(
          repo.resetTextToDefault(_admin, AdminAiTextField.markdown),
          throwsStateError,
        );
        expect(
          transport.requests.where((r) => r.uri.path.endsWith('/ai/reset')),
          hasLength(1),
        );
        await stream.close();
      },
    );

    test(
      'administrator mutation redirects are disabled and rejected',
      () async {
        final transport = _textTransport(
          override: (request, _) async {
            if (request.url.path.endsWith('/ai/reset')) {
              expect(request.followRedirects, isFalse);
              return const _Reply(
                302,
                null,
                headers: {'location': 'https://elsewhere.example.invalid'},
              );
            }
            return const _Reply(-1, null);
          },
        );
        await expectLater(
          _client(transport).adminAiResetJson('ai_system_prompt_md'),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 302)),
        );
        expect(
          transport.requests.every(
            (r) => r.uri.host == 'server.example.invalid',
          ),
          isTrue,
        );
      },
    );

    test(
      'lost reset response issues exactly one POST and no automatic replay',
      () async {
        final transport = _textTransport(
          override: (request, _) async {
            if (request.url.path.endsWith('/ai/reset')) {
              throw http.ClientException('fixture link lost');
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        await expectLater(
          repo.resetTextToDefault(_admin, AdminAiTextField.note),
          throwsA(isA<http.ClientException>()),
        );
        expect(
          transport.requests.where((r) => r.uri.path.endsWith('/ai/reset')),
          hasLength(1),
        );
        expect(transport.requests.where((r) => r.method == 'PUT'), isEmpty);
      },
    );
  });
  group('administrator recommendation endpoint', () {
    const config = {
      'strategy': 'manual',
      'manual_labels': ['技术', '阅读'],
      'page_size': 10,
    };
    test(
      'GET and PUT use mounted fixed endpoint with fresh profile and exact typed body',
      () async {
        final transport = _transport(
          override: (request, body) async {
            if (request.url.path.endsWith('/labels/recommendation-settings')) {
              return const _Reply(200, {'code': 0, 'data': config});
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final value = await repo.readRecommendations(_admin);
        expect(value.manualLabels, ['技术', '阅读']);
        await repo.saveRecommendations(_admin, value);
        final put = transport.requests.singleWhere(
          (request) => request.method == 'PUT',
        );
        expect(put.uri.path, '/mount/api/labels/recommendation-settings');
        expect(jsonDecode(put.body), config);
        expect(put.headers['x-csrf-token'], 'fixture-csrf');
        expect(put.headers['cookie'], contains('fixture-token'));
        expect(
          transport.requests.where((r) => r.uri.path.endsWith('/api/profile')),
          hasLength(3),
        );
      },
    );
    test('non-admin cannot issue recommendation requests', () async {
      final transport = _transport(
        override: null,
        profile: {
          'code': 0,
          'data': {'member_id': 41, 'account': 'admin-fixture', 'role': 1},
        },
      );
      final repo = AdminSettingsRepository(_client(transport));
      await expectLater(repo.read(_admin), throwsStateError);
      await expectLater(repo.readRecommendations(_admin), throwsStateError);
      expect(
        transport.requests.where(
          (r) => r.uri.path.endsWith('/recommendation-settings'),
        ),
        isEmpty,
      );
    });
    test(
      'malformed successful mutation receipt is unknown with exactly one PUT',
      () async {
        var writes = 0;
        final transport = _transport(
          override: (request, body) async {
            if (request.url.path.endsWith('/labels/recommendation-settings')) {
              if (request.method == 'PUT') {
                writes++;
                return const _Reply(200, {
                  'code': 0,
                  'data': {'strategy': 'manual'},
                });
              }
              return const _Reply(200, {'code': 0, 'data': config});
            }
            return const _Reply(-1, null);
          },
        );
        final repo = AdminSettingsRepository(_client(transport));
        await repo.read(_admin);
        final value = await repo.readRecommendations(_admin);
        await expectLater(
          repo.saveRecommendations(_admin, value),
          throwsFormatException,
        );
        expect(writes, 1);
      },
    );
  });
}
