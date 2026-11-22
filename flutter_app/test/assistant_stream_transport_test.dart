import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  test(
    'assistant stream sends JSON, CSRF, language cookie and preserves prefix',
    () async {
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{"code":0}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          expect(r.url.path, '/base/api/ai/assistant/chat');
          expect(r.headers['accept'], 'text/event-stream');
          expect(r.headers['cookie'], contains('lang=en'));
          expect(r.headers['x-csrf-token'], 'x');
          expect(jsonDecode(r.body)['message'], 'hello');
          return http.Response(
            'event: delta\ndata: {"text":"hello"}\n\nevent: done\ndata: {"code":0}\n\n',
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }),
      );
      client.language = 'en';
      final events = await client.postEvents('/api/ai/assistant/chat', {
        'message': 'hello',
        'session_id': 's',
        'history': [],
      }).toList();
      expect(events.map((event) => event.type), ['delta', 'done']);
      expect(client.exportSession().containsKey('lang'), isFalse);
    },
  );
  test('cancelling subscription aborts request and source stream', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    Future<void>? abortion;
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient.streaming((r, body) async {
        abortion = (r as http.Abortable).abortTrigger;
        return http.StreamedResponse(
          source.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    client.restoreSession({'csrf_token': 'x'});
    final events = client
        .postEvents('/api/ai/assistant/chat', {})
        .take(1)
        .toList();
    source.add(utf8.encode('event: delta\ndata: {"text":"first"}\n\n'));
    expect((await events).single.type, 'delta');
    await abortion!.timeout(const Duration(seconds: 1));
    expect(cancelled, isTrue);
    await source.close();
  });
  test(
    'JSON service error is reported instead of being treated as completed chat',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => http.Response('{"code":403,"message":"disabled"}', 403),
        ),
      );
      client.restoreSession({'csrf_token': 'x'});
      await expectLater(
        client.postEvents('/api/ai/assistant/chat', {}).toList(),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.message,
            'message',
            'disabled',
          ),
        ),
      );
    },
  );
}
