import 'dart:async';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/features/admin/admin_community_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_community_widgets.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class Transport extends http.BaseClient {
  Transport(this.handler);
  final Future<http.Response> Function(http.Request) handler;
  late final http.Client delegate = MockClient(handler);
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      delegate.send(request);
  @override
  void close() {
    closed = true;
    delegate.close();
  }
}

({BookstarkClient client, AdminCommunityScope scope}) owned({int role = 0}) {
  final client = BookstarkClient(
    'https://example.invalid/root',
    transport: MockClient(
      (_) async => throw StateError('No authenticated API expected'),
    ),
  );
  client.restoreSession({
    'token': 'owned-qr-session',
    'csrf_token': 'owned-qr-csrf',
  });
  return (
    client: client,
    scope: AdminCommunityScope(
      client,
      AdminPrincipal(memberId: 1, account: 'fixture', role: role),
    ),
  );
}

void main() {
  test(
    'QR preview retains exact encoded path and mount prefix without cookies',
    () async {
      final h = owned();
      addTearDown(h.scope.dispose);
      addTearDown(h.client.close);
      final requests = <http.Request>[];
      final transport = Transport((request) async {
        requests.add(request);
        return http.Response.bytes([1, 2, 3], 200);
      });
      final reader = AdminFriendQrReader(h.scope, transport: transport);
      expect(
        await reader.read('/upload-files/a%25.png'),
        Uint8List.fromList([1, 2, 3]),
      );
      expect(
        requests.single.url.removeFragment().toString(),
        'https://example.invalid/root/upload-files/a%25.png',
      );
      expect(requests.single.method, 'GET');
      expect(requests.single.followRedirects, isFalse);
      expect(
        requests.single.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(transport.closed, isTrue);
    },
  );
  for (final path in [
    'https://outside.invalid/a.png',
    '/upload-files/../a.png',
    '/upload-files/a%2Fb.png',
    '/api/admin/settings',
    '/upload-files/a.png?secret=fixture',
  ]) {
    test('QR invalid path never reaches network: $path', () async {
      final h = owned();
      addTearDown(h.scope.dispose);
      addTearDown(h.client.close);
      var calls = 0;
      final transport = Transport((_) async {
        calls++;
        return http.Response('unexpected', 200);
      });
      final reader = AdminFriendQrReader(h.scope, transport: transport);
      await expectLater(reader.read(path), throwsFormatException);
      expect(calls, 0);
      expect(transport.closed, isTrue);
    });
  }
  test(
    'QR closing owner retires pending read and closes its own transport',
    () async {
      final h = owned();
      addTearDown(h.scope.dispose);
      addTearDown(h.client.close);
      final gate = Completer<http.Response>();
      final transport = Transport((_) => gate.future);
      final reader = AdminFriendQrReader(h.scope, transport: transport);
      final pending = reader.read('/upload-files/a.png');
      await Future<void>.delayed(Duration.zero);
      h.scope.close();
      expect(transport.closed, isTrue);
      gate.complete(http.Response.bytes([1, 2, 3], 200));
      await expectLater(pending, throwsA(isA<AttachmentCancelled>()));
    },
  );
  test(
    'QR non-admin owner cannot fetch even a public preview through this component',
    () async {
      final h = owned(role: 1);
      addTearDown(h.scope.dispose);
      addTearDown(h.client.close);
      var calls = 0;
      final transport = Transport((_) async {
        calls++;
        return http.Response('', 200);
      });
      final reader = AdminFriendQrReader(h.scope, transport: transport);
      await expectLater(
        reader.read('/upload-files/a.png'),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(calls, 0);
      expect(transport.closed, isTrue);
    },
  );
  test('QR response cannot exceed two MiB', () async {
    final h = owned();
    addTearDown(h.scope.dispose);
    addTearDown(h.client.close);
    final transport = Transport(
      (_) async => http.Response.bytes(Uint8List(2 * 1024 * 1024 + 1), 200),
    );
    final reader = AdminFriendQrReader(h.scope, transport: transport);
    await expectLater(
      reader.read('/upload-files/a.png'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'bounded', 413)),
    );
    expect(transport.closed, isTrue);
  });
  test(
    'QR redirect does not become an authenticated or external followup',
    () async {
      final h = owned();
      addTearDown(h.scope.dispose);
      addTearDown(h.client.close);
      var calls = 0;
      final transport = Transport((request) async {
        calls++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://outside.invalid/a.png'},
        );
      });
      final reader = AdminFriendQrReader(h.scope, transport: transport);
      await expectLater(
        reader.read('/upload-files/a.png'),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 1);
      expect(transport.closed, isTrue);
    },
  );
}
