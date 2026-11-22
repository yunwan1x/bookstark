import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topic_resource_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/topics.dart';
import '../tool/fixtures/topic_picker.dart';

class PartialTopicsFixture extends TopicsFixture {
  bool failSecond = true, loseFirstResponse = false;
  final calls = <int>[];
  @override
  Future<TopicResource> addResource(TopicResource value) async {
    calls.add(value.targetId);
    if (value.targetId == 12 && failSecond) throw StateError('测试添加失败');
    final saved = await super.addResource(value);
    if (value.targetId == 11 && loseFirstResponse) {
      loseFirstResponse = false;
      throw StateError('测试响应丢失');
    }
    return saved;
  }
}

Future<void> launch(
  WidgetTester tester,
  PartialTopicsFixture topics,
  TopicPickerFixture candidates,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => TopicResourcePickerPage(
                  repository: candidates,
                  topics: topics,
                  topic: topics.records[2]!,
                  existing: const {},
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
}

void main() {
  testWidgets(
    'selecting resources has no side effects and partial failure preserves remaining selection',
    (tester) async {
      final topics = PartialTopicsFixture();
      await launch(tester, topics, TopicPickerFixture());
      await tester.tap(find.text('阅读的意义'));
      await tester.tap(find.text('如何建立知识体系'));
      await tester.pumpAndSettle();
      expect(topics.calls, isEmpty);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(topics.calls, [11, 12]);
      await tester.scrollUntilVisible(
        find.text('已选择1项（最多50项）'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已选择1项（最多50项）'), findsOneWidget);
      expect(find.text('本次已添加1项'), findsOneWidget);
      expect(
        topics.resources.values.any(
          (row) =>
              row.topicId == 2 &&
              row.targetId == 11 &&
              row.type == TopicResourceType.note,
        ),
        isTrue,
      );
      topics.failSecond = false;
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(topics.calls, [11, 12, 12]);
      expect(find.byType(TopicResourcePickerPage), findsNothing);
    },
  );
  testWidgets('uncertain create result is verified without duplicate POST', (
    tester,
  ) async {
    final topics = PartialTopicsFixture()..loseFirstResponse = true;
    await launch(tester, topics, TopicPickerFixture());
    await tester.tap(find.text('阅读的意义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(topics.calls, [11]);
    expect(
      topics.resources.values
          .where(
            (row) =>
                row.topicId == 2 &&
                row.targetId == 11 &&
                row.type == TopicResourceType.note,
          )
          .length,
      1,
    );
    expect(find.byType(TopicResourcePickerPage), findsNothing);
  });
  testWidgets('document selection loads only after choosing an actual book', (
    tester,
  ) async {
    final topics = PartialTopicsFixture();
    final candidates = TopicPickerFixture();
    await launch(tester, topics, candidates);
    await tester.tap(find.widgetWithText(ChoiceChip, '文档'));
    await tester.pumpAndSettle();
    expect(find.text('请先选择书籍以加载章节'), findsOneWidget);
    await tester.tap(find.text('先选择书籍'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读的方法'));
    await tester.pumpAndSettle();
    expect(find.text('阅读的起点'), findsOneWidget);
    expect(topics.calls, isEmpty);
  });
}
