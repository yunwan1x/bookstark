import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_member_password_page.dart';
import 'package:bookstark_flutter/features/admin/admin_member_role_page.dart';
import 'package:bookstark_flutter/features/admin/admin_members_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_members_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_members_models.dart';
import 'package:bookstark_flutter/features/admin/admin_members_page.dart';
import 'package:bookstark_flutter/features/admin/admin_members_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_members_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_members_controller_test.dart' as fixture;

Widget root(
  AdminMembersScope scope,
  AdminMembersController controller, {
  bool english = false,
  double scale = 1,
}) => MaterialApp(
  theme: bookstarkTheme(),
  locale: Locale(english ? 'en' : 'zh'),
  supportedLocales: const [Locale('zh'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: AdminMembersFeature(
    key: const ValueKey('member-feature-test'),
    scope: scope,
    controller: controller,
    english: english,
    onReturn: () {},
  ),
);
Future<
  ({
    fixture.MemberRepository repository,
    AdminMembersController controller,
    AdminMembersScope scope,
  })
>
mount(
  WidgetTester tester, {
  fixture.MemberRepository? repository,
  bool english = false,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final data = repository ?? fixture.MemberRepository();
  data.client.restoreSession({
    'token': 'owned-widget-session',
    'csrf_token': 'owned-widget-csrf',
  });
  final controller = AdminMembersController(data, fixture.owner);
  final scope = AdminMembersScope(data.client, fixture.owner);
  addTearDown(scope.dispose);
  await tester.pumpWidget(
    root(scope, controller, english: english, scale: scale),
  );
  await tester.pumpAndSettle();
  return (repository: data, controller: controller, scope: scope);
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

Future<void> chooseMember(WidgetTester tester, [int id = 2]) async =>
    tapVisible(tester, find.byKey(ValueKey('member-card-$id')));
Finder dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);
Future<void> finish(WidgetTester tester, AdminMembersScope scope) async {
  await tester.pumpWidget(const SizedBox.shrink());
  scope.dispose();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'password validation disappearing preserves platform input focus',
    (tester) async {
      final h = await mount(
        tester,
        repository: fixture.MemberRepository()
          ..data = fixture.initialPage(status: AdminMemberStatus.approved),
      );
      await chooseMember(tester);
      await tapVisible(tester, find.text('重置密码'));
      final first = find.byKey(const ValueKey('member-new-password'));
      final second = find.byKey(const ValueKey('member-confirm-password'));
      await tester.enterText(first, 'short');
      await tester.enterText(second, 'short');
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认重置'));
      expect(find.text('密码必须为 6–72 个 UTF-8 字节。'), findsOneWidget);
      await tester.showKeyboard(first);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'fixture-six',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('密码必须为 6–72 个 UTF-8 字节。'), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'fixture-six-more',
          selection: TextSelection.collapsed(offset: 16),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(first).controller!.text,
        'fixture-six-more',
      );
      expect(tester.widget<TextField>(second).controller!.text, 'short');
      expect(h.repository.writeAttempts, 0);
      await finish(tester, h.scope);
    },
  );
  testWidgets('320dp English pagination keeps complete words on one line', (
    tester,
  ) async {
    final h = await mount(tester, english: true, width: 320);
    expect(tester.getSize(find.text('Previous')).height, lessThanOrEqualTo(24));
    expect(tester.getSize(find.text('Next')).height, lessThanOrEqualTo(24));
    final rect = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Previous'),
    );
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.height, greaterThanOrEqualTo(48));
    await finish(tester, h.scope);
  });
  testWidgets('member approval chooses target and cancel sends nothing', (
    tester,
  ) async {
    final h = await mount(tester);
    await chooseMember(tester);
    await tapVisible(tester, find.text('审批处理'));
    await tester.tap(find.widgetWithText(FilledButton, '审批通过'));
    await tester.pumpAndSettle();
    expect(find.text('member-fixture (ID 2)'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, '取消'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.repository.writeAttempts, 0);
    expect(h.controller.selected!.status, AdminMemberStatus.pending);
    await finish(tester, h.scope);
  });
  testWidgets('confirmed approval reads current state and updates details', (
    tester,
  ) async {
    final h = await mount(tester);
    await chooseMember(tester);
    await tapVisible(tester, find.text('审批处理'));
    await tester.tap(find.widgetWithText(FilledButton, '审批通过'));
    await tester.pumpAndSettle();
    await tester.tap(dialogButton('确认通过'));
    await tester.pumpAndSettle();
    expect(h.repository.submittedWrites, 1);
    expect(h.controller.selected!.status, AdminMemberStatus.approved);
    expect(find.byType(AdminMemberDetailPage), findsOneWidget);
    expect(find.text('已通过'), findsOneWidget);
    await finish(tester, h.scope);
  });
  testWidgets('role selection needs explicit target confirmation', (
    tester,
  ) async {
    final h = await mount(tester);
    await chooseMember(tester);
    await tapVisible(tester, find.text('修改角色'));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('member-role-option-0')),
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, '下一步'));
    expect(h.repository.writeAttempts, 0);
    await tester.tap(dialogButton('确认修改'));
    await tester.pumpAndSettle();
    expect(h.repository.submittedWrites, 1);
    expect(h.controller.selected!.role, AdminMemberRole.administrator);
    expect(h.controller.selected!.status, AdminMemberStatus.pending);
    await finish(tester, h.scope);
  });
  testWidgets('own role is visibly disabled and never invokes a write', (
    tester,
  ) async {
    final h = await mount(tester);
    await chooseMember(tester, 1);
    await tapVisible(tester, find.text('修改角色'));
    expect(find.text('不能修改自己的角色。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<RadioListTile<AdminMemberRole>>(
            find.byType(RadioListTile<AdminMemberRole>),
          )
          .every((radio) => radio.enabled == false),
      isTrue,
    );
    expect(h.repository.writeAttempts, 0);
    await finish(tester, h.scope);
  });
  testWidgets(
    'unknown reset clears both attached password controllers and never replays',
    (tester) async {
      final repository = fixture.MemberRepository()
        ..data = fixture.initialPage(status: AdminMemberStatus.approved)
        ..writeError = const AdminMemberWriteUnknown();
      final h = await mount(tester, repository: repository);
      await chooseMember(tester);
      await tapVisible(tester, find.text('重置密码'));
      final first = find.byKey(const ValueKey('member-new-password'));
      final second = find.byKey(const ValueKey('member-confirm-password'));
      await tester.enterText(first, ' owned fixture ');
      await tester.enterText(second, ' owned fixture ');
      final firstController = tester.widget<TextField>(first).controller!;
      final secondController = tester.widget<TextField>(second).controller!;
      expect(tester.widget<TextField>(first).obscureText, isTrue);
      expect(tester.widget<TextField>(second).obscureText, isTrue);
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认重置'));
      await tester.tap(dialogButton('确认重置'));
      await tester.pumpAndSettle();
      expect(h.controller.phase, AdminMembersPhase.unknown);
      expect(firstController.text, isEmpty);
      expect(secondController.text, isEmpty);
      expect(find.byType(TextField), findsNothing);
      await tapVisible(tester, find.widgetWithText(OutlinedButton, '只读取当前列表'));
      expect(h.controller.phase, AdminMembersPhase.reviewingUnknown);
      expect(h.controller.notice, AdminMembersNotice.unknownCurrent);
      await tapVisible(tester, find.widgetWithText(FilledButton, '已核对，返回用户详情'));
      expect(h.controller.phase, AdminMembersPhase.ready);
      expect(repository.submittedWrites, 1);
      expect(find.byType(AdminMemberDetailPage), findsOneWidget);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'scope close removes owned confirmation and clears all password inputs',
    (tester) async {
      final h = await mount(
        tester,
        repository: fixture.MemberRepository()
          ..data = fixture.initialPage(status: AdminMemberStatus.approved),
      );
      await chooseMember(tester);
      await tapVisible(tester, find.text('重置密码'));
      final first = find.byKey(const ValueKey('member-new-password'));
      final second = find.byKey(const ValueKey('member-confirm-password'));
      await tester.enterText(first, 'owned-fixture-password');
      await tester.enterText(second, 'owned-fixture-password');
      final firstController = tester.widget<TextField>(first).controller!;
      final secondController = tester.widget<TextField>(second).controller!;
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认重置'));
      expect(find.byType(AlertDialog), findsOneWidget);
      final rootNavigator = Navigator.of(
        tester.element(find.byType(AdminMembersFeature)),
      );
      expect(
        rootNavigator.canPop(),
        isFalse,
        reason: 'The confirmation belongs to the inner navigator',
      );
      h.scope.close();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(firstController.text, isEmpty);
      expect(secondController.text, isEmpty);
      expect(h.controller.page, isNull);
      expect(h.controller.selected, isNull);
      expect(h.repository.submittedWrites, 0);
      expect(tester.takeException(), isNull);
      await finish(tester, h.scope);
    },
  );
  testWidgets(
    'new scope retires old owned dialogs even in the same feature element',
    (tester) async {
      final old = await mount(
        tester,
        repository: fixture.MemberRepository()
          ..data = fixture.initialPage(status: AdminMemberStatus.approved),
      );
      await chooseMember(tester);
      await tapVisible(tester, find.text('重置密码'));
      await tester.enterText(
        find.byKey(const ValueKey('member-new-password')),
        'owned-fixture-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('member-confirm-password')),
        'owned-fixture-password',
      );
      final secret = tester
          .widget<TextField>(find.byKey(const ValueKey('member-new-password')))
          .controller!;
      await tapVisible(tester, find.widgetWithText(FilledButton, '确认重置'));
      expect(find.byType(AlertDialog), findsOneWidget);
      final repository = fixture.MemberRepository();
      repository.client.restoreSession({
        'token': 'second-widget-session',
        'csrf_token': 'second-widget-csrf',
      });
      final controller = AdminMembersController(repository, fixture.owner);
      final scope = AdminMembersScope(repository.client, fixture.owner);
      addTearDown(scope.dispose);
      await tester.pumpWidget(root(scope, controller));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AdminMembersPage), findsOneWidget);
      expect(find.byType(AdminMemberPasswordPage), findsNothing);
      expect(secret.text, isEmpty);
      expect(old.controller.page, isNull);
      expect(old.repository.submittedWrites, 0);
      expect(tester.takeException(), isNull);
      old.scope.dispose();
      await finish(tester, scope);
    },
  );
  testWidgets(
    'non-admin scope cannot mount even a supplied populated controller',
    (tester) async {
      final repository = fixture.MemberRepository();
      repository.client.restoreSession({'token': 'normal-widget-session'});
      const normal = AdminPrincipal(
        memberId: 2,
        account: 'normal-fixture',
        role: 1,
      );
      final controller = AdminMembersController(repository, normal);
      final scope = AdminMembersScope(repository.client, normal);
      addTearDown(scope.dispose);
      await tester.pumpWidget(root(scope, controller));
      await tester.pumpAndSettle();
      expect(find.byType(AdminMembersPage), findsNothing);
      expect(repository.readCalls, 0);
      expect(scope.closed, isTrue);
      expect(controller.page, isNull);
      await finish(tester, scope);
    },
  );
  for (final english in [false, true]) {
    testWidgets('all member screens 320dp200% english=$english', (
      tester,
    ) async {
      final repository = fixture.MemberRepository()
        ..data = fixture.initialPage(status: AdminMemberStatus.approved);
      final h = await mount(
        tester,
        repository: repository,
        english: english,
        width: 320,
        scale: 2,
      );
      await chooseMember(tester);
      await tapVisible(tester, find.text(english ? 'Change role' : '修改角色'));
      expect(find.byType(AdminMemberRolePage), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('member-role-option-0')),
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, english ? 'Next' : '下一步'),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, english ? 'Cancel' : '取消'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(english ? 'Back' : '返回'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text(english ? 'Reset password' : '重置密码'));
      final first = find.byKey(const ValueKey('member-new-password'));
      await tester.scrollUntilVisible(
        first.hitTestable(),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(first, 'owned-fixture-password');
      final second = find.byKey(const ValueKey('member-confirm-password'));
      await tester.scrollUntilVisible(
        second.hitTestable(),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(second, 'owned-fixture-password');
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, english ? 'Confirm reset' : '确认重置'),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, english ? 'Cancel' : '取消'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.submittedWrites, 0);
      expect(tester.takeException(), isNull);
      await finish(tester, h.scope);
    });
  }
}
