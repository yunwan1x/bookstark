import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:bookstark_flutter/core/local_model_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FixtureClient extends http.BaseClient {
  FixtureClient(this.handler, {this.onClose});
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final void Function()? onClose;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    if (closed) return;
    closed = true;
    onClose?.call();
  }
}

String frame(Map<String, Object?> body) => 'data: ${jsonEncode(body)}\r\n\r\n';
String delta(String text) => frame({
  'choices': [
    {
      'index': 0,
      'delta': {'content': text},
      'finish_reason': null,
    },
  ],
});
String finish([String reason = 'stop']) => frame({
  'choices': [
    {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': reason},
  ],
});
const done = 'data: [DONE]\r\n\r\n';
final config = LocalModelConfig(
  endpoint: 'https://model.example.invalid/prefix/v1/',
  model: 'fixture-model',
  apiKey: 'fixture-stream-key',
);
final question = <Map<String, Object?>>[
  {'role': 'user', 'content': '计划'},
];
Matcher issue(LocalModelStreamIssue expected) =>
    isA<LocalModelStreamFailure>().having((e) => e.issue, 'issue', expected);
LocalModelStreamTransport transport(
  String body, {
  int status = 200,
  String mime = 'text/event-stream',
  void Function(http.BaseRequest)? inspect,
}) => LocalModelStreamTransport(
  config,
  createClient: () => FixtureClient((request) async {
    inspect?.call(request);
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.fromIterable(bytes.map((v) => [v])),
      status,
      headers: {'content-type': mime},
    );
  }),
);
List<LocalModelToolDefinition> tools() => [
  LocalModelToolDefinition(
    name: 'search',
    description: 'Read-only search',
    parameters: {'type': 'object'},
  ),
  LocalModelToolDefinition(
    name: 'read',
    description: 'Read an authorized ID',
    parameters: {'type': 'object'},
  ),
];
String toolFrame(List<Map<String, Object?>> calls) => frame({
  'choices': [
    {
      'index': 0,
      'delta': {'tool_calls': calls},
      'finish_reason': null,
    },
  ],
});

void main() {
  test(
    'prefixed independent request preserves fragmented Unicode Markdown and completes once',
    () async {
      const text = '# 阅读计划\n- 学习 🧭\n\n|内容|日期|\n|-|-|\n|笔记|今天|';
      var requests = 0;
      final stream = transport(
        '\uFEFF: heartbeat\r\n\r\n${delta(text)}${finish()}$done',
        inspect: (request) {
          requests++;
          expect(
            request.url.toString(),
            'https://model.example.invalid/prefix/v1/chat/completions',
          );
          expect(request.followRedirects, false);
          expect(request.headers['Authorization'], 'Bearer fixture-stream-key');
          expect(request.headers.containsKey('Cookie'), false);
          expect(request.headers.containsKey('X-CSRF-Token'), false);
          final body = jsonDecode((request as http.Request).body) as Map;
          expect(body['model'], 'fixture-model');
          expect(body['stream'], true);
          expect(body['messages'], question);
          expect(body['max_tokens'], 2048);
        },
      );
      addTearDown(stream.close);
      final updates = await stream.chat(messages: question).toList();
      expect(requests, 1);
      expect(
        updates.where((e) => e.turn == null).map((e) => e.text).join(),
        text,
      );
      expect(updates.where((e) => e.turn != null).single.turn!.text, text);
      expect(updates.last.turn!.toolCalls, isEmpty);
    },
  );
  test(
    'delta arrives while body is still open rather than being buffered to EOF',
    () async {
      final bytes = StreamController<List<int>>(), first = Completer<void>();
      var complete = false;
      final client = FixtureClient(
        (_) async => http.StreamedResponse(
          bytes.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final stream = LocalModelStreamTransport(
        config,
        createClient: () => client,
      );
      final observed = <LocalModelStreamUpdate>[];
      final result = stream.chat(messages: question).forEach((event) {
        observed.add(event);
        if (event.text.isNotEmpty && !first.isCompleted) first.complete();
        if (event.turn != null) complete = true;
      });
      bytes.add(utf8.encode(delta('首段')));
      await first.future.timeout(const Duration(seconds: 2));
      expect(complete, false);
      expect(observed.single.text, '首段');
      bytes.add(utf8.encode(finish() + done));
      await bytes.close();
      await result;
      expect(complete, true);
      expect(client.closed, true);
      stream.close();
    },
  );
  test(
    'missing DONE and length truncation retain received text without a complete turn',
    () async {
      for (final pair in [
        (delta('已接收') + finish(), LocalModelStreamIssue.truncated),
        (
          delta('已接收') + finish('length') + done,
          LocalModelStreamIssue.outputLimit,
        ),
      ]) {
        final stream = transport(pair.$1);
        final observed = <LocalModelStreamUpdate>[];
        await expectLater(
          stream.chat(messages: question).forEach(observed.add),
          throwsA(issue(pair.$2)),
        );
        expect(observed.map((e) => e.text).join(), '已接收');
        expect(observed.any((e) => e.turn != null), false);
        stream.close();
      }
    },
  );
  test(
    'fragmented tool names arguments and interleaved call indices are bound before exposure',
    () async {
      final body =
          toolFrame([
            {
              'index': 0,
              'id': 'call_a',
              'type': 'function',
              'function': {'name': 'sea', 'arguments': '{"query":"'},
            },
            {
              'index': 1,
              'id': 'call_b',
              'type': 'function',
              'function': {'name': 'read', 'arguments': '{"id":'},
            },
          ]) +
          toolFrame([
            {
              'index': 1,
              'function': {'arguments': '7}'},
            },
            {
              'index': 0,
              'function': {'name': 'rch', 'arguments': '笔记"}'},
            },
          ]) +
          finish('tool_calls') +
          done;
      final stream = transport(body);
      addTearDown(stream.close);
      final result = await stream
          .chat(messages: question, tools: tools())
          .toList();
      final calls = result.single.turn!.toolCalls;
      expect(calls.map((c) => c.id), ['call_a', 'call_b']);
      expect(calls.map((c) => c.name), ['search', 'read']);
      expect(jsonDecode(calls.first.arguments), {'query': '笔记'});
      expect(jsonDecode(calls.last.arguments), {'id': 7});
    },
  );
  test(
    'unknown tools duplicate IDs missing indices and incomplete arguments never complete',
    () async {
      final cases = [
        [
          {
            'index': 0,
            'id': 'a',
            'function': {'name': 'delete_all', 'arguments': '{}'},
          },
        ],
        [
          {
            'index': 0,
            'id': 'a',
            'function': {'name': 'search', 'arguments': '{"query":'},
          },
        ],
        [
          {
            'index': 1,
            'id': 'a',
            'function': {'name': 'search', 'arguments': '{}'},
          },
        ],
        [
          {
            'index': 0,
            'id': 'a',
            'function': {'name': 'search', 'arguments': '{}'},
          },
          {
            'index': 1,
            'id': 'a',
            'function': {'name': 'read', 'arguments': '{}'},
          },
        ],
      ];
      for (final calls in cases) {
        final stream = transport(
          toolFrame(calls) + finish('tool_calls') + done,
        );
        await expectLater(
          stream.chat(messages: question, tools: tools()).toList(),
          throwsA(issue(LocalModelStreamIssue.protocol)),
        );
        stream.close();
      }
    },
  );
  test(
    'HTTP errors and redirects expose only safe typed issues and never retry',
    () async {
      for (final pair in [
        (401, LocalModelStreamIssue.authentication),
        (403, LocalModelStreamIssue.authentication),
        (429, LocalModelStreamIssue.busy),
        (302, LocalModelStreamIssue.redirect),
        (503, LocalModelStreamIssue.network),
      ]) {
        var calls = 0;
        final stream = transport(
          'provider echo fixture-stream-key',
          status: pair.$1,
          inspect: (_) => calls++,
        );
        try {
          await stream.chat(messages: question).toList();
          fail('Expected failure');
        } on LocalModelStreamFailure catch (e) {
          expect(e.issue, pair.$2);
          expect(e.toString(), isNot(contains('fixture-stream-key')));
        }
        expect(calls, 1);
        stream.close();
      }
    },
  );
  test(
    'wrong MIME malformed events and nonprimary choices are not valid completed replies',
    () async {
      final cases = [
        transport(delta('x') + finish() + done, mime: 'text/html'),
        transport('data: {broken\n\n'),
        transport(
          frame({
                'choices': [
                  {
                    'index': 1,
                    'delta': {'content': 'bad'},
                    'finish_reason': 'stop',
                  },
                ],
              }) +
              done,
        ),
        transport(
          frame({
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': 42},
                    'finish_reason': 'stop',
                  },
                ],
              }) +
              done,
        ),
        transport(
          frame({
            'error': {'message': 'fixture-stream-key'},
          }),
        ),
      ];
      for (final stream in cases) {
        await expectLater(
          stream.chat(messages: question).toList(),
          throwsA(issue(LocalModelStreamIssue.protocol)),
        );
        stream.close();
      }
    },
  );
  test(
    'text and tool argument budgets abort instead of silently truncating or completing',
    () async {
      final cases = [
        transport(delta('x' * 24001) + finish() + done),
        transport(
          toolFrame([
                {
                  'index': 0,
                  'id': 'a',
                  'function': {'name': 'search', 'arguments': 'x' * 32769},
                },
              ]) +
              finish('tool_calls') +
              done,
        ),
      ];
      for (final stream in cases) {
        await expectLater(
          stream.chat(messages: question, tools: tools()).toList(),
          throwsA(issue(LocalModelStreamIssue.outputLimit)),
        );
        stream.close();
      }
    },
  );
  test('invalid input and retired owners make no model request', () async {
    var calls = 0;
    final stream = transport('', inspect: (_) => calls++);
    await expectLater(
      stream
          .chat(
            messages: [
              {'role': 'user', 'content': 'x', 'unexpected': 'private'},
            ],
          )
          .toList(),
      throwsFormatException,
    );
    await expectLater(
      stream
          .chat(
            messages: [
              {'role': 'tool', 'content': 'x'},
            ],
          )
          .toList(),
      throwsFormatException,
    );
    expect(calls, 0);
    stream.close();
    await expectLater(
      stream.chat(messages: question).toList(),
      throwsA(issue(LocalModelStreamIssue.retired)),
    );
    expect(calls, 0);
  });
  test('overall deadline stops an endlessly heartbeating body', () async {
    final bytes = StreamController<List<int>>();
    var pings = 0;
    late Timer heartbeat;
    final client = FixtureClient(
      (_) async {
        heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
          pings++;
          bytes.add(utf8.encode(': ping\n\n'));
        });
        return http.StreamedResponse(
          bytes.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      },
      onClose: () {
        heartbeat.cancel();
        unawaited(bytes.close());
      },
    );
    final stream = LocalModelStreamTransport(
      config,
      createClient: () => client,
      idleDeadline: const Duration(seconds: 1),
      turnDeadline: const Duration(milliseconds: 150),
    );
    await expectLater(
      stream.chat(messages: question).toList(),
      throwsA(issue(LocalModelStreamIssue.timeout)),
    );
    expect(pings, greaterThan(2));
    expect(client.closed, true);
    stream.close();
  });
  test(
    'actual HTTP owner retirement and user cancellation close an unfinished stream',
    () async {
      for (final retire in [false, true]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final bodyClosed = Completer<void>(),
            first = Completer<void>(),
            finished = Completer<void>();
        server.listen((request) async {
          await request.drain<void>();
          request.response.bufferOutput = false;
          request.response.headers.set(
            'Content-Type',
            'text/event-stream; charset=utf-8',
          );
          request.response.add(utf8.encode(delta('真实首段')));
          await request.response.flush();
          try {
            await request.response.done;
          } catch (_) {}
          if (!bodyClosed.isCompleted) bodyClosed.complete();
        });
        final stream = LocalModelStreamTransport(
          LocalModelConfig(
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            model: 'fixture',
          ),
        );
        final abort = Completer<void>();
        final events = <LocalModelStreamUpdate>[];
        Object? error;
        final subscription = stream
            .chat(messages: question, abortTrigger: abort.future)
            .listen(
              (event) {
                events.add(event);
                if (event.text.isNotEmpty && !first.isCompleted) {
                  first.complete();
                }
              },
              onError: (Object e) {
                error = e;
              },
              onDone: () => finished.complete(),
            );
        try {
          await Future.any<void>([
            first.future,
            finished.future.then((_) {
              final observed = error;
              throw StateError(
                'Stream ended before first delta: ${observed is LocalModelStreamFailure ? observed.issue.name : observed.runtimeType.toString()}',
              );
            }),
          ]).timeout(const Duration(seconds: 3));
          if (retire) {
            stream.close();
          } else {
            abort.complete();
          }
          await finished.future.timeout(const Duration(seconds: 2));
          expect(
            error,
            issue(
              retire
                  ? LocalModelStreamIssue.retired
                  : LocalModelStreamIssue.cancelled,
            ),
          );
          expect(events.single.text, '真实首段');
          expect(events.any((e) => e.turn != null), false);
        } finally {
          stream.close();
          await subscription.cancel();
          await server.close(force: true);
        }
      }
    },
  );
  test('already cancelled turn creates no HTTP client or request', () async {
    var clients = 0;
    final abort = Completer<void>()..complete();
    final stream = LocalModelStreamTransport(
      config,
      createClient: () {
        clients++;
        return FixtureClient(
          (_) async => http.StreamedResponse(const Stream.empty(), 200),
        );
      },
    );
    await expectLater(
      stream.chat(messages: question, abortTrigger: abort.future).toList(),
      throwsA(issue(LocalModelStreamIssue.cancelled)),
    );
    expect(clients, 0);
    stream.close();
  });
}
