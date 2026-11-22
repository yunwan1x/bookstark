import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';

const sid = '0123456789abcdef0123456789abcdef';
const did = 'abcdef0123456789abcdef0123456789';
Map<String, Object?> draftData([String status = 'pending']) => {
  'id': did,
  'payload': {
    'kind': 'task',
    'title': '',
    'content': '每日阅读20分钟',
    'due_date': '2026-11-04',
  },
  'status': status,
  'url': status == 'done' ? '/notes?tab=tasks&task_id=9' : '',
};

class Repository extends AssistantRepository {
  Repository()
    : super(
        BookstarkClient(
          'https://example.test',
          transport: MockClient((_) async => http.Response('', 500)),
        ),
      );
  bool hold = false, existingDraft = false;
  int chats = 0, confirms = 0, cancels = 0, resets = 0;
  @override
  Future<AssistantSession> open() async => AssistantSession.fromJson({
    'id': sid,
    'busy': false,
    'drafts': existingDraft ? [draftData()] : [],
  });
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    chats++;
    yield const AssistantUpdate('round', round: 1);
    yield const AssistantUpdate('delta', text: '# In progress');
    if (hold) {
      await abortTrigger;
      throw StateError('cancelled');
    }
    yield AssistantUpdate(
      'done',
      messages: [
        AssistantMessage(role: 'user', content: message),
        const AssistantMessage(
          role: 'assistant',
          content: '# Answer\n\n- Item one',
        ),
      ],
      drafts: [AssistantDraft.fromJson(draftData())],
    );
  }

  @override
  Future<AssistantSession> reset(String id) async {
    resets++;
    return AssistantSession.fromJson({
      'id': 'fedcba9876543210fedcba9876543210',
      'busy': false,
      'drafts': [],
    });
  }

  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    if (confirm) {
      confirms++;
    } else {
      cancels++;
    }
    return AssistantDraft.fromJson(draftData(confirm ? 'done' : 'cancelled'));
  }

  @override
  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> source,
  ) async => const AssistantResourceDetail('Created task', '每日阅读20分钟');
}

class LongRepository extends Repository {
  final histories = <List<AssistantMessage>>[];
  final longReply =
      '# Large reply\n\n```text\n${List.filled(24001, 'x').join()}\n```';
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    histories.add(List.of(history));
    yield AssistantUpdate(
      'done',
      messages: [
        AssistantMessage(role: 'user', content: message),
        AssistantMessage(
          role: 'assistant',
          content: histories.length == 1 ? longReply : '# Short reply',
        ),
      ],
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  Repository repository, {
  AssistantConversationVault? vault,
  bool english = false,
  bool small = false,
}) async {
  tester.view.physicalSize = small
      ? const Size(320, 568)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(small ? 2 : 1),
          viewInsets: small
              ? const EdgeInsets.only(bottom: 200)
              : EdgeInsets.zero,
        ),
        child: child!,
      ),
      home: AssistantPage(
        repository: repository,
        vault: vault,
        english: english,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'explicit new conversation clears local context and pending draft cards only after reset succeeds',
    (tester) async {
      final repository = Repository()..existingDraft = true;
      final storage = <String, String>{};
      final vault = AssistantConversationVault(
        namespace: 'reset-test',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      await vault.save(sid, [
        const AssistantMessage(role: 'user', content: 'old question'),
        const AssistantMessage(role: 'assistant', content: 'old answer'),
      ], input: 'unsent');
      await mount(tester, repository, vault: vault);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建会话'));
      await tester.pumpAndSettle();
      expect(repository.resets, 0);
      await tester.tap(find.widgetWithText(FilledButton, '新建会话'));
      await tester.pumpAndSettle();
      expect(repository.resets, 1);
      expect(repository.confirms, 0);
      expect(repository.cancels, 0);
      expect(find.text('核对并创建'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        isEmpty,
      );
      final saved = await vault.load();
      expect(saved!.session, 'fedcba9876543210fedcba9876543210');
      expect(saved.messages, isEmpty);
      expect(saved.input, isEmpty);
    },
  );

  testWidgets(
    'long completed reply remains visible and retained while excluded from subsequent model context',
    (tester) async {
      final repository = LongRepository();
      final storage = <String, String>{};
      final vault = AssistantConversationVault(
        namespace: 'long-test',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      await mount(tester, repository, vault: vault);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'first question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect((await vault.load())!.messages.last.content, repository.longReply);
      expect(find.text('Large reply'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'second question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(repository.histories.last, isEmpty);
      expect((await vault.load())!.messages.length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Markdown reply and pending draft do not create anything before explicit review confirmation',
    (tester) async {
      final repository = Repository();
      await mount(tester, repository);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(repository.chats, 1);
      expect(repository.confirms, 0);
      await tester.ensureVisible(find.text('核对并创建'));
      await tester.tap(find.text('核对并创建'));
      await tester.pumpAndSettle();
      expect(repository.confirms, 0);
      await tester.tap(find.text('确认创建'));
      await tester.pumpAndSettle();
      expect(repository.confirms, 1);
      expect(repository.cancels, 0);
      expect(find.text('已创建'), findsOneWidget);
      expect(find.text('打开已创建资源'), findsOneWidget);
    },
  );
  testWidgets('explicit discard resolves cancel once and never confirms', (
    tester,
  ) async {
    final repository = Repository()..existingDraft = true;
    await mount(tester, repository);
    await tester.ensureVisible(find.text('放弃'));
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(repository.cancels, 1);
    expect(repository.confirms, 0);
    expect(find.text('已放弃'), findsOneWidget);
  });
  testWidgets(
    'stop aborts actual chat token and retains question without completing history',
    (tester) async {
      final repository = Repository()..hold = true;
      await mount(tester, repository);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'stop question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('停止回答'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已停止 ·'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        'stop question',
      );
      expect(repository.confirms, 0);
      expect(repository.chats, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('stopped partial survives reopening without automatic resend', (
    tester,
  ) async {
    final repository = Repository()..hold = true;
    final values = <String, String>{};
    AssistantConversationVault vault() => AssistantConversationVault(
      namespace: 'reopen-partial',
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    await mount(tester, repository, vault: vault());
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'interrupted question',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('停止回答'));
    await tester.pumpAndSettle();
    expect((await vault().load())!.partial, '# In progress');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await mount(tester, repository, vault: vault());
    expect(find.textContaining('已停止 ·'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect((await vault().load())!.messages, isEmpty);
    expect(repository.chats, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('refresh preserves newly typed input before debounce storage', (
    tester,
  ) async {
    final repository = Repository();
    await mount(tester, repository);
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'do not lose this',
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新草稿状态'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('assistant-input')))
          .controller!
          .text,
      'do not lose this',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'corrupt retained context can be explicitly cleared without touching server drafts',
    (tester) async {
      final repository = Repository()..existingDraft = true;
      String? record = 'broken-json';
      final vault = AssistantConversationVault(
        namespace: 'test',
        readValue: (key) async => record,
        writeValue: (key, value) async {
          record = value;
        },
        deleteValue: (key) async {
          record = null;
        },
      );
      await mount(tester, repository, vault: vault);
      await tester.tap(find.text('清空本地上下文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .enabled,
        isTrue,
      );
      expect(repository.confirms, 0);
      expect(repository.cancels, 0);
      expect((await vault.load())!.messages, isEmpty);
    },
  );
  testWidgets('English small-screen keyboard and double text do not overflow', (
    tester,
  ) async {
    await mount(tester, Repository(), english: true, small: true);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'question',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
