import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'speech HTTP retains same-origin prefix and CSRF while yielding before done; cancellation aborts transport',
    () async {
      final audio = StreamController<List<int>>();
      final requested = Completer<http.AbortableRequest>();
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient.streaming((request, body) async {
          if (request.url.path.endsWith('/csrf-token')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              200,
              headers: {
                'set-cookie': 'csrf_token=test-csrf',
                'content-type': 'application/json',
              },
            );
          }
          expect(request.url.path, '/base/api/ai/tts/stream');
          expect(request.followRedirects, isFalse);
          expect(request.headers['x-csrf-token'], 'test-csrf');
          expect(request.headers['cookie'], contains('csrf_token=test-csrf'));
          expect(request.headers['accept'], 'application/x-ndjson');
          final data = jsonDecode(utf8.decode(await body.toBytes())) as Map;
          expect(data, {'text': '中文朗读', 'voice': 'zh-CN-YunxiNeural'});
          requested.complete(request as http.AbortableRequest);
          return http.StreamedResponse(
            audio.stream,
            200,
            headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final abort = Completer<void>();
      final iterator = StreamIterator(
        RemoteSpeechRepository(
          client,
        ).audio(' 中文朗读 ', 'zh-CN-YunxiNeural', abortTrigger: abort.future),
      );
      final first = iterator.moveNext();
      final request = await requested.future;
      audio.add(utf8.encode('{"event":"audio","data":"AQID"}\n'));
      expect(await first, isTrue);
      expect(iterator.current, [1, 2, 3]);
      await iterator.cancel();
      await request.abortTrigger!.timeout(const Duration(seconds: 2));
      await audio.close();
    },
  );
  test(
    'speech voices use top-level real endpoint and invalid requests never reach transport',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          requests++;
          expect(request.url.path, '/api/ai/tts/voices');
          return http.Response(
            '{"code":0,"voices":[{"id":"en-US-AriaNeural","name":"Aria","locale":"en-US"}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final repo = RemoteSpeechRepository(client);
      expect((await repo.voices()).single.id, 'en-US-AriaNeural');
      final abort = Completer<void>();
      expect(
        () => repo.audio('', 'en-US-AriaNeural', abortTrigger: abort.future),
        throwsFormatException,
      );
      expect(
        () => repo.audio(
          List.filled(801, '📖').join(),
          'en-US-AriaNeural',
          abortTrigger: abort.future,
        ),
        throwsFormatException,
      );
      expect(
        () =>
            repo.audio('hello', 'invalid\r\nvoice', abortTrigger: abort.future),
        throwsFormatException,
      );
      expect(requests, 1);
    },
  );
  for (final mime in <String?>[null, 'text/html', 'text/plain']) {
    test(
      'speech catalogue refuses non-JSON MIME $mime even with plausible JSON',
      () async {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient(
            (_) async => http.Response(
              '{"code":0,"voices":[{"id":"en-US-AriaNeural","name":"Aria","locale":"en-US"}]}',
              200,
              headers: mime == null
                  ? <String, String>{}
                  : {'content-type': mime},
            ),
          ),
        );
        addTearDown(client.close);
        await expectLater(
          RemoteSpeechRepository(client).voices(),
          throwsFormatException,
        );
      },
    );
  }
}
