import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

const _sid = '0123456789abcdef0123456789abcdef';
const _partial = '\ufeff# Unfinished\n\n- exact partial α';

class _Repository extends Fake implements AssistantDataSource {
  bool stop = false, fail = false;
  final questions = <String>[];
  final histories = <List<AssistantMessage>>[];
  @override
  Future<AssistantSession> open() async =>
      AssistantSession.fromJson({'id': _sid, 'busy': false, 'drafts': []});
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    questions.add(message);
    histories.add(List.of(history));
    if (stop || fail) {
      yield const AssistantUpdate('delta', text: _partial);
      if (stop) await abortTrigger;
      throw StateError('interrupted fixture');
    }
    yield AssistantUpdate(
      'done',
      messages: [
        AssistantMessage(role: 'user', content: message),
        const AssistantMessage(
          role: 'assistant',
          content: '# New complete reply',
        ),
      ],
    );
  }
}

void main() {
  late AssistantConversationVault vault;
  setUp(() {
    final records = <String, String>{};
    vault = AssistantConversationVault(
      namespace: 'partial-replacement-fixture',
      readValue: (key) async => records[key],
      writeValue: (key, value) async {
        records[key] = value;
      },
      deleteValue: (key) async {
        records.remove(key);
      },
    );
  });
  Future<void> mount(
    WidgetTester tester,
    _Repository repository, {
    bool small = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = small
        ? const Size(320, 568)
        : const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            viewInsets: small
                ? const EdgeInsets.only(bottom: 180)
                : EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: AssistantPage(
          repository: repository,
          vault: vault,
          local: true,
          english: small,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seed() => vault.save(
    _sid,
    [],
    input: 'New question',
    pendingQuestion: 'Old unfinished question',
    partial: _partial,
  );
  Future<void> send(
    WidgetTester tester, {
    String question = 'New question',
    bool english = false,
  }) async {
    await tester.enterText(find.byKey(const Key('assistant-input')), question);
    await tester.pump();
    await tester.tap(find.byTooltip(english ? 'Send' : '发送'));
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> unchanged() async {
    final saved = await vault.load();
    expect(utf8.encode(saved!.partial), utf8.encode(_partial));
    expect(saved.pendingQuestion, 'Old unfinished question');
    expect(saved.messages, isEmpty);
  }

  testWidgets(
    'reopened stopped partial defaults to retaining exact bytes with no request',
    (tester) async {
      await seed();
      final repository = _Repository();
      await mount(tester, repository);
      await send(tester);
      expect(find.text('替换未完成回答？'), findsOneWidget);
      final preview = tester.widgetList<BookstarkMarkdown>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(BookstarkMarkdown),
        ),
      );
      expect(preview.single.data, _partial);
      await action(tester, '返回并保留');
      await unchanged();
      expect(repository.questions, isEmpty);
    },
  );
  testWidgets(
    'explicit replacement sends exactly once without partial in completed history',
    (tester) async {
      await seed();
      final repository = _Repository();
      await mount(tester, repository);
      await send(tester);
      expect(repository.questions, isEmpty);
      await action(tester, '替换并发送');
      expect(repository.questions, ['New question']);
      expect(repository.histories.single, isEmpty);
      final saved = await vault.load();
      expect(saved!.partial, isEmpty);
      expect(saved.pendingQuestion, isNull);
      expect(saved.messages.map((m) => m.content), [
        'New question',
        '# New complete reply',
      ]);
    },
  );
  testWidgets(
    'two fast send actions open one confirmation and cannot bypass it',
    (tester) async {
      await seed();
      final repository = _Repository();
      await mount(tester, repository);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '发送',
        ),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.questions, isEmpty);
      await action(tester, '返回并保留');
      await unchanged();
    },
  );
  testWidgets(
    'real stopped reply survives restart then cancelled replacement makes zero new calls',
    (tester) async {
      final repository = _Repository()..stop = true;
      await mount(tester, repository);
      await send(tester, question: 'Old unfinished question');
      await tester.tap(find.byTooltip('停止回答'));
      await tester.pumpAndSettle();
      expect(repository.questions.length, 1);
      expect((await vault.load())!.partial, _partial);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, repository);
      expect(repository.questions.length, 1);
      await send(tester);
      await action(tester, '返回并保留');
      await unchanged();
      expect(repository.questions.length, 1);
    },
  );
  testWidgets('real failed partial is retained until explicit replacement', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await mount(tester, repository);
    await send(tester, question: 'Old unfinished question');
    expect(repository.questions.length, 1);
    expect((await vault.load())!.partial, _partial);
    await send(tester);
    await action(tester, '返回并保留');
    await unchanged();
    expect(repository.questions.length, 1);
    repository.fail = false;
    await send(tester);
    await action(tester, '替换并发送');
    expect(repository.questions, ['Old unfinished question', 'New question']);
    expect(repository.histories.last, isEmpty);
  });
  testWidgets(
    'repository replacement during dialog cannot send through either owner',
    (tester) async {
      await seed();
      final old = _Repository(), next = _Repository();
      await mount(tester, old);
      await send(tester);
      await mount(tester, next);
      expect(find.byType(AlertDialog), findsOneWidget);
      await action(tester, '替换并发送');
      expect(old.questions, isEmpty);
      expect(next.questions, isEmpty);
      await unchanged();
    },
  );
  testWidgets(
    'disposing a pending confirmation does not send or destroy partial',
    (tester) async {
      await seed();
      final repository = _Repository();
      await mount(tester, repository);
      await send(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(repository.questions, isEmpty);
      await unchanged();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320dp 200 percent English keyboard confirmation remains scrollable',
    (tester) async {
      await seed();
      final repository = _Repository();
      await mount(tester, repository, small: true);
      await send(tester, english: true);
      expect(find.text('Replace the unfinished reply?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await action(tester, 'Keep unfinished reply');
      await unchanged();
      expect(repository.questions, isEmpty);
      await send(tester, english: true);
      await action(tester, 'Replace and send');
      expect(repository.questions, ['New question']);
      expect(repository.histories.single, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
