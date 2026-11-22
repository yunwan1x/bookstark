import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/credentials/webdav_password_page.dart';
import 'webdav_password_controller_test.dart' as fixture;
import 'webdav_password_repository_test.dart' as values;
import 'api_tokens_page_test.dart' show click;

Future<void> open(
  WidgetTester tester,
  fixture.Repo repo, {
  bool english = false,
  Future<void> Function(String)? copy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WebdavPasswordPage(repository: repo, english: english, copy: copy),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'generate requires confirmation, verifies once, hides secret and clears display on close',
    (tester) async {
      final r = fixture.Repo();
      final copied = <String>[];
      await open(
        tester,
        r,
        copy: (v) async {
          copied.add(v);
        },
      );
      await click(tester, find.text('生成新的应用密码'));
      await click(tester, find.text('取消'));
      expect(r.resets, 0);
      await click(tester, find.text('生成新的应用密码'));
      await click(tester, find.text('确认生成新密码'));
      expect([r.resets, r.verifies], [1, 1]);
      expect(find.text(values.generated), findsNothing);
      await click(tester, find.text('显示本次应用密码'));
      expect(find.text(values.generated), findsOneWidget);
      await click(tester, find.text('复制本次应用密码'));
      expect(copied, [values.generated]);
      await click(tester, find.text('关闭并清除本次显示'));
      expect(find.text(values.generated), findsNothing);
      await click(tester, find.text('撤销应用密码'));
      await click(tester, find.text('取消'));
      expect(r.revokes, 0);
      await click(tester, find.text('撤销应用密码'));
      await click(tester, find.text('确认撤销'));
      expect(r.revokes, 1);
      expect(find.text('撤销回执与实际无密码状态已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown custom reset clears input widgets and only explicit probe verifies preserved raw spaces',
    (tester) async {
      final r = fixture.Repo()..loseReset = true;
      await open(tester, r);
      await click(tester, find.text('设置自定义应用密码'));
      await tester.enterText(find.byType(TextFormField).at(0), ' custom 密码 ');
      await tester.enterText(find.byType(TextFormField).at(1), ' custom 密码 ');
      await click(tester, find.text('确认替换应用密码'));
      expect(r.password, ' custom 密码 ');
      expect([r.resets, r.verifies], [1, 0]);
      expect(find.byType(TextFormField), findsNothing);
      await click(tester, find.text('只读刷新状态'));
      expect([r.resets, r.verifies], [1, 0]);
      await click(tester, find.text('核对本次新凭据'));
      expect([r.resets, r.verifies], [1, 1]);
      expect(find.text(' custom 密码 '), findsNothing);
      await click(tester, find.text('显示本次应用密码'));
      expect(find.text(' custom 密码 '), findsOneWidget);
      await click(tester, find.text('关闭并清除本次显示'));
      expect(find.text(' custom 密码 '), findsNothing);
    },
  );
  testWidgets(
    'unknown random reset cannot recover secret or silently repeat operation',
    (tester) async {
      final r = fixture.Repo()..loseReset = true;
      await open(tester, r);
      await click(tester, find.text('生成新的应用密码'));
      await click(tester, find.text('确认生成新密码'));
      await click(tester, find.text('只读刷新状态'));
      expect(find.text('核对本次新凭据'), findsNothing);
      expect(find.text(values.generated), findsNothing);
      expect([r.resets, r.verifies], [1, 0]);
      await click(tester, find.text('清除本次记录并继续'));
      await click(tester, find.text('理解并继续管理'));
      expect(r.resets, 1);
    },
  );
  testWidgets(
    'English narrow 200 percent custom input, receipt and revoke remain scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final r = fixture.Repo();
      await open(tester, r, english: true, copy: (_) async {});
      await click(tester, find.text('Set a custom app password'));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        ' custom password ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        ' custom password ',
      );
      await click(tester, find.text('Replace app password'));
      await click(tester, find.text('Show this app password'));
      expect(find.text(' custom password '), findsOneWidget);
      await click(tester, find.text('Close and clear this display'));
      await click(tester, find.text('Revoke app password'));
      await click(tester, find.text('Confirm revocation'));
      expect(r.revokes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
