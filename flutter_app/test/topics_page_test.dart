import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/topics.dart';

void main() {
  testWidgets('topic list opens actual ID and shows real counters', (
    tester,
  ) async {
    final repo = TopicsFixture();
    int? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicsPage(
          repository: repo,
          onOpenTopic: (id) async {
            opened = id;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2个主题'), findsOneWidget);
    expect(find.text('资料3 · 小结2 · 任务1'), findsOneWidget);
    await tester.tap(find.text('阅读与知识整理'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(repo.saveCalls, 0);
  });
  testWidgets(
    'topic deletion confirms associated tasks and leaves other topics intact',
    (tester) async {
      final repo = TopicsFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: TopicsPage(repository: repo, onOpenTopic: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('主题操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('主题内任务'), findsOneWidget);
      expect(repo.records.containsKey(1), isTrue);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(repo.records.containsKey(1), isFalse);
      expect(repo.records.containsKey(2), isTrue);
      expect(repo.taskRepository.records.containsKey(71), isFalse);
      expect(find.text('1个主题'), findsOneWidget);
    },
  );
  testWidgets('stale topic search cannot replace newer result', (tester) async {
    final repo = TopicsFixture();
    final old = Completer<TopicPageResult>();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicsPage(repository: repo, onOpenTopic: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    repo.listOverride = (query) async => query.keyword == '旧'
        ? await old.future
        : const TopicPageResult(
            [TopicItem(id: 3, memberId: 7, title: '新查询')],
            1,
            1,
            20,
          );
    await tester.enterText(find.byType(TextField), '旧');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    old.complete(
      const TopicPageResult(
        [TopicItem(id: 4, memberId: 7, title: '旧查询')],
        1,
        1,
        20,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新查询'), findsOneWidget);
    expect(find.text('旧查询'), findsNothing);
  });
  testWidgets('new topic save opens returned ID before refreshing list', (
    tester,
  ) async {
    final repo = TopicsFixture();
    int? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: TopicsPage(
          repository: repo,
          onOpenTopic: (id) async {
            opened = id;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建主题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新主题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(opened, 100);
    expect(repo.records[100]!.title, '新主题');
    expect(repo.saveCalls, 1);
    expect(find.text('3个主题'), findsOneWidget);
  });
}
