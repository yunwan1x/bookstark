import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/completion_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String delta(String content, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': content},
          'finish_reason': ?finish,
        },
      ],
    })}\n\n';
void main() {
  RemoteCompletionRepository repository(
    String response, {
    void Function(http.Request)? onRequest,
  }) {
    final client = BookstarkClient(
      'https://example.test/base',
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/csrf-token')) {
          return http.Response(
            '{}',
            200,
            headers: {'set-cookie': 'csrf_token=test'},
          );
        }
        onRequest?.call(request);
        return http.Response(
          response,
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    return RemoteCompletionRepository(client);
  }

  test(
    'completion uses real generic endpoint and explicit scene with no writes',
    () async {
      final paths = <String>[];
      final repo = repository(
        '${delta('# 小结')}${delta('\n\n正文')}data: {"choices":[],"usage":{"completion_tokens":4}}\n\ndata: [DONE]\n\n',
        onRequest: (request) {
          paths.add(request.url.path);
          expect(request.headers['x-csrf-token'], 'test');
          final body = jsonDecode(request.body) as Map;
          expect(body['scene'], 'topic-summary');
          expect((body['messages'] as List).last['content'], contains('真实上下文'));
        },
      );
      final chunks = await repo
          .complete(
            context: '真实上下文',
            instruction: '整理成小结',
            scene: CompletionScene.topicSummary,
          )
          .toList();
      expect(chunks, ['# 小结', '\n\n正文']);
      expect(paths, ['/base/api/ai/complete']);
    },
  );
  test('partial body remains available but missing DONE is an error', () async {
    final chunks = <String>[];
    await expectLater(
      repository(delta('已有部分'))
          .complete(
            context: '',
            instruction: '继续',
            scene: CompletionScene.topicComment,
          )
          .forEach(chunks.add),
      throwsFormatException,
    );
    expect(chunks, ['已有部分']);
  });
  test(
    'length-truncated and blank completions cannot be called successful',
    () async {
      await expectLater(
        repository('${delta('部分', finish: 'length')}data: [DONE]\n\n')
            .complete(
              context: '',
              instruction: '生成',
              scene: CompletionScene.topicSummary,
            )
            .drain<void>(),
        throwsFormatException,
      );
      await expectLater(
        repository('data: [DONE]\n\n')
            .complete(
              context: '',
              instruction: '生成',
              scene: CompletionScene.topicSummary,
            )
            .drain<void>(),
        throwsFormatException,
      );
    },
  );
  test(
    'oversized context and output refuse rather than silently truncate',
    () async {
      var requests = 0;
      final repo = repository(
        '${delta(List.filled(20001, '📖').join())}data: [DONE]\n\n',
        onRequest: (_) {
          requests++;
        },
      );
      await expectLater(
        repo
            .complete(
              context: List.filled(20001, '字').join(),
              instruction: '生成',
              scene: CompletionScene.topicSummary,
            )
            .drain<void>(),
        throwsFormatException,
      );
      expect(requests, 0);
      await expectLater(
        repo
            .complete(
              context: '',
              instruction: '生成',
              scene: CompletionScene.topicSummary,
            )
            .drain<void>(),
        throwsFormatException,
      );
      expect(requests, 1);
    },
  );
}
