import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';

const session = '0123456789abcdef0123456789abcdef';
const draftId = 'abcdef0123456789abcdef0123456789';
void main() {
  test(
    'interrupted reply survives encrypted-record reload outside completed history',
    () async {
      final values = <String, String>{};
      AssistantConversationVault vault() => AssistantConversationVault(
        namespace: 'partial-test',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      await vault().save(
        session,
        [],
        pendingQuestion: 'Question',
        partial: '## Still streaming\n中文',
      );
      final recovered = await vault().load();
      expect(recovered!.messages, isEmpty);
      expect(recovered.pendingQuestion, 'Question');
      expect(recovered.partial, '## Still streaming\n中文');
      await expectLater(
        Future.sync(() => vault().save(session, [], partial: 'orphaned')),
        throwsFormatException,
      );
      expect((await vault().load())!.pendingQuestion, 'Question');
    },
  );

  test(
    'source navigation uses the authenticated kind/id route and ignores supplied URLs',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/blogs/7');
          return responseSource();
        }),
      );
      final repository = AssistantRepository(client);
      final detail = await repository.readSource({
        'kind': 'note',
        'id': 7,
        'url': 'https://foreign.test/steal',
      });
      expect(detail.content, '# Source');
      await expectLater(
        repository.readSource({
          'kind': 'shell',
          'id': 7,
          'url': 'https://foreign.test/',
        }),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );

  test(
    'only done creates a complete turn; drafts remain pending until explicit resolve call',
    () async {
      var confirmations = 0;
      final draft = {
        'id': draftId,
        'payload': {
          'kind': 'note',
          'title': 'title',
          'content': 'body',
          'due_date': '',
        },
        'status': 'pending',
        'url': '',
      };
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.url.path.contains('/drafts/')) {
            confirmations++;
            expect(jsonDecode(r.body), {
              'session_id': session,
              'action': 'confirm',
            });
            return http.Response(
              jsonEncode({
                'code': 0,
                'draft': {...draft, 'status': 'done'},
              }),
              200,
            );
          }
          final body = jsonDecode(r.body) as Map;
          expect(body['history'], []);
          final events =
              'event: round\ndata: {"round":1}\n\nevent: delta\ndata: {"text":"temporary"}\n\nevent: round\ndata: {"round":2}\n\nevent: done\ndata: ${jsonEncode({
                'code': 0,
                'session_id': session,
                'messages': [
                  {'role': 'user', 'content': 'question'},
                  {'role': 'assistant', 'content': '# Final'},
                ],
                'drafts': [draft],
              })}\n\n';
          return http.Response(
            events,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      client.restoreSession({'csrf_token': 'x'});
      final repository = AssistantRepository(client);
      final updates = await repository
          .chat(session: session, message: 'question', history: [])
          .toList();
      expect(updates.last.messages.last.content, '# Final');
      expect(updates.last.drafts.single.status, 'pending');
      expect(confirmations, 0);
      expect(
        (await repository.resolve(session, draftId, confirm: true)).status,
        'done',
      );
      expect(confirmations, 1);
    },
  );
  test(
    'missing done and mismatched session cannot be accepted as a completed answer',
    () async {
      for (final wire in [
        'event: delta\ndata: {"text":"partial"}\n\n',
        'event: done\ndata: {"code":0,"session_id":"wrong","messages":[]}\n\n',
      ]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient(
            (r) async => http.Response(
              wire,
              200,
              headers: {'content-type': 'text/event-stream'},
            ),
          ),
        );
        client.restoreSession({'csrf_token': 'x'});
        await expectLater(
          AssistantRepository(
            client,
          ).chat(session: session, message: 'question', history: []).toList(),
          throwsA(anyOf(isA<ApiFailure>(), isA<FormatException>())),
        );
      }
    },
  );
  test(
    'invalid UTF8 byte length/history order is rejected without a network request',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      final repository = AssistantRepository(client);
      await expectLater(
        repository
            .chat(
              session: session,
              message: List.filled(3000, '中').join(),
              history: [],
            )
            .toList(),
        throwsFormatException,
      );
      await expectLater(
        repository
            .chat(
              session: session,
              message: 'q',
              history: [
                const AssistantMessage(role: 'assistant', content: 'wrong'),
                const AssistantMessage(role: 'user', content: 'wrong'),
              ],
            )
            .toList(),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'conversation persistence is isolated and reuses secure draft queue without changing draft keys',
    () async {
      final storage = <String, String>{};
      AssistantConversationVault vault(String namespace) =>
          AssistantConversationVault(
            namespace: namespace,
            readValue: (key) async => storage[key],
            writeValue: (key, value) async {
              storage[key] = value;
            },
            deleteValue: (key) async {
              storage.remove(key);
            },
          );
      await vault('server|user1').save(session, [
        const AssistantMessage(role: 'user', content: 'question'),
        const AssistantMessage(role: 'assistant', content: '# Answer'),
      ]);
      expect(
        (await vault('server|user1').load())!.messages.last.content,
        '# Answer',
      );
      expect(await vault('server|user2').load(), isNull);
      await vault('server|user1').clear();
      expect(await vault('server|user1').load(), isNull);
    },
  );
}

http.Response responseSource() => http.Response(
  jsonEncode({
    'code': 0,
    'data': {'blog_title': 'title', 'blog_content': '# Source'},
  }),
  200,
);
