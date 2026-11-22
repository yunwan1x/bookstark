import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/profile/account_security_page.dart';
import 'account_security_controller_test.dart' as fixture;
import 'profile_edit_controller_test.dart' as profile;

Future<void> open(
  WidgetTester tester,
  fixture.Repo repo, {
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AccountSecurityPage(
        member: profile.member(),
        repository: repo,
        english: english,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  for (var i = 0; i < 3; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(fields.at(i), i == 0 ? 'current-pass' : ' raw new ');
  }
}

Future<void> click(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder submit(bool english) => find.widgetWithText(
  FilledButton,
  english ? 'Change login password' : '修改登录密码',
);
void assertEmpty(WidgetTester tester) {
  for (final field in tester.widgetList<TextFormField>(
    find.byType(TextFormField),
  )) {
    expect(field.controller!.text, isEmpty);
  }
}

void main() {
  testWidgets(
    'submission immediately clears all passwords while real write remains pending',
    (tester) async {
      final repo = fixture.Repo()..wait = Completer<void>();
      await open(tester, repo);
      await fill(tester);
      await tester.ensureVisible(submit(false));
      await tester.pumpAndSettle();
      await tester.tap(submit(false));
      await tester.pump();
      assertEmpty(tester);
      expect(repo.writes, 1);
      expect(repo.verifies, 0);
      expect(tester.widget<FilledButton>(submit(false)).onPressed, isNull);
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(find.text('登录密码修改已核对，当前会话已保存。'), findsOneWidget);
      expect(repo.password, ' raw new ');
      expect([repo.writes, repo.verifies, repo.stores], [1, 1, 1]);
      assertEmpty(tester);
    },
  );
  testWidgets(
    'unknown applied change requires explicit credential verification without another mutation',
    (tester) async {
      final repo = fixture.Repo()..lose = true;
      await open(tester, repo);
      await fill(tester);
      await click(tester, submit(false));
      assertEmpty(tester);
      expect(repo.verifies, 0);
      expect(tester.widget<FilledButton>(submit(false)).onPressed, isNull);
      await click(tester, find.text('验证本次新凭据'));
      expect([repo.writes, repo.verifies, repo.stores], [1, 1, 1]);
      expect(find.text('新凭据已验证，会话已保存；上次修改回执仍未知。'), findsOneWidget);
    },
  );
  testWidgets(
    'session storage failure exposes only storage retry and retains no input',
    (tester) async {
      final repo = fixture.Repo()..storeFails = true;
      await open(tester, repo);
      await fill(tester);
      await click(tester, submit(false));
      expect(find.text('新凭据已验证，但当前会话尚未保存。'), findsOneWidget);
      assertEmpty(tester);
      repo.storeFails = false;
      await click(tester, find.text('仅重试保存会话'));
      expect([repo.writes, repo.verifies, repo.stores], [1, 1, 2]);
    },
  );
  testWidgets(
    'English narrow large text and keyboard keep fields and leave confirmation usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = fixture.Repo();
      await open(tester, repo, english: true);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, 'current-pass');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave account security?'), findsOneWidget);
      await click(tester, find.text('Cancel'));
      expect(repo.writes, 0);
      await fill(tester);
      await click(tester, submit(true));
      expect(
        find.text(
          'The password change was verified and this session is saved.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      assertEmpty(tester);
    },
  );
}
