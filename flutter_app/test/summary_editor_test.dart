import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/summary_editor_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'summary uses shared Markdown editor without title or label fields',
    (tester) async {
      final writes = <String>[];
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=test'},
            );
          }
          writes.add('${request.method} ${request.url.path}');
          expect(jsonDecode(request.body), {
            'content': '# 小结',
            'expected_source_sha256': sha256
                .convert(utf8.encode('# 小结'))
                .toString(),
          });
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'summary_id': 9,
                'topic_id': 4,
                'content': '# 小结',
                'summary_type': 'ai',
                'order_sort': 7,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final repo = SummaryEditorRepository(
        RemoteTopicsRepository(client, memberId: 7),
        const TopicSummary(
          id: 9,
          topicId: 4,
          content: '# 小结',
          type: 'ai',
          order: 7,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: NoteEditorPage(
            repository: repo,
            note: const Note(id: 9, title: '', content: '# 小结'),
            documentPath: '主题 · AI小结',
            contentEditorTitle: '编辑小结',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('文档名称'), findsNothing);
      expect(find.text('添加标签'), findsNothing);
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      expect(find.text('小结'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(writes, ['PUT /api/topics/4/summaries/9/content']);
    },
  );
  testWidgets(
    'created summary subsequent save uses real ID and lifecycle draft isolation',
    (tester) async {
      final writes = <String>[];
      final values = <String, String>{};
      final vault = DraftVault(
        namespace: 'server/7/topic/4/summary',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=test'},
            );
          }
          writes.add('${request.method} ${request.url.path}');
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map;
            expect(body.keys.toSet(), {'content', 'expected_source_sha256'});
            expect(
              body['expected_source_sha256'],
              sha256.convert(utf8.encode('# 第一稿')).toString(),
            );
          }
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'summary_id': 21,
                'topic_id': 4,
                'content': (jsonDecode(request.body) as Map)['content'],
                'summary_type': 'manual',
                'order_sort': 0,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final repo = SummaryEditorRepository(
        RemoteTopicsRepository(client, memberId: 7),
        const TopicSummary(topicId: 4, content: ''),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: NoteEditorPage(
            repository: repo,
            note: const Note(title: '', content: ''),
            drafts: vault,
            documentPath: '主题 · 手动记录',
            contentEditorTitle: '编辑小结',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '# 第一稿');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '# 第二稿');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(writes, [
        'POST /api/topics/4/summaries',
        'PUT /api/topics/4/summaries/21/content',
      ]);
      await tester.enterText(find.byType(TextField), '# 未保存');
      await tester.pump(const Duration(seconds: 1));
      expect((await vault.read(21))?.content, '# 未保存');
    },
  );
  testWidgets('summary Unicode limit rejects before HTTP', (tester) async {
    var calls = 0;
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final repo = SummaryEditorRepository(
      RemoteTopicsRepository(client, memberId: 7),
      const TopicSummary(topicId: 4, content: ''),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: NoteEditorPage(
          repository: repo,
          note: const Note(title: '', content: ''),
          documentPath: '主题',
          contentEditorTitle: '编辑小结',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      List.filled(20001, '📖').join(),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('正文最多20000字'), findsOneWidget);
  });
}
