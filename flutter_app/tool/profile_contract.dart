import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';
import 'package:bookstark_flutter/core/profile_edit_controller.dart';

void check(bool value, String reason) {
  if (!value) {
    throw StateError(reason);
  }
}

Future<void> runProfileContract(BookstarkClient client, int memberId) async {
  final repo = RemoteProfileRepository(client, memberId: memberId),
      initial = await RemoteProfileRepository(
        client,
        memberId: memberId,
      ).read();
  await repo.read();
  try {
    for (final module in profileHomeModules) {
      await repo.update(
        ProfileDraft(
          email: 'profile-contract@example.invalid',
          defaultHome: module,
        ),
      );
      final actual = await repo.read();
      check(
        actual.id == initial.id &&
            actual.account == initial.account &&
            actual.role == initial.role &&
            actual.email == 'profile-contract@example.invalid' &&
            actual.defaultHome == module,
        'Actual profile fields and all8 supported default modules',
      );
    }
    final baseline = await repo.read(),
        controller = ProfileEditController(repo, await repo.read());
    await client.mutate('PUT', '/api/profile', {
      'email': 'remote-profile@example.invalid',
      'default_home': 'notes',
    });
    final desired = ProfileDraft(
      email: 'local-profile@example.invalid',
      defaultHome: 'books',
    );
    await controller.save(desired);
    check(
      controller.phase == ProfileEditPhase.conflict &&
          (await repo.read()).email == 'remote-profile@example.invalid',
      'Preflight conflict does not overwrite actual changed profile',
    );
    await controller.save(desired, overwriteObserved: controller.observed);
    check(
      controller.phase == ProfileEditPhase.confirmed &&
          controller.receivedWriteReceipt &&
          desired.matches(await repo.read()),
      'Explicit observed overwrite gets real receipt and fresh verification',
    );
    controller.dispose();
    check(baseline.id == memberId, 'Current member identity remains fixed');
    final wrong = RemoteProfileRepository(client, memberId: memberId + 999999);
    var rejected = false;
    try {
      await wrong.read();
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Foreign member context rejected without writing');
    stdout.writeln(
      'PASS actual profile: fixed current member, email-only/default-home owner PUT with all8 modules, unchanged identity/role, observed conflict without overwrite, explicit recheck/save and exact receipt readback; no mail API calls',
    );
  } finally {
    await repo.read();
    final email = initial.email.isEmpty
        ? 'profile-contract@example.invalid'
        : initial.email;
    await repo.update(
      ProfileDraft(email: email, defaultHome: initial.defaultHome),
    );
  }
}
