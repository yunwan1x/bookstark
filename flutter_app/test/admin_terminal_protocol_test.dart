import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/features/admin/admin_terminal_protocol.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_transport_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fixed terminal URL preserves prefix and excludes query authentication',
    () {
      expect(
        terminalEndpoint(
          Uri.parse('https://example.invalid/root/'),
          17,
        ).toString(),
        'wss://example.invalid/root/api/admin/assets/ssh-hosts/17/terminal',
      );
      expect(
        terminalEndpoint(Uri.parse('http://127.0.0.1:9000'), 1).scheme,
        'ws',
      );
      for (final uri in [
        'https://a/?token=x',
        'https://u:p@a/',
        'https://a/#x',
        'file:///tmp/x',
      ]) {
        expect(
          () => terminalEndpoint(Uri.parse(uri), 1),
          throwsA(isA<TerminalException>()),
        );
      }
      for (final id in [0, -1, 9007199254740992]) {
        expect(
          () => terminalEndpoint(Uri.parse('https://a'), id),
          throwsA(isA<TerminalException>()),
        );
      }
    },
  );
  test(
    'frames preserve exact Unicode and control input without implicit enter',
    () {
      const text = '中文😀\t\r\n\u0003';
      expect(jsonDecode(terminalInputFrame(text)), {
        'type': 'input',
        'data': text,
      });
      expect(terminalPasteAllowed(' 中文😀\t\r\n'), isTrue);
      expect(terminalPasteAllowed('\u001b[31m'), isFalse);
      expect(terminalPasteAllowed('x\u0085y'), isFalse);
      expect(terminalInputAllowed(String.fromCharCode(0xd800)), isFalse);
      expect(terminalInputAllowed('😀' * 16384), isTrue);
      expect(terminalInputAllowed('😀' * 16385), isFalse);
      expect(
        () => terminalResizeFrame(501, 20),
        throwsA(isA<TerminalException>()),
      );
      expect(jsonDecode(terminalResizeFrame(80, 24)), {
        'type': 'resize',
        'cols': 80,
        'rows': 24,
      });
    },
  );
  test('wire event errors never retain remote output or JSON source', () {
    expect(
      TerminalEvent.parse('{"type":"ready","data":"connected"}').kind,
      TerminalEventKind.ready,
    );
    expect(
      TerminalEvent.parse('{"type":"closed"}').kind,
      TerminalEventKind.closed,
    );
    const secret = 'synthetic-remote-private-output';
    final event = TerminalEvent.parse(
      jsonEncode({'type': 'error', 'data': secret}),
    );
    expect(event.output, isEmpty);
    expect(event.toString(), isNot(contains(secret)));
    for (final frame in [
      <int>[1, 2],
      '{"type":"output","data":123}',
      '{"type":"unknown"}',
      secret,
    ]) {
      try {
        TerminalEvent.parse(frame);
        fail('invalid frame accepted');
      } catch (error) {
        expect(error, isA<TerminalException>());
        expect(error.toString(), isNot(contains(secret)));
      }
    }
  });
  test(
    'output backlog is byte bounded, UTF8 intact and explicitly truncated',
    () {
      final queue = TerminalOutputQueue(capacity: 16, frameBytes: 8);
      queue.add('😀😀😀😀😀😀');
      expect(queue.pendingBytes, 16);
      expect(queue.take(), contains('truncated'));
      expect(queue.take(), '😀😀');
      expect(queue.take(), '😀😀');
      expect(queue.take(), isNull);
      queue.add('secret');
      queue.clear();
      expect(queue.pendingBytes, 0);
      expect(queue.hasPending, isFalse);
    },
  );

  for (final code in [302, 307]) {
    test(
      'HTTP $code never forwards an authenticated upgrade to redirect target',
      () async {
        final destination = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var leaked = 0, requests = 0;
        final destSub = destination.listen((request) {
          leaked++;
          request.response.close();
        });
        final srcSub = source.listen((request) {
          requests++;
          expect(
            request.headers.value('cookie'),
            'token=owned-synthetic-token',
          );
          expect(
            request.headers.value('origin'),
            'http://127.0.0.1:${source.port}',
          );
          request.response.statusCode = code;
          request.response.headers.set(
            'location',
            'http://127.0.0.1:${destination.port}/escape',
          );
          request.response.close();
        });
        final transport = IoTerminalTransport();
        try {
          await expectLater(
            transport.connect(
              Uri.parse('ws://127.0.0.1:${source.port}/terminal'),
              'owned-synthetic-token',
            ),
            throwsA(isA<TerminalException>()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(requests, 1);
          expect(leaked, 0);
        } finally {
          transport.abort();
          await source.close(force: true);
          await destination.close(force: true);
          await srcSub.cancel();
          await destSub.cancel();
        }
      },
    );
  }
  test(
    'real RFC6455 handshake, masked Unicode input and abort have no replay',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<String>();
      var connections = 0;
      final sub = server.listen((request) async {
        connections++;
        final socket = await WebSocketTransformer.upgrade(
          request,
          compression: CompressionOptions.compressionOff,
        );
        socket.add(jsonEncode({'type': 'ready', 'data': 'connected'}));
        socket.listen((frame) {
          if (!received.isCompleted) received.complete(frame as String);
        }, onError: (Object _) {});
      });
      final transport = IoTerminalTransport();
      try {
        final stream = await transport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/terminal'),
          'owned-test-token',
        );
        final ready = Completer<void>();
        final listener = stream.listen((frame) {
          if (TerminalEvent.parse(frame).kind == TerminalEventKind.ready &&
              !ready.isCompleted) {
            ready.complete();
          }
        }, onError: (Object _) {});
        await ready.future.timeout(const Duration(seconds: 2));
        transport.send(terminalInputFrame('printf 中文😀\r'));
        expect(
          jsonDecode(
            await received.future.timeout(const Duration(seconds: 2)),
          )['data'],
          'printf 中文😀\r',
        );
        transport.abort();
        expect(
          () => transport.send(terminalInputFrame('must not send')),
          throwsA(isA<TerminalException>()),
        );
        await expectLater(
          transport.connect(
            Uri.parse('ws://127.0.0.1:${server.port}'),
            'owned-test-token',
          ),
          throwsA(isA<TerminalException>()),
        );
        expect(connections, 1);
        await listener.cancel();
      } finally {
        transport.abort();
        await server.close(force: true);
        await sub.cancel();
      }
    },
  );
  test(
    'abort retires a pending upgrade and ignores its late response',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final reached = Completer<void>();
      final sub = server.listen((request) {
        reached.complete();
      });
      final transport = IoTerminalTransport();
      try {
        final pending = transport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}'),
          'owned-test-token',
        );
        final assertion = expectLater(
          pending,
          throwsA(isA<TerminalException>()),
        );
        await reached.future;
        transport.abort();
        await assertion.timeout(const Duration(seconds: 2));
      } finally {
        transport.abort();
        await server.close(force: true);
        await sub.cancel();
      }
    },
  );
}
