import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/reminder_repository.dart';
import 'package:bookstark_flutter/core/reminder_controller.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';

void check(bool value, String message) {
  if (!value) {
    throw StateError(message);
  }
}

Future<int> mailCount(String provider) async {
  final transport = HttpClient();
  try {
    final request = await transport.getUrl(
      Uri.parse(provider).replace(path: '/reminder-mail-count'),
    );
    final response = await request.close();
    final row = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    return row['count'] as int;
  } finally {
    transport.close(force: true);
  }
}

Future<void> runReminderContract(
  BookstarkClient client,
  int memberId, {
  required String smtpHost,
  required int smtpPort,
  required String provider,
}) async {
  final repo = RemoteReminderRepository(client, memberId: memberId);
  final before = await repo.read();
  final profileRepo = RemoteProfileRepository(client, memberId: memberId);
  final originalProfile = await profileRepo.read();
  var writes = 0;
  final initialMail = await mailCount(provider);
  try {
    await profileRepo.update(
      ProfileDraft(
        email: 'reminder-contract@example.invalid',
        defaultHome: originalProfile.defaultHome,
      ),
    );
    await client.mutate('PUT', '/api/admin/settings', {
      'mail_enabled': '1',
      'smtp_host': smtpHost,
      'smtp_port': '$smtpPort',
      'smtp_encryption': 'none',
      'smtp_username': '',
      'smtp_password': '',
      'mail_from_address': 'sender@example.invalid',
      'mail_public_url': 'https://fixture.invalid',
      'task_email_reminder_enabled': '1',
      'password_reset_enabled': '0',
    });
    final ready = await repo.read();
    check(ready.available, 'Actual configured scheduler available');
    final controller = ReminderController(repo, ready);
    await controller.save(
      const ReminderDraft(
        enabled: true,
        sendTime: '23:59',
        days: 30,
        overdue: false,
      ),
    );
    writes++;
    check(
      controller.phase == ReminderPhase.confirmed && controller.receivedReceipt,
      'Actual settings PUT receipt and exact readback',
    );
    final saved = await repo.read();
    check(
      saved.preferences.enabled &&
          saved.preferences.sendTime == '23:59' &&
          saved.preferences.days == 30 &&
          !saved.preferences.overdue,
      'All four actual fields persisted',
    );
    check(
      await mailCount(provider) == initialMail,
      'Ordinary settings save must not send a test message',
    );
    await client.mutate('PUT', '/api/admin/settings', {
      'task_email_reminder_enabled': '0',
    });
    final unavailable = await repo.read();
    check(
      !unavailable.available && unavailable.preferences.enabled,
      'Unavailable scheduler preserves stored enabled preference',
    );
    await controller.sendTest(unavailable.email);
    check(
      controller.mailPhase == ReminderMailPhase.acknowledged,
      'Explicit test succeeds independently of scheduler availability',
    );
    await controller.sendTest(unavailable.email);
    await controller.sendTest(unavailable.email);
    check(
      await mailCount(provider) == initialMail + 3,
      'Exactly3 accepted messages in non-forwarding reserved-recipient SMTP sink',
    );
    await controller.sendTest(unavailable.email);
    check(
      controller.mailPhase == ReminderMailPhase.limited,
      'Fourth actual test is rate limited',
    );
    check(
      await mailCount(provider) == initialMail + 3,
      'Rate limited send produces no SMTP message',
    );
    var emailRejected = false;
    try {
      await repo.sendTest('changed@example.invalid');
    } on ReminderPreflightFailure {
      emailRejected = true;
    }
    check(emailRejected, 'Recipient mismatch rejects before POST');
    controller.dispose();
    final off = ReminderController(repo, await repo.read());
    await off.save(
      const ReminderDraft(
        enabled: false,
        sendTime: '00:00',
        days: 0,
        overdue: true,
      ),
    );
    writes++;
    check(
      off.phase == ReminderPhase.confirmed &&
          !(await repo.read()).preferences.enabled,
      'Unavailable scheduler permits explicit disable',
    );
    off.dispose();
    stdout.writeln(
      'PASS actual reminder settings: four fields and boundary values, verified receipt/readback, stored enable preserved during service outage, explicit disable, recipient preflight, exactly3 test messages in private non-forwarding .invalid SMTP sink and fourth429; settings changes send no mail',
    );
  } finally {
    await profileRepo.read();
    await profileRepo.update(
      ProfileDraft(
        email: originalProfile.email.isEmpty
            ? 'profile-contract@example.invalid'
            : originalProfile.email,
        defaultHome: originalProfile.defaultHome,
      ),
    );
    if (writes > 0) {
      await repo.read();
      await repo.update(
        ReminderDraft(
          enabled: false,
          sendTime: before.preferences.sendTime,
          days: before.preferences.days,
          overdue: before.preferences.overdue,
        ),
      );
    }
    await client.mutate('PUT', '/api/admin/settings', {
      'mail_enabled': '0',
      'task_email_reminder_enabled': '0',
    });
  }
}
