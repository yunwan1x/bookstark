import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/completion_repository.dart';
import 'package:bookstark_flutter/features/topics/ai_draft_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCompletion implements CompletionRepository {
  final controllers = <StreamController<String>>[];
  int aborted = 0, cancelled = 0;
  @override
  Stream<String> complete({
    required String context,
    required String instruction,
    required CompletionScene scene,
    Future<void>? abortTrigger,
  }) {
    abortTrigger?.then((_) {
      aborted++;
    });
    final controller = StreamController<String>(
      onCancel: () async {
        cancelled++;
      },
    );
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  testWidgets(
    'AI stop really aborts and returns only explicitly adopted incomplete draft',
    (tester) async {
      final repo = FakeCompletion();
      CompletionDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<CompletionDraft>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AIDraftPage(
                        repository: repo,
                        title: '主题',
                        initialContext: '真实上下文',
                        initialInstruction: '提炼行动',
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始生成'));
      await tester.pump();
      repo.controllers.single.add('# 部分小结');
      await tester.pump();
      expect(result, isNull);
      await tester.ensureVisible(find.text('停止生成'));
      await tester.pump();
      await tester.tap(find.text('停止生成'));
      await tester.pumpAndSettle();
      expect(repo.aborted, 1);
      expect(repo.cancelled, 1);
      expect(find.text('已停止，内容尚不完整'), findsOneWidget);
      repo.controllers.single.add('不能再追加');
      await tester.pump();
      expect(find.textContaining('不能再追加'), findsNothing);
      await tester.ensureVisible(find.text('编辑当前草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑当前草稿'));
      await tester.pumpAndSettle();
      expect(result?.markdown, '# 部分小结');
      expect(result?.complete, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      unawaited(repo.controllers.single.close());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
  testWidgets(
    'completed AI draft is not adopted automatically and regeneration confirms replacement',
    (tester) async {
      final repo = FakeCompletion();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: AIDraftPage(
            repository: repo,
            title: '主题',
            initialContext: '',
            initialInstruction: '生成小结',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始生成'));
      await tester.pump();
      repo.controllers.single.add('## 已生成的小结');
      unawaited(repo.controllers.single.close());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('生成完成'), findsOneWidget);
      expect(find.byType(AIDraftPage), findsOneWidget);
      await tester.ensureVisible(find.text('重新生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();
      expect(repo.controllers.length, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('生成完成'), findsOneWidget);
      expect(repo.controllers.length, 1);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
  testWidgets('AI failure retains partial text and never marks completion', (
    tester,
  ) async {
    final repo = FakeCompletion();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: AIDraftPage(
          repository: repo,
          title: '主题',
          initialContext: '',
          initialInstruction: '生成',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始生成'));
    await tester.pump();
    repo.controllers.single.add('保留部分正文');
    repo.controllers.single.addError(const FormatException('连接中断'));
    await tester.pumpAndSettle();
    expect(find.text('生成完成'), findsNothing);
    expect(find.text('生成未完成'), findsOneWidget);
    expect(find.textContaining('连接中断'), findsOneWidget);
    expect(find.text('保留部分正文'), findsOneWidget);
    unawaited(repo.controllers.single.close());
    await tester.pump();
  });
  testWidgets('English AI draft supports narrow large text and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        home: AIDraftPage(
          repository: FakeCompletion(),
          title: 'A topic',
          initialContext: '',
          initialInstruction: 'Write a summary',
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Generate'),
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
  });
}
