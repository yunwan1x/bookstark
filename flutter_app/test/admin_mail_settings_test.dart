import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_mail_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_mail_settings_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final entry in {
    'mail_enabled': '1',
    'task_email_reminder_enabled': '0',
    'password_reset_enabled': '1',
    'mail_public_url': 'https://example.invalid',
    'password_reset_expiry_minutes': '30',
    'smtp_host': 'smtp.example.invalid',
    'mail_from_address': 'sender@example.invalid',
  }.entries)
    {
      'key': entry.key,
      'value': entry.value,
      'description': '',
      'update_time': '',
    },
]);
const status = AdminMailStatus(
  configured: true,
  enabled: true,
  taskReminderEnabled: false,
  passwordResetEnabled: true,
  passwordResetReady: true,
  pending: 3,
  failed: 2,
  sent: 7,
  lastSent: null,
  hasLastError: false,
);

class MailRepository extends AdminSettingsRepository {
  MailRepository() : super(BookstarkClient('https://example.invalid'));
  int puts = 0;
  int sends = 0;
  int statusReads = 0;
  bool? testedDirty;
  String? recipient;
  Map<String, String>? patch;
  Object? statusError;
  Completer<AdminMailTestOutcome>? sendBarrier;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => snapshot();
  @override
  Future<void> saveMail(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminMailChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }

  @override
  Future<AdminMailStatus> readMailStatus(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    statusReads++;
    if (statusError != null) throw statusError!;
    return status;
  }

  @override
  Future<AdminMailTestOutcome> sendMailTest(
    AdminPrincipal owner,
    String recipient, {
    bool hasUnsavedSettings = false,
    Future<void>? abortTrigger,
  }) async {
    sends++;
    testedDirty = hasUnsavedSettings;
    this.recipient = recipient;
    return sendBarrier?.future ??
        const AdminMailTestOutcome(AdminMailTestState.sent);
  }
}

void main() {
  test(
    'status refresh does not replace unsaved form or perform writes',
    () async {
      final repo = MailRepository();
      final c = AdminMailSettingsController(repo, owner);
      await c.load();
      c.edit('mail_public_url', 'https://new.example.invalid');
      await c.refreshStatus();
      expect(c.draft['mail_public_url'], 'https://new.example.invalid');
      expect(c.status!.pending, 3);
      expect(c.statusReadAt, isNotNull);
      expect(repo.puts, 0);
      expect(repo.sends, 0);
      repo.statusError = const FormatException('fixture');
      await c.refreshStatus();
      expect(c.status, isNull);
      expect(c.statusReadAt, isNull);
      c.dispose();
    },
  );
  test(
    'save performs no test and only submits mail page dirty fields',
    () async {
      final repo = MailRepository();
      final c = AdminMailSettingsController(repo, owner);
      await c.load();
      c.edit('password_reset_expiry_minutes', '45');
      await c.save();
      expect(repo.patch, {'password_reset_expiry_minutes': '45'});
      expect(repo.sends, 0);
      c.dispose();
    },
  );
  test(
    'test uses saved configuration and freezes competing operations',
    () async {
      final repo = MailRepository()
        ..sendBarrier = Completer<AdminMailTestOutcome>();
      final c = AdminMailSettingsController(repo, owner);
      await c.load();
      c.edit('mail_public_url', 'https://new.example.invalid');
      final sending = c.sendTest('receiver@example.invalid');
      await c.save();
      await c.refreshStatus();
      expect(repo.puts, 0);
      expect(repo.statusReads, 0);
      expect(repo.testedDirty, isTrue);
      repo.sendBarrier!.complete(
        const AdminMailTestOutcome(AdminMailTestState.unknown),
      );
      await sending;
      expect(repo.sends, 1);
      expect(c.testOutcome!.state, AdminMailTestState.unknown);
      expect(c.dirty, isTrue);
      c.dispose();
    },
  );
  test('dependency errors never silently change switches or write', () async {
    final repo = MailRepository();
    final c = AdminMailSettingsController(repo, owner);
    await c.load();
    c.edit('mail_enabled', '0');
    c.edit('task_email_reminder_enabled', '1');
    await c.save();
    expect(repo.puts, 0);
    expect(c.draft['task_email_reminder_enabled'], '1');
    c.dispose();
  });
  test('dispose rejects delayed test result', () async {
    final repo = MailRepository()
      ..sendBarrier = Completer<AdminMailTestOutcome>();
    final c = AdminMailSettingsController(repo, owner);
    await c.load();
    final sending = c.sendTest('receiver@example.invalid');
    c.dispose();
    repo.sendBarrier!.complete(
      const AdminMailTestOutcome(AdminMailTestState.sent),
    );
    await sending;
    expect(c.testOutcome, isNull);
    expect(c.draft, isEmpty);
  });
  testWidgets('320dp200% mail form shows absent status instead of fake zero', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MailRepository();
    final c = AdminMailSettingsController(repo, owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminMailSettingsPage(
          controller: c,
          onReturn: () {},
          onSmtp: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final absent = find.text('尚无当前状态，请刷新读取。');
    await tester.scrollUntilVisible(
      absent,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(absent, findsOneWidget);
    expect(find.text('待发送：0'), findsNothing);
    expect(repo.sends, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
