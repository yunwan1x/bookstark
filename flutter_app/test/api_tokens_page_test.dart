import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/credentials/api_tokens_page.dart';
import 'api_tokens_controller_test.dart' as fixture;
import 'api_tokens_repository_test.dart' as tokens;

Future<void> click(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  fixture.Repo repo, {
  bool english = false,
  Future<void> Function(String)? copy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ApiTokensPage(repository: repo, english: english, copySecret: copy),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'ordinary refresh and cancelled name dialog never create; one-time receipt is hidden until requested and cleared on close',
    (tester) async {
      final r = fixture.Repo();
      final copied = <String>[];
      await open(
        tester,
        r,
        copy: (value) async {
          copied.add(value);
        },
      );
      expect(r.creates, 0);
      await click(tester, find.text('创建令牌'));
      await click(tester, find.text('取消'));
      expect(r.creates, 0);
      await click(tester, find.text('创建令牌'));
      await tester.enterText(find.byType(TextFormField), '浏览器收藏');
      await click(tester, find.text('创建'));
      expect(r.creates, 1);
      expect(find.text('令牌已创建'), findsOneWidget);
      expect(find.text(tokens.secret), findsNothing);
      await click(tester, find.text('显示本次令牌'));
      expect(find.text(tokens.secret), findsOneWidget);
      await click(tester, find.text('复制本次令牌'));
      expect(copied, [tokens.secret]);
      await click(tester, find.text('关闭并清除本次显示'));
      expect(find.text(tokens.secret), findsNothing);
      expect(find.text('浏览器收藏'), findsOneWidget);
      expect(r.creates, 1);
    },
  );
  testWidgets(
    'revocation requires actual record confirmation and verified readback',
    (tester) async {
      final r = fixture.Repo();
      await r.create('reader');
      await open(tester, r);
      await click(tester, find.text('撤销'));
      expect(r.deletes, 0);
      await click(tester, find.text('取消'));
      expect(r.deletes, 0);
      await click(tester, find.text('撤销'));
      await click(tester, find.text('撤销令牌'));
      expect(r.deletes, 1);
      expect(find.text('撤销回执和实际列表已核对。'), findsOneWidget);
      expect(find.text('尚无API令牌。'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown creation refresh reads masks only and another create requires explicit acknowledgement',
    (tester) async {
      final r = fixture.Repo()..loseCreate = true;
      await open(tester, r);
      await click(tester, find.text('创建令牌'));
      await tester.enterText(find.byType(TextFormField), 'uncertain');
      await click(tester, find.text('创建'));
      expect(r.creates, 1);
      expect(find.text(tokens.secret), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建令牌'))
            .onPressed,
        isNull,
      );
      await click(tester, find.text('只读刷新核对记录'));
      expect(r.creates, 1);
      expect(find.text('uncertain'), findsOneWidget);
      await click(tester, find.text('核对后继续管理'));
      await click(tester, find.text('理解并继续管理'));
      expect(r.creates, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建令牌'))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'English narrow200 percent secret and confirmation dialogs stay scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final r = fixture.Repo();
      await open(tester, r, english: true, copy: (_) async {});
      await click(tester, find.text('Create token'));
      await tester.enterText(find.byType(TextFormField), 'reader');
      await click(tester, find.text('Create'));
      expect(find.text('Token created'), findsOneWidget);
      await click(tester, find.text('Show this token'));
      expect(find.text(tokens.secret), findsOneWidget);
      await click(tester, find.text('Close and clear this display'));
      expect(find.text(tokens.secret), findsNothing);
      await click(tester, find.text('Revoke'));
      await click(tester, find.text('Revoke token'));
      expect(r.deletes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
