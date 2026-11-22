import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_registration_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_registration_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  {
    'key': 'invite_code_enabled',
    'value': '0',
    'description': '',
    'update_time': '',
  },
  {
    'key': 'invite_code',
    'value': ' fixture invite ',
    'description': '',
    'update_time': '',
  },
]);

class RegistrationRepository extends AdminSettingsRepository {
  RegistrationRepository() : super(BookstarkClient('https://example.invalid'));
  int puts = 0;
  Map<String, String>? patch;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => snapshot();
  @override
  Future<void> saveRegistration(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminRegistrationChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }
}

void main() {
  test(
    'registration toggle sends only flag and does not trim or clear code',
    () async {
      final repo = RegistrationRepository();
      final c = AdminRegistrationController(repo, owner);
      await c.load();
      c.edit('invite_code_enabled', '1');
      await c.save();
      expect(repo.patch, {'invite_code_enabled': '1'});
      c.edit('invite_code', ' new fixture invite ');
      await c.save();
      expect(repo.patch, {'invite_code': ' new fixture invite '});
      c.dispose();
    },
  );
  test(
    'empty enabled code blocks save and clear confirmation is revision bound',
    () async {
      final repo = RegistrationRepository();
      final c = AdminRegistrationController(repo, owner);
      await c.load();
      c.edit('invite_code', '');
      final revision = c.revision;
      c.edit('invite_code_enabled', '1');
      await c.save(confirmedClearRevision: revision);
      expect(repo.puts, 0);
      await c.save(confirmedClearRevision: c.revision);
      expect(repo.puts, 0);
      expect(c.message, contains('所有新注册'));
      c.edit('invite_code_enabled', '0');
      await c.save(confirmedClearRevision: c.revision);
      expect(repo.patch, {'invite_code': ''});
      c.dispose();
    },
  );
  testWidgets('registration 320dp200% masks code and explains auto approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminRegistrationController(RegistrationRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminRegistrationPage(
          controller: c,
          onReturn: () {},
          onSignaling: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('invite_code'));
    expect(tester.widget<TextField>(code).obscureText, isTrue);
    final influence = find.textContaining('会自动通过审批');
    await tester.scrollUntilVisible(
      influence,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(influence, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
