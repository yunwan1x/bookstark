import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_smtp_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_smtp_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final entry in {
    'smtp_host': 'smtp.example.invalid',
    'smtp_port': '587',
    'smtp_encryption': 'starttls',
    'smtp_username': 'fixture',
    'smtp_password': '',
    'mail_timeout_seconds': '10',
    'mail_from_name': 'Fixture',
    'mail_from_address': 'sender@example.invalid',
  }.entries)
    {
      'key': entry.key,
      'value': entry.value,
      'description': '',
      'update_time': '',
    },
]);

class SmtpRepository extends AdminSettingsRepository {
  SmtpRepository() : super(BookstarkClient('https://example.invalid'));
  int puts = 0;
  Map<String, String>? patch;
  Object? readError;
  Object? saveError;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    if (readError != null) throw readError!;
    return snapshot();
  }

  @override
  Future<void> saveSmtp(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminSmtpChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
    if (saveError != null) throw saveError!;
  }
}

void main() {
  test(
    'SMTP blank password retains existing and only changed fields save',
    () async {
      final repo = SmtpRepository();
      final c = AdminSmtpSettingsController(repo, owner);
      await c.load();
      c.edit('smtp_host', 'new.example.invalid');
      await c.save();
      expect(repo.patch, {'smtp_host': 'new.example.invalid'});
      expect(c.draft['smtp_password'], '');
      c.dispose();
    },
  );
  test(
    'SMTP secret retains exact whitespace and clears after known receipt',
    () async {
      final repo = SmtpRepository();
      final c = AdminSmtpSettingsController(repo, owner);
      await c.load();
      c.edit('smtp_password', ' fixture password ');
      repo.readError = const FormatException('fixture');
      await c.save();
      expect(repo.patch!['smtp_password'], ' fixture password ');
      expect(c.draft['smtp_password'], '');
      expect(c.phase, AdminSmtpPhase.committedNeedsRead);
      repo.readError = null;
      await c.readCurrent();
      expect(repo.puts, 1);
      c.dispose();
    },
  );
  test('SMTP validation uses UTF8 bytes and port boundaries', () async {
    final repo = SmtpRepository();
    final c = AdminSmtpSettingsController(repo, owner);
    await c.load();
    c.edit('mail_from_name', List.filled(34, '中').join());
    await c.save();
    expect(repo.puts, 0);
    c.edit('mail_from_name', 'Valid');
    c.edit('smtp_port', '65536');
    await c.save();
    expect(repo.puts, 0);
    c.dispose();
  });
  test(
    'SMTP unknown save only reads and never claims password verification',
    () async {
      final repo = SmtpRepository()..saveError = TimeoutException('fixture');
      final c = AdminSmtpSettingsController(repo, owner);
      await c.load();
      c.edit('smtp_password', 'new-fixture');
      await c.save();
      await c.readCurrent();
      expect(c.message, contains('无法回读'));
      c.adoptReviewedCurrent();
      expect(c.draft['smtp_password'], '');
      expect(repo.puts, 1);
      c.dispose();
    },
  );
  testWidgets('SMTP 320dp200% keeps password hidden and save accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminSmtpSettingsController(SmtpRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminSmtpSettingsPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final password = find.byKey(const ValueKey('smtp_password'));
    await tester.scrollUntilVisible(
      password,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(find.text('保存连接配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.draft, isEmpty);
  });
}
