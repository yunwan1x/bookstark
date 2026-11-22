import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topic_draft_vault.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topic_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'failed topic save preserves title, question, pin and secure draft restoration',
    (tester) async {
      final values = <String, String>{};
      final vault = TopicDraftVault(
        namespace: 'server/user/topic',
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
          return http.Response('{"message":"Unavailable"}', 503);
        }),
      );
      addTearDown(client.close);
      final repository = RemoteTopicsRepository(client, memberId: 7);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TopicEditorPage(
                      repository: repository,
                      topic: const TopicItem(title: ''),
                      vault: vault,
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '我的主题');
      await tester.enterText(find.byType(TextField).last, '真实问题');
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿'));
      await tester.pumpAndSettle();
      final draft = (await vault.read(const TopicItem(title: '')))!;
      expect(draft.title, '我的主题');
      expect(draft.question, '真实问题');
      expect(draft.isPinned, isTrue);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('发现主题草稿'), findsOneWidget);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('我的主题'), findsOneWidget);
      expect(find.text('真实问题'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );
  testWidgets('draft cleanup failure after create retries same topic ID', (
    tester,
  ) async {
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
        return http.Response(
          jsonEncode({
            'topic_id': 21,
            'member_id': 7,
            ...jsonDecode(request.body) as Map,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    final vault = TopicDraftVault(
      namespace: 'test',
      readValue: (_) async => null,
      writeValue: (_, _) async {},
      deleteValue: (_) async => throw StateError('cleanup failed'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicEditorPage(
          repository: RemoteTopicsRepository(client, memberId: 7),
          topic: const TopicItem(title: '主题'),
          vault: vault,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cleanup failed'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(writes, ['POST /api/topics', 'PUT /api/topics/21']);
  });
  testWidgets(
    'English topic editor scrolls at 320dp with 200 percent text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 200),
            ),
            child: child!,
          ),
          home: TopicEditorPage(
            repository: RemoteTopicsRepository(client, memberId: 7),
            topic: const TopicItem(title: 'A topic'),
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Pin topic'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
