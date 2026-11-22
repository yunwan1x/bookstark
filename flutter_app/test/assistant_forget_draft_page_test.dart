import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';

const session = '0123456789abcdef0123456789abcdef';
const recordId = 'abcdef0123456789abcdef0123456789';

class _Repository implements AssistantDataSource {
  String status = 'done';
  bool present = true;
  int opens = 0, resolves = 0, chats = 0;
  final savedResources = {9: 'Actual saved resource'};
  @override
  Future<AssistantSession> open() async {
    opens++;
    return AssistantSession.fromJson({
      'id': session,
      'busy': false,
      'drafts': [
        if (present)
          {
            'id': recordId,
            'status': status,
            'payload': {
              'kind': 'note',
              'title': 'Proposal record',
              'content': '## Original body',
            },
            'url': status == 'done' ? '/notes?tab=notes&id=9' : '',
          },
      ],
    });
  }

  @override
  Future<AssistantSession> reset(String id) => throw UnimplementedError();
  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    resolves++;
    throw UnimplementedError();
  }

  @override
  Future<AssistantResourceDetail> readSource(Map<String, Object?> source) =>
      throw UnimplementedError();
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    chats++;
    throw UnimplementedError();
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Repository repo, {
    bool local = true,
    bool large = false,
    Future<void> Function(String)? forget,
  }) async {
    tester.view.physicalSize = large
        ? const Size(320, 640)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!,
        ),
        home: AssistantPage(
          repository: repo,
          local: local,
          english: large,
          onForgetLocalDraft: forget,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester, {bool english = false}) async {
    final label = english ? 'Remove this record' : '移除此记录';
    final target = find.widgetWithText(TextButton, label);
    for (var attempt = 0; attempt < 30; attempt++) {
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        if (target.hitTestable().evaluate().isNotEmpty) break;
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -160));
      await tester.pumpAndSettle();
    }
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'explicit confirm removes list record then refreshes without touching saved resources or remote resolve',
    (tester) async {
      final repo = _Repository();
      var forgets = 0;
      await mount(
        tester,
        repo,
        forget: (id) async {
          expect(id, recordId);
          forgets++;
          repo.present = false;
        },
      );
      await openDialog(tester);
      expect(forgets, 0);
      expect(repo.resolves, 0);
      expect(find.textContaining('不会删除已保存资料或保留草稿'), findsOneWidget);
      await tester.tap(find.text('返回并保留'));
      await tester.pumpAndSettle();
      expect(forgets, 0);
      expect(repo.opens, 1);
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '确认移除此记录'));
      await tester.pumpAndSettle();
      expect(forgets, 1);
      expect(repo.opens, 2);
      expect(repo.resolves, 0);
      expect(repo.chats, 0);
      expect(find.text('Proposal record'), findsNothing);
      expect(repo.savedResources, {9: 'Actual saved resource'});
    },
  );
  testWidgets(
    'linked recovery data shows fixed message and retains record without freeing quota',
    (tester) async {
      final repo = _Repository()..status = 'cancelled';
      await mount(
        tester,
        repo,
        forget: (_) async => throw const LocalAssistantDraftNeedsAttention(),
      );
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '确认移除此记录'));
      await tester.pumpAndSettle();
      // Error is above the card; scroll back to it.
      await tester.scrollUntilVisible(
        find.text('仍有关联草稿，请先在本地备份的恢复管理中处理。'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('仍有关联草稿，请先在本地备份的恢复管理中处理。'), findsOneWidget);
      expect(repo.present, true);
      expect(repo.opens, 1);
      expect(repo.resolves, 0);
      expect(repo.savedResources.length, 1);
    },
  );
  testWidgets(
    'in-flight cleanup disables duplicate clicks and send until fresh acknowledgement',
    (tester) async {
      final repo = _Repository();
      final finish = Completer<void>();
      var forgets = 0;
      await mount(
        tester,
        repo,
        forget: (_) async {
          forgets++;
          await finish.future;
          repo.present = false;
        },
      );
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '确认移除此记录'));
      await tester.pumpAndSettle();
      expect(forgets, 1);
      final removing = find.widgetWithText(TextButton, '移除中…');
      expect(tester.widget<TextButton>(removing).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Keep pending input');
      await tester.pump();
      final send = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '发送',
        ),
      );
      expect(send.onPressed, isNull);
      expect(repo.chats, 0);
      finish.complete();
      await tester.pumpAndSettle();
      expect(forgets, 1);
      expect(repo.opens, 2);
      expect(repo.present, false);
    },
  );
  testWidgets(
    'no callback and remote sessions expose no local terminal cleanup action',
    (tester) async {
      final repo = _Repository();
      await mount(tester, repo);
      expect(find.text('移除此记录'), findsNothing);
      await mount(
        tester,
        repo,
        local: false,
        forget: (_) async => throw StateError('must not call'),
      );
      expect(find.text('移除此记录'), findsNothing);
    },
  );
  testWidgets(
    'unknown and pending states never offer terminal removal despite supplied callback',
    (tester) async {
      final repo = _Repository()..status = 'unknown';
      await mount(
        tester,
        repo,
        forget: (_) async => throw StateError('must not call'),
      );
      expect(find.text('移除此记录'), findsNothing);
      repo.status = 'pending';
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(
        tester,
        repo,
        forget: (_) async => throw StateError('must not call'),
      );
      expect(find.text('移除此记录'), findsNothing);
    },
  );
  testWidgets(
    'English320dp200 scrolls terminal confirmation and refreshes actual list',
    (tester) async {
      final repo = _Repository()..status = 'cancelled';
      var forgets = 0;
      await mount(
        tester,
        repo,
        large: true,
        forget: (_) async {
          forgets++;
          repo.present = false;
        },
      );
      await openDialog(tester, english: true);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Remove this record'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove this record'));
      await tester.pumpAndSettle();
      expect(forgets, 1);
      expect(repo.opens, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown ledger storage failure is not optimistic removal or refresh',
    (tester) async {
      final repo = _Repository();
      await mount(
        tester,
        repo,
        forget: (_) async => throw const LocalAssistantDraftStorageUnknown(),
      );
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, '确认移除此记录'));
      await tester.pumpAndSettle();
      expect(repo.present, true);
      expect(repo.opens, 1);
      expect(find.text('Proposal record'), findsOneWidget);
      expect(repo.savedResources.length, 1);
    },
  );
}
