import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';

class OwnedAuthCheck implements Exception {
  OwnedAuthCheck(this.label);
  final String label;
}

void check(bool value, String message) {
  if (!value) throw OwnedAuthCheck(message);
}

Future<ApiFailure> rejection(Future<Object?> work, int status) async {
  try {
    await work;
  } on ApiFailure catch (error) {
    check(
      error.status == status,
      'Unexpected owned authentication rejection status',
    );
    return error;
  }
  throw OwnedAuthCheck('Owned authentication request unexpectedly succeeded');
}

Map<String, Object?> registration(
  Map<String, dynamic> c, {
  required bool approved,
  String invite = '',
}) => {
  'account': c[approved ? 'approvedAccount' : 'pendingAccount'],
  'email': c[approved ? 'approvedEmail' : 'pendingEmail'],
  'password': c['password'],
  'confirm_password': c['password'],
  'invite_code': invite,
};

Future<void> run(Map<String, dynamic> c, String phase) async {
  check(
    c['format'] == 'bookstark-owned-auth-contract-v1' &&
        c['ownedFixture'] == true,
    'Owned fixture marker required',
  );
  final base = BookstarkClient.normalizeServer(c['base'] as String);
  check(
    base.path == '/auth-fixture' && base.host.startsWith('172.'),
    'Owned prefixed bridge fixture required',
  );
  final clients = <BookstarkClient>[];
  BookstarkClient client() {
    final value = BookstarkClient(c['base'] as String);
    clients.add(value);
    return value;
  }

  try {
    if (phase == 'registration') {
      final admin = client();
      await admin.login(
        c['adminAccount'] as String,
        c['adminPassword'] as String,
      );
      Future<void> settings(Map<String, Object?> value) async {
        await admin.mutate('PUT', '/api/admin/settings', value);
      }

      await settings({
        'invite_code_enabled': '0',
        'mail_enabled': '0',
        'task_email_reminder_enabled': '0',
        'password_reset_enabled': '1',
      });
      final guest = client();
      var submissions = 0;
      check(
        (await guest.accountFormConfiguration())['invite_code_enabled'] ==
            false,
        'Actual invite-disabled configuration mismatch',
      );
      final pending = await guest.submitAccountForm(
        '/api/register',
        registration(c, approved: false),
        onSubmitted: () => submissions++,
      );
      check(
        pending['message'] == '注册成功，请等待管理员审批',
        'Actual pending registration receipt mismatch',
      );
      await rejection(
        guest.login(c['pendingAccount'] as String, c['password'] as String),
        403,
      );
      final duplicate = await rejection(
        guest.submitAccountForm(
          '/api/register',
          registration(c, approved: false),
        ),
        400,
      );
      check(
        duplicate.message == '注册失败，账号或邮箱可能已存在',
        'Actual duplicate registration receipt mismatch',
      );

      await settings({
        'invite_code_enabled': '1',
        'invite_code': c['inviteCode'],
      });
      check(
        (await guest.accountFormConfiguration())['invite_code_enabled'] == true,
        'Actual invite-enabled configuration mismatch',
      );
      await rejection(
        guest.submitAccountForm(
          '/api/register',
          registration(c, approved: true),
        ),
        400,
      );
      await rejection(
        guest.submitAccountForm(
          '/api/register',
          registration(c, approved: true, invite: 'wrong-owned-code'),
        ),
        400,
      );
      final approved = await guest.submitAccountForm(
        '/api/register',
        registration(c, approved: true, invite: c['inviteCode'] as String),
        onSubmitted: () => submissions++,
      );
      check(
        approved['message'] == '注册成功，请登录',
        'Actual approved registration receipt mismatch',
      );
      final signedIn = await guest.login(
        c['approvedAccount'] as String,
        c['password'] as String,
      );
      final member = signedIn['member'];
      check(
        member is Map && member['member_id'] is int,
        'Actual registered account login did not return member',
      );
      final approvedId = (member as Map)['member_id'] as int;
      final disabled = await rejection(
        guest.submitAccountForm('/api/password/forgot', {
          'identity': c['approvedEmail'],
        }),
        503,
      );
      check(
        disabled.message == '找回密码服务暂不可用，请联系管理员',
        'Actual disabled mail service response mismatch',
      );
      await settings({
        'mail_enabled': '1',
        'smtp_host': c['smtpHost'],
        'smtp_port': c['smtpPort'].toString(),
        'smtp_encryption': 'none',
        'smtp_username': '',
        'smtp_password': '',
        'mail_from_address': 'sender@fixture.invalid',
        'mail_from_name': 'BookStark fixture',
        'mail_public_url': base.toString(),
        'password_reset_enabled': '1',
        'task_email_reminder_enabled': '0',
      });
      final existing = await guest.submitAccountForm('/api/password/forgot', {
        'identity': c['approvedEmail'],
      });
      final missing = await guest.submitAccountForm('/api/password/forgot', {
        'identity': 'missing-owned@fixture.invalid',
      });
      check(
        existing['message'] == missing['message'] &&
            existing['message'] == '如果账号存在，重置密码邮件将发送到注册邮箱',
        'Password reset endpoint disclosed account existence',
      );
      final state = File(c['stateFile'] as String);
      state.writeAsStringSync(
        jsonEncode({
          'approvedId': approvedId,
          'oldSession': guest.exportSession(),
          'successfulRegistrationSubmissions': submissions,
        }),
      );
      File(c['registrationProof'] as String).writeAsStringSync(
        jsonEncode({
          'passed': true,
          'actualGo': true,
          'actualDartAccountClient': true,
          'serverPathPrefixPreserved': true,
          'pendingRegistrationAndLoginRejection': true,
          'duplicateRegistrationRejected': true,
          'actualInviteConfigurationChanged': true,
          'missingAndWrongInviteRejected': true,
          'correctInviteApprovedAndActualLoginSucceeded': true,
          'disabledMail503': true,
          'existingAndMissingIdentitySameGenericResponse': true,
          'successfulRegistrationSubmissions': submissions,
          'credentialsAndTokensPublished': false,
          'nativeUIClaimed': false,
        }),
      );
    } else if (phase == 'reset') {
      final state =
          jsonDecode(File(c['stateFile'] as String).readAsStringSync())
              as Map<String, dynamic>;
      final token = File(c['tokenFile'] as String).readAsStringSync().trim();
      check(
        RegExp(r'^[A-Za-z0-9_-]{40,100}$').hasMatch(token),
        'Owned SMTP token shape mismatch',
      );
      final wrong = (token.startsWith('A') ? 'B' : 'A') + token.substring(1);
      final reset = client();
      final invalid = await rejection(
        reset.submitAccountForm('/api/password/reset', {
          'token': wrong,
          'new_password': c['newPassword'],
          'confirm_password': c['newPassword'],
        }),
        400,
      );
      check(
        invalid.message == '重置链接无效或已过期',
        'Actual invalid token response mismatch',
      );
      final result = await reset.submitAccountForm('/api/password/reset', {
        'token': token,
        'new_password': c['newPassword'],
        'confirm_password': c['newPassword'],
      });
      check(
        result['message'] == '密码已重置，请使用新密码登录',
        'Actual password reset receipt mismatch',
      );
      final reused = await rejection(
        reset.submitAccountForm('/api/password/reset', {
          'token': token,
          'new_password': c['password'],
          'confirm_password': c['password'],
        }),
        400,
      );
      check(
        reused.message == '重置链接无效或已过期',
        'Actual used token was not rejected',
      );
      final oldSession = client();
      oldSession.restoreSession(
        Map<String, String>.from(state['oldSession'] as Map),
      );
      await rejection(oldSession.get('/api/profile'), 401);
      final changed = client();
      final signedIn = await changed.login(
        c['approvedAccount'] as String,
        c['newPassword'] as String,
      );
      check(
        (signedIn['member'] as Map)['member_id'] == state['approvedId'],
        'New password authenticated a different member',
      );
      await rejection(
        client().login(c['approvedAccount'] as String, c['password'] as String),
        401,
      );
      File(c['resetProof'] as String).writeAsStringSync(
        jsonEncode({
          'passed': true,
          'actualGo': true,
          'actualDartAccountClient': true,
          'tokenFromActualOwnedSMTP': true,
          'invalidTokenRejected': true,
          'actualResetApplied': true,
          'usedTokenRejected': true,
          'actualNewPasswordLoginSucceeded': true,
          'oldPasswordLoginRejected': true,
          'oldSessionRejectedAfterReset': true,
          'memberIdentityPreserved': true,
          'credentialsAndTokensPublished': false,
          'nativeUIClaimed': false,
        }),
      );
    } else {
      throw ArgumentError('Unknown owned authentication phase');
    }
  } finally {
    for (final value in clients) {
      value.close();
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Owned fixture config and phase required');
  }
  try {
    final config =
        jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
    await run(config, args[1]);
    stdout.writeln(
      'PASS owned Go/Dart authentication ${args[1]}; credentials and tokens remain private',
    );
  } catch (error) {
    if (error is OwnedAuthCheck) stderr.writeln('Owned check: ${error.label}');
    if (error is ApiFailure) {
      stderr.writeln(
        'Owned HTTP status ${error.status}; invalidJSON=${error.message == '服务器没有返回有效的 JSON 响应'}',
      );
    }
    stderr.writeln(
      'Owned authentication contract failed (${error.runtimeType}); inspect private phase evidence',
    );
    exitCode = 1;
  }
}
