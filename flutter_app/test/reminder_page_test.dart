import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/profile/reminder_page.dart';
import 'reminder_controller_test.dart' as fixture;

Future<void> open(
  WidgetTester tester,
  fixture.Repo repo, {
  bool english = false,
  Future<void> Function()? edit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReminderPage(
        repository: repo,
        settings: repo.current,
        english: english,
        onEditEmail: edit ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reminder semantics editable bounds exclude surrounding switches and help text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final r = fixture.Repo();
        await open(tester, r);
        await tester.ensureVisible(find.byType(TextFormField));
        await tester.pumpAndSettle();
        final field = tester.getSemantics(find.byType(TextFormField));
        expect(field.rect.height, lessThan(150));
        expect(field.rect.width, greaterThan(100));
        await tester.tapAt(tester.getCenter(find.byType(TextFormField)));
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(r.writes, 0);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'save reads actual receipt and settings; no mail sent on entry or ordinary save',
    (tester) async {
      final r = fixture.Repo();
      await open(tester, r);
      expect(r.mails, 0);
      expect(r.writes, 0);
      await click(tester, find.byTooltip('增加提前天数'));
      await click(tester, find.text('保存提醒设置'));
      expect(r.current.preferences.days, 2);
      expect(r.writes, 1);
      expect(r.mails, 0);
      expect(find.text('实际提醒设置已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'test mail requires confirmation; unavailable scheduling does not disable explicit test; generic unknown and limiter',
    (tester) async {
      final r = fixture.Repo()
        ..current = fixture.settings(available: false)
        ..mailLose = true;
      await open(tester, r);
      await click(tester, find.text('发送测试邮件'));
      expect(r.mails, 0);
      expect(find.text('发送一封测试邮件？'), findsOneWidget);
      await click(tester, find.text('取消'));
      expect(r.mails, 0);
      await click(tester, find.text('发送测试邮件'));
      await click(tester, find.text('确认发送一封'));
      expect(r.mails, 1);
      expect(find.text('发送结果未知，邮件可能已经发出。不会自动重试。'), findsOneWidget);
      r.mailLose = false;
      r.mailStatus = 429;
      await click(tester, find.text('发送测试邮件'));
      expect(r.mails, 1);
      await click(tester, find.text('确认发送一封'));
      expect(r.mails, 2);
      expect(find.text('发送过于频繁，请稍后再试。'), findsOneWidget);
      expect(find.textContaining('SMTP secret'), findsNothing);
    },
  );
  testWidgets(
    'changed email is reloaded through real edit callback before further actions',
    (tester) async {
      final r = fixture.Repo();
      var edits = 0;
      await open(
        tester,
        r,
        edit: () async {
          edits++;
          r.current = fixture.settings(email: 'new@example.invalid');
        },
      );
      await click(tester, find.text('修改邮箱'));
      expect(edits, 1);
      expect(find.text('接收邮箱: new@example.invalid'), findsOneWidget);
      expect(r.writes, 0);
      expect(r.mails, 0);
    },
  );
  testWidgets(
    'unknown save has read-only verification and never repeats update',
    (tester) async {
      final r = fixture.Repo()..lose = true;
      await open(tester, r);
      await click(tester, find.byTooltip('增加提前天数'));
      await click(tester, find.text('保存提醒设置'));
      expect(find.text('保存结果未知，不会自动重发。'), findsOneWidget);
      expect(r.writes, 1);
      await click(tester, find.text('只读核对保存结果'));
      expect(r.writes, 1);
      expect(find.text('实际提醒设置已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'English 320dp 200 percent keyboard and native confirmation stay usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final r = fixture.Repo();
      await open(tester, r, english: true);
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), '08:15');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await click(tester, find.text('Save reminder preferences'));
      expect(r.current.preferences.sendTime, '08:15');
      await click(tester, find.text('Send test email'));
      expect(r.mails, 0);
      await click(tester, find.text('Send one email'));
      expect(r.mails, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
