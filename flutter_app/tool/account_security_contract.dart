import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';
import 'package:bookstark_flutter/core/account_password_repository.dart';
import 'package:bookstark_flutter/core/account_security_controller.dart';

void check(bool value, String reason) {
  if (!value) {
    throw StateError(reason);
  }
}

Future<void> runAccountSecurityContract(
  BookstarkClient client,
  int memberId,
  String originalPassword,
) async {
  final member = await RemoteProfileRepository(
    client,
    memberId: memberId,
  ).read();
  var stores = 0;
  final repo = RemoteAccountPasswordRepository(
    client,
    member: member,
    saveSession: () async {
      stores++;
      return client.exportSession().containsKey('token');
    },
  );
  final controller = AccountSecurityController(repo);
  const next = ' contract 新密码 spaces ';
  var changed = false;
  try {
    await controller.change(originalPassword, next);
    changed = controller.receivedWriteReceipt;
    check(
      controller.phase == AccountSecurityPhase.complete &&
          controller.credentialsVerified &&
          stores == 1,
      'Actual password change requires new credential login, same member and saved session',
    );
    final old = BookstarkClient(client.baseUri.toString());
    var rejected = false;
    try {
      await old.credentialLoginJson(member.account, originalPassword);
    } on ApiFailure catch (error) {
      rejected = error.status == 401 || error.status == 400;
    } finally {
      old.close();
    }
    check(rejected, 'Actual old credentials rejected after password change');
    await repo.verifyAndAdopt(next);
    final actual = await RemoteProfileRepository(
      client,
      memberId: memberId,
    ).read();
    check(
      actual.id == member.id &&
          actual.account == member.account &&
          actual.email == member.email &&
          actual.defaultHome == member.defaultHome,
      'Account change keeps actual identity and profile preferences',
    );
    stdout.writeln(
      'PASS actual account security: raw Unicode/spaces password mutation, new isolated login and profile verification, adopted actual cookie, session save, old credentials rejected and unchanged profile; disposable fixture only',
    );
  } finally {
    controller.dispose();
    if (changed) {
      await repo.change(next, originalPassword);
      await repo.verifyAndAdopt(originalPassword);
    }
  }
}
