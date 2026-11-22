import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_logs_controller.dart';
import 'admin_docker_test_fixture.dart';

class LogTransport extends http.BaseClient {
  LogTransport(this.handle);
  final Future<http.Response> Function(http.Request) handle;
  final started = Completer<void>();
  final abortedSignal = Completer<void>();
  final stream = StreamController<List<int>>();
  int streams = 0, aborts = 0;
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/logs/stream')) {
      return MockClient(handle).send(request);
    }
    streams++;
    expect(request.method, 'GET');
    expect(request.followRedirects, false);
    expect(request.headers['accept'], 'text/event-stream');
    expect(
      request.url.path,
      contains('/prefix/api/admin/assets/ssh-hosts/43/'),
    );
    if (request is http.AbortableRequest) {
      request.abortTrigger?.then((_) {
        if (!aborted) {
          aborted = true;
          aborts++;
          abortedSignal.complete();
          unawaited(stream.close());
        }
      });
    }
    if (!started.isCompleted) started.complete();
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }

  void event(String type, Map<String, Object?> data, {bool bytewise = false}) {
    final bytes = utf8.encode('event: $type\ndata: ${jsonEncode(data)}\n\n');
    if (bytewise) {
      for (final byte in bytes) {
        stream.add([byte]);
      }
    } else {
      stream.add(bytes);
    }
  }

  @override
  void close() {
    if (!stream.isClosed) unawaited(stream.close());
  }
}

Future<void> turn() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DockerHarness h;
  late LogTransport transport;
  late AdminDockerLogsController c;
  setUp(() {
    transport = LogTransport((request) => h.handle(request));
    h = DockerHarness(transport: transport);
    c = AdminDockerLogsController(h.repo, DockerInspect.parse(h.detail));
  });
  tearDown(() {
    c.dispose();
    h.dispose();
  });
  test(
    'ordinary snapshot uses unwrapped object and preserves Unicode',
    () async {
      await c.snapshot(200);
      expect(c.phase, DockerLogsPhase.snapshot);
      expect(c.text, '中文😀\nline two\n');
      expect(transport.streams, 0);
    },
  );
  test(
    'connecting SSE is not ready until data; UTF8 split into bytes is exact',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      transport.event('status', {'state': 'connecting'});
      await turn();
      expect(c.phase, DockerLogsPhase.connecting);
      expect(c.text, '');
      transport.event('log', {'data': '中文😀\n'}, bytewise: true);
      await turn();
      expect(c.phase, DockerLogsPhase.receiving);
      expect(c.text, '中文😀\n');
      c.stop();
      await done;
      expect(transport.aborts, 1);
      expect(transport.streams, 1);
    },
  );
  test(
    'background clears sensitive output and resumes without any new request',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      transport.event('log', {'data': 'owned-sensitive-log'});
      await turn();
      expect(c.text, isNotEmpty);
      c.background();
      await done;
      expect(c.text, '');
      expect(c.phase, DockerLogsPhase.background);
      final count = h.requests.length;
      c.resume();
      await turn();
      expect(c.phase, DockerLogsPhase.idle);
      expect(h.requests.length, count);
      expect(transport.streams, 1);
      expect(transport.aborts, 1);
    },
  );
  test(
    'log-error never exposes raw server message and cancels following',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      transport.event('log', {'data': 'earlier-owned-content'});
      transport.event('log-error', {
        'message': 'owned-private-upstream-address-and-password',
      });
      await done;
      expect(c.phase, DockerLogsPhase.failed);
      expect(c.text, '');
      await transport.abortedSignal.future.timeout(const Duration(seconds: 2));
      expect(transport.aborts, 1);
    },
  );
  test(
    'display buffer stays bounded and clearly reports dropped older logs',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      final chunk = List.filled(4096, 'x').join();
      for (var i = 0; i < 270; i++) {
        transport.event('log', {'data': chunk});
      }
      await turn();
      expect(c.truncated, true);
      expect(
        utf8.encode(c.text).length,
        lessThanOrEqualTo(AdminDockerLogsController.maxBufferBytes),
      );
      c.stop();
      await done;
    },
  );
  test(
    'server replacement characters are noticed without claiming reconstruction',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      transport.event('log', {'data': 'owned\ufffdend'});
      await turn();
      expect(c.containsReplacement, true);
      expect(c.text, 'owned\ufffdend');
      c.stop();
      await done;
    },
  );
  test(
    'incomplete final SSE event is never displayed as a complete log',
    () async {
      final done = c.follow(200);
      await transport.started.future;
      transport.stream.add(
        utf8.encode('event: log\ndata: {"data":"incomplete"}'),
      );
      await transport.stream.close();
      await done;
      expect(c.text, '');
      expect(c.phase, DockerLogsPhase.stopped);
      expect(transport.streams, 1);
    },
  );
  test(
    'owner revocation while following cancels stream and clears content',
    () async {
      c.dispose();
      // Replace the retired route with an independently owned scope.
      h.dispose();
      transport = LogTransport((request) => h.handle(request));
      h = DockerHarness(transport: transport);
      c = AdminDockerLogsController(
        h.repo,
        DockerInspect.parse(h.detail),
        ownerPollInterval: const Duration(milliseconds: 5),
      );
      final revoked = Completer<void>();
      c.addListener(() {
        if (c.phase == DockerLogsPhase.revoked && !revoked.isCompleted) {
          revoked.complete();
        }
      });
      final done = c.follow(200);
      await transport.started.future;
      transport.event('log', {'data': 'owned-log'});
      await turn();
      h.role = -1;
      await revoked.future.timeout(const Duration(seconds: 2));
      await done;
      expect(h.scope.active, false);
      expect(c.text, '');
      expect(transport.aborts, 1);
    },
  );
}
