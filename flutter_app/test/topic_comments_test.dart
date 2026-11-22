import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topic_comments_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/topics.dart';

void main() {
  testWidgets(
    'comment target filter and shared editor preserve exact immutable target',
    (tester) async {
      final repo = TopicsFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: TopicCommentsPage(repository: repo, topic: repo.records[1]!),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2条评论'), findsOneWidget);
      await tester.tap(find.text('评论目标 · 全部目标'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('从记录走向行动'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.ensureVisible(find.text('从记录走向行动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从记录走向行动'));
      await tester.pumpAndSettle();
      expect(find.text('1条评论'), findsOneWidget);
      await tester.tap(find.byTooltip('添加评论'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPage), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '**新增评论**');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.commentRecords[100]!.target, TopicCommentTarget.summary);
      expect(repo.commentRecords[100]!.targetId, 31);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('2条评论'), findsOneWidget);
      expect(find.text('新增评论'), findsOneWidget);
    },
  );
  testWidgets(
    'comment deletion requires confirmation and never deletes target',
    (tester) async {
      final repo = TopicsFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: TopicCommentsPage(repository: repo, topic: repo.records[1]!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('评论操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(repo.commentRecords.length, 2);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(repo.commentRecords.length, 1);
      expect(repo.summaries.containsKey(31), isTrue);
      expect(find.text('1条评论'), findsOneWidget);
    },
  );
  testWidgets(
    'missing initial target clearly falls back to actual all-target list',
    (tester) async {
      final repo = TopicsFixture();
      await repo.removeSummary(1, 31);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: TopicCommentsPage(
            repository: repo,
            topic: repo.records[1]!,
            initialTarget: const TopicCommentDestination(
              TopicCommentTarget.summary,
              31,
              '从记录走向行动',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原评论目标已失效，当前显示全部目标。'), findsOneWidget);
      expect(find.text('1条评论'), findsOneWidget);
      expect(find.text('评论目标 · 全部目标'), findsOneWidget);
    },
  );
  testWidgets(
    'target picker can scroll with English double text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TopicsFixture();
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
          home: TopicCommentsPage(
            repository: repo,
            topic: repo.records[1]!,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Target · All targets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Target · All targets'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '小结');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
