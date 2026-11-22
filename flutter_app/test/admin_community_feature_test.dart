import 'dart:async';
import 'dart:io';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_community_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_community_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_community_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_community_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_friend_links_models.dart';
import 'package:bookstark_flutter/features/admin/admin_friend_links_page.dart';
import 'package:bookstark_flutter/features/admin/admin_friend_link_editor_page.dart';
import 'package:bookstark_flutter/features/admin/admin_community_confirmation_pages.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'admin_community_controller_test.dart' as fixture;

final image = File('test/fixtures/admin_community_qr.png').readAsBytesSync();
Widget root(
  AdminCommunityScope scope,
  AdminCommunityController controller,
  AdminCommunityKind kind, {
  bool english = false,
  double scale = 1,
  VoidCallback? onReturn,
}) => MaterialApp(
  theme: bookstarkTheme(),
  locale: Locale(english ? 'en' : 'zh'),
  supportedLocales: const [Locale('zh'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: AdminCommunityFeature(
    key: const ValueKey('community-under-test'),
    scope: scope,
    controller: controller,
    kind: kind,
    english: english,
    onReturn: onReturn ?? () {},
    qrTransportFactory: () =>
        MockClient((_) async => http.Response.bytes(image, 200)),
  ),
);
Future<void> viewport(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<
  ({
    fixture.LinksRepository repository,
    AdminFriendLinksController controller,
    AdminCommunityScope scope,
  })
>
mountLinks(
  WidgetTester tester, {
  fixture.LinksRepository? repository,
  bool english = false,
  double width = 390,
  double scale = 1,
}) async {
  await viewport(tester, width);
  final repo = repository ?? fixture.LinksRepository();
  final c = AdminFriendLinksController(repo, fixture.owner),
      scope = AdminCommunityScope(repo.client, fixture.owner);
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    root(scope, c, AdminCommunityKind.links, english: english, scale: scale),
  );
  await tester.pumpAndSettle();
  return (repository: repo, controller: c, scope: scope);
}

Future<
  ({
    fixture.CommentsRepository repository,
    AdminCommentsController controller,
    AdminCommunityScope scope,
  })
>
mountComments(
  WidgetTester tester, {
  fixture.CommentsRepository? repository,
  bool english = false,
  double width = 390,
  double scale = 1,
}) async {
  await viewport(tester, width);
  final repo = repository ?? fixture.CommentsRepository();
  final c = AdminCommentsController(repo, fixture.owner),
      scope = AdminCommunityScope(repo.client, fixture.owner);
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    root(scope, c, AdminCommunityKind.comments, english: english, scale: scale),
  );
  await tester.pumpAndSettle();
  return (repository: repo, controller: c, scope: scope);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder.hitTestable(),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> finish(WidgetTester tester, AdminCommunityScope scope) async {
  await tester.pumpWidget(const SizedBox.shrink());
  scope.dispose();
  await tester.pumpAndSettle();
}

Finder dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);
Finder dialogCancel() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextButton, '取消'),
);
fixture.LinksRepository normalLinks() => fixture.LinksRepository()
  ..data = AdminFriendLinksSnapshot(
    items: [fixture.linksData().items.single.edit(qr: '')],
    simpleMode: false,
  );
Future<void> editFirst(WidgetTester tester) async =>
    tapVisible(tester, find.text('编辑'));
Future<void> toggleSimple(WidgetTester tester) async => tapVisible(
  tester,
  find.descendant(
    of: find.byKey(const ValueKey('friend-links-simple-mode')),
    matching: find.byType(Switch),
  ),
);
void main() {
  testWidgets(
    'link editor applies only local draft and explicit save commits once',
    (tester) async {
      final h = await mountLinks(tester, repository: normalLinks());
      await editFirst(tester);
      await tester.enterText(
        find.byKey(const ValueKey('friend-editor-name')),
        'updated fixture',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '应用到草稿'));
      expect(find.byType(AdminFriendLinksPage), findsOneWidget);
      expect(h.repository.writes, 0);
      expect(h.controller.rows.single.link.name, 'updated fixture');
      expect(h.controller.rows.single.link.raw['future'], {'keep': true});
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存全部'));
      expect(find.byType(AdminFriendLinksSavePage), findsOneWidget);
      expect(h.repository.writes, 0);
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认保存全部'));
      expect(h.repository.writes, 1);
      expect(h.controller.dirty, isFalse);
      expect(find.byType(AdminFriendLinksPage), findsOneWidget);
      await finish(tester, h.scope);
    },
  );
  testWidgets('cancel full-link confirmation preserves draft without a write', (
    tester,
  ) async {
    final h = await mountLinks(tester);
    await toggleSimple(tester);
    await tapVisible(tester, find.widgetWithText(FilledButton, '保存全部'));
    await tapVisible(tester, find.widgetWithText(OutlinedButton, '返回核对'));
    expect(h.repository.writes, 0);
    expect(h.controller.dirty, isTrue);
    expect(h.controller.simpleMode, isTrue);
    await finish(tester, h.scope);
  });
  testWidgets(
    'remove draft confirmation is owned and empty list requires explicit save',
    (tester) async {
      final h = await mountLinks(tester, repository: normalLinks());
      await editFirst(tester);
      await tapVisible(tester, find.text('移除这条草稿'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        Navigator.of(
          tester.element(find.byType(AdminCommunityFeature)),
        ).canPop(),
        isFalse,
      );
      await tester.tap(dialogCancel());
      await tester.pumpAndSettle();
      expect(h.controller.rows.length, 1);
      expect(h.repository.writes, 0);
      await tapVisible(tester, find.text('移除这条草稿'));
      await tester.tap(dialogButton('移除草稿'));
      await tester.pumpAndSettle();
      expect(h.controller.rows, isEmpty);
      expect(h.repository.writes, 0);
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存全部'));
      expect(find.textContaining('将清空全部友情链接'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认保存全部'));
      expect(h.repository.writes, 1);
      expect(h.repository.data.items, isEmpty);
      await finish(tester, h.scope);
    },
  );
  testWidgets('new ordinary and QR choices keep all actual editor fields', (
    tester,
  ) async {
    final h = await mountLinks(tester, repository: normalLinks());
    await tester.tap(find.byTooltip('新增友情链接'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '新增二维码条目'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminFriendLinkEditorPage), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('friend-editor-name')),
      'new QR fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey('friend-editor-qr')),
      '/upload-files/fixture.png',
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, '应用到草稿'));
    expect(h.controller.rows.length, 2);
    expect(h.repository.writes, 0);
    expect(h.controller.rows.last.link.qr, '/upload-files/fixture.png');
    expect(h.controller.rows.last.link.url, isEmpty);
    await finish(tester, h.scope);
  });
  testWidgets(
    'editor validation notice removal preserves consecutive platform input',
    (tester) async {
      final h = await mountLinks(tester, repository: normalLinks());
      await editFirst(tester);
      final name = find.byKey(const ValueKey('friend-editor-name'));
      await tester.enterText(name, '');
      await tapVisible(tester, find.widgetWithText(FilledButton, '应用到草稿'));
      expect(find.textContaining('请检查名称'), findsOneWidget);
      await tester.showKeyboard(name);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'new fixture',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('请检查名称'), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'new fixture more',
          selection: TextSelection.collapsed(offset: 16),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(name).controller!.text,
        'new fixture more',
      );
      expect(h.repository.writes, 0);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'unknown link save requires read then explicit local-draft adoption',
    (tester) async {
      final repo = normalLinks()
        ..writeError = const AdminCommunityWriteUnknown();
      final h = await mountLinks(tester, repository: repo);
      await toggleSimple(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存全部'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认保存全部'));
      expect(h.controller.phase, AdminCommunityPhase.unknown);
      expect(repo.reads, 1);
      expect(repo.writes, 1);
      await tapVisible(tester, find.text('只读取当前配置'));
      expect(h.controller.phase, AdminCommunityPhase.reviewing);
      expect(repo.writes, 1);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, '采用当前配置并结束核对'),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(dialogCancel());
      await tester.pumpAndSettle();
      expect(h.controller.pending, isTrue);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, '采用当前配置并结束核对'),
      );
      await tester.tap(dialogButton('采用当前配置'));
      await tester.pumpAndSettle();
      expect(h.controller.ready, isTrue);
      expect(h.controller.notice, AdminCommunityNotice.reviewEnded);
      expect(repo.writes, 1);
      await finish(tester, h.scope);
    },
  );

  testWidgets(
    'comment cancel preserves selected ids and confirm shows actual affected count',
    (tester) async {
      final h = await mountComments(tester);
      final selected = find.descendant(
        of: find.byKey(const ValueKey('comment-2')),
        matching: find.byType(Checkbox),
      );
      await tapVisible(tester, selected);
      await tapVisible(tester, find.widgetWithText(FilledButton, '永久删除'));
      expect(find.byType(AdminCommentDeletePage), findsOneWidget);
      expect(h.repository.writes, 0);
      expect(find.textContaining('实际删除数量可能更多'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(OutlinedButton, '取消'));
      expect(h.controller.selected, {2});
      expect(h.repository.writes, 0);
      await tapVisible(tester, find.widgetWithText(FilledButton, '永久删除'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认永久删除'));
      expect(h.repository.writes, 1);
      expect(h.controller.selected, isEmpty);
      expect(find.text('服务器确认实际删除 3 条，已刷新列表。'), findsOneWidget);
      await finish(tester, h.scope);
    },
  );
  testWidgets('comment submitted request locks repeated confirmation', (
    tester,
  ) async {
    final gate = Completer<void>(), repo = fixture.CommentsRepository();
    repo.writeGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
    final h = await mountComments(tester, repository: repo);
    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('comment-2')),
        matching: find.byType(Checkbox),
      ),
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, '永久删除'));
    final button = find.widgetWithText(FilledButton, '确认永久删除');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(repo.writes, 1);
    expect(h.controller.busy, isTrue);
    final during = find.byType(AdminCommentDeletePage);
    expect(during, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '正在删除…'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '正在删除…'));
    await tester.pump();
    expect(repo.writes, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.controller.ready, isTrue);
    await finish(tester, h.scope);
  });
  testWidgets(
    'unknown comment delete clears selection and never silently repeats',
    (tester) async {
      final repo = fixture.CommentsRepository()
        ..writeError = const AdminCommunityWriteUnknown();
      final h = await mountComments(tester, repository: repo);
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('comment-2')),
          matching: find.byType(Checkbox),
        ),
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '永久删除'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认永久删除'));
      expect(h.controller.phase, AdminCommunityPhase.unknown);
      expect(h.controller.selected, isEmpty);
      expect(h.controller.actualDeleted, isNull);
      expect(repo.reads, 1);
      expect(repo.writes, 1);
      expect(find.byType(Checkbox), findsNothing);
      await tapVisible(tester, find.text('只读取当前列表'));
      expect(h.controller.phase, AdminCommunityPhase.reviewing);
      await tapVisible(tester, find.widgetWithText(FilledButton, '已核对，结束本次核对'));
      expect(h.controller.ready, isTrue);
      expect(repo.writes, 1);
      expect(h.controller.selected, isEmpty);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'scope close retires owned draft dialog and clears attached field buffers',
    (tester) async {
      final h = await mountLinks(tester, repository: normalLinks());
      await editFirst(tester);
      final name = find.byKey(const ValueKey('friend-editor-name'));
      await tester.enterText(name, 'owned temporary draft');
      final field = tester.widget<TextField>(name).controller!;
      await tapVisible(tester, find.text('移除这条草稿'));
      expect(find.byType(AlertDialog), findsOneWidget);
      final rootNavigator = Navigator.of(
        tester.element(find.byType(AdminCommunityFeature)),
      );
      expect(rootNavigator.canPop(), isFalse);
      h.scope.close();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(field.text, isEmpty);
      expect(h.controller.rows, isEmpty);
      expect(h.repository.writes, 0);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'new scope on same feature element removes old dialog and editor values',
    (tester) async {
      final h = await mountLinks(tester, repository: normalLinks());
      await editFirst(tester);
      final name = find.byKey(const ValueKey('friend-editor-name'));
      await tester.enterText(name, 'previous owner draft');
      final oldController = tester.widget<TextField>(name).controller!;
      await tapVisible(tester, find.text('移除这条草稿'));
      expect(find.byType(AlertDialog), findsOneWidget);
      final nextRepo = normalLinks()
        ..data = AdminFriendLinksSnapshot(
          items: [
            fixture.linksData().items.single.edit(
              qr: '',
              name: 'new owner fixture',
            ),
          ],
          simpleMode: false,
        );
      final next = AdminFriendLinksController(nextRepo, fixture.owner),
          nextScope = AdminCommunityScope(nextRepo.client, fixture.owner);
      addTearDown(nextScope.dispose);
      await tester.pumpWidget(root(nextScope, next, AdminCommunityKind.links));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(oldController.text, isEmpty);
      expect(find.text('previous owner draft'), findsNothing);
      expect(find.text('new owner fixture'), findsOneWidget);
      expect(h.controller.rows, isEmpty);
      expect(h.repository.writes, 0);
      expect(nextRepo.writes, 0);
      await finish(tester, nextScope);
    },
  );
  testWidgets(
    'non-admin scope cannot display a supplied populated controller',
    (tester) async {
      await viewport(tester, 390);
      final repo = normalLinks();
      final controller = AdminFriendLinksController(repo, fixture.owner);
      await controller.load();
      final scope = AdminCommunityScope(
        repo.client,
        const AdminPrincipal(memberId: 1, account: 'fixture-owner', role: 1),
      );
      addTearDown(scope.dispose);
      final reads = repo.reads;
      await tester.pumpWidget(
        root(scope, controller, AdminCommunityKind.links),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminFriendLinksPage), findsNothing);
      expect(find.text('fixture-link'), findsNothing);
      expect(controller.rows, isEmpty);
      expect(repo.reads, reads);
      expect(repo.writes, 0);
      await finish(tester, scope);
    },
  );
  for (final english in [false, true]) {
    testWidgets(
      'community screens stay reachable at320dp200% english=$english',
      (tester) async {
        final h = await mountLinks(
          tester,
          repository: normalLinks(),
          english: english,
          width: 320,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text(english ? 'Edit' : '编辑'));
        expect(find.byType(AdminFriendLinkEditorPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('friend-editor-name')),
          'updated fixture',
        );
        await tapVisible(
          tester,
          find.widgetWithText(
            FilledButton,
            english ? 'Apply to draft' : '应用到草稿',
          ),
        );
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, english ? 'Save all' : '保存全部'),
        );
        expect(find.byType(AdminFriendLinksSavePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapVisible(
          tester,
          find.widgetWithText(
            OutlinedButton,
            english ? 'Return to review' : '返回核对',
          ),
        );
        await finish(tester, h.scope);
        final comments = await mountComments(
          tester,
          english: english,
          width: 320,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tapVisible(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('comment-2')),
            matching: find.byType(Checkbox),
          ),
        );
        await tapVisible(
          tester,
          find.widgetWithText(
            FilledButton,
            english ? 'Delete permanently' : '永久删除',
          ),
        );
        expect(find.byType(AdminCommentDeletePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapVisible(
          tester,
          find.widgetWithText(OutlinedButton, english ? 'Cancel' : '取消'),
        );
        await finish(tester, comments.scope);
      },
    );
  }
  testWidgets(
    'permission loss retires leave dialog while a readonly unknown review is pending',
    (tester) async {
      final repo = normalLinks()
        ..writeError = const AdminCommunityWriteUnknown();
      final h = await mountLinks(tester, repository: repo);
      await toggleSimple(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存全部'));
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认保存全部'));
      final gate = Completer<AdminFriendLinksSnapshot>();
      repo.readGate = gate;
      final pending = h.controller.readCurrent();
      await tester.pump();
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      gate.completeError(const ApiFailure(401, 'owned test'));
      await pending;
      await tester.pumpAndSettle();
      expect(h.controller.phase, AdminCommunityPhase.permissionLost);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('fixture-link'), findsNothing);
      expect(h.controller.rows, isEmpty);
      expect(repo.writes, 1);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'setting switches, editors and comment selection expose actual target labels',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final h = await mountLinks(tester, repository: normalLinks());
        final simple = find.descendant(
          of: find.byKey(const ValueKey('friend-links-simple-mode')),
          matching: find.byType(Switch),
        );
        expect(tester.getSemantics(simple).label, contains('简洁模式'));
        expect(
          tester.getSemantics(find.byType(Switch).last).label,
          contains('fixture-link'),
        );
        expect(
          tester.getSemantics(find.text('编辑')).label,
          contains('fixture-link'),
        );
        await finish(tester, h.scope);
        final comments = await mountComments(tester);
        expect(
          tester.getSemantics(find.text('全部状态').first).label,
          contains('评论状态'),
        );
        expect(
          tester.getSemantics(find.text('全部类型').first).label,
          contains('评论类型'),
        );
        final choice = find.descendant(
          of: find.byKey(const ValueKey('comment-2')),
          matching: find.byType(Checkbox),
        );
        await tester.scrollUntilVisible(
          choice,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.getSemantics(choice).label, contains('选择评论 ID 2'));
        await finish(tester, comments.scope);
      } finally {
        handle.dispose();
      }
    },
  );
}
