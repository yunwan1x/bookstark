import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_members_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_members_models.dart';
import 'package:bookstark_flutter/features/admin/admin_members_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

const owner = AdminPrincipal(memberId: 1, account: 'owner-fixture', role: 0);
AdminMemberRecord member(
  int id, {
  AdminMemberStatus status = AdminMemberStatus.pending,
  AdminMemberRole role = AdminMemberRole.member,
}) => AdminMemberRecord(
  id: id,
  account: id == 1 ? 'owner-fixture' : 'member-fixture',
  role: role,
  status: status,
  created: DateTime.utc(2026, 11, 7),
  createdUnix: 1794009600,
  lastLogin: null,
);
AdminMemberPage initialPage({
  AdminMemberStatus status = AdminMemberStatus.pending,
}) => AdminMemberPage(
  items: [
    member(
      1,
      status: AdminMemberStatus.approved,
      role: AdminMemberRole.administrator,
    ),
    member(2, status: status),
  ],
  page: 1,
  total: 2,
  totalPages: 1,
);

class MemberRepository extends AdminMembersRepository {
  MemberRepository()
    : super(
        BookstarkClient(
          'https://example.invalid',
          transport: MockClient(
            (_) async =>
                throw StateError('Controller fixture must not make HTTP calls'),
          ),
        ),
      );
  AdminMemberPage data = initialPage();
  int readCalls = 0, writeAttempts = 0, submittedWrites = 0;
  Object? preflightError, writeError, readAfterWriteError;
  bool applyWrite = true, removeTarget = false;
  Completer<void>? writeGate;
  Future<AdminMemberPage> Function(int)? readHandler;
  @override
  Future<AdminMemberPage> read(
    AdminPrincipal owner,
    int page, {
    Future<void>? abortTrigger,
  }) async {
    readCalls++;
    if (readHandler != null) {
      return readHandler!(page);
    }
    final error = readAfterWriteError;
    if (submittedWrites > 0 && error != null) {
      readAfterWriteError = null;
      throw error;
    }
    return data;
  }

  @override
  Future<AdminMemberMutationReceipt> write(
    AdminPrincipal owner,
    AdminMemberRecord reviewed,
    AdminMemberAction action, {
    AdminMemberRole? newRole,
    String? newPassword,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    writeAttempts++;
    if (preflightError != null) {
      throw preflightError!;
    }
    submittedWrites++;
    onSubmitted?.call();
    if (writeGate != null) {
      await writeGate!.future;
    }
    if (applyWrite) {
      data = AdminMemberPage(
        items: [
          for (final old in data.items)
            if (old.id != reviewed.id)
              old
            else if (!removeTarget)
              member(
                old.id,
                status: switch (action) {
                  AdminMemberAction.approve => AdminMemberStatus.approved,
                  AdminMemberAction.reject => AdminMemberStatus.rejected,
                  _ => old.status,
                },
                role: action == AdminMemberAction.role ? newRole! : old.role,
              ),
        ],
        page: data.page,
        total: removeTarget ? data.total - 1 : data.total,
        totalPages: data.totalPages,
      );
    }
    if (writeError != null) {
      throw writeError!;
    }
    return AdminMemberMutationReceipt(action);
  }

  @override
  void dispose() {
    super.dispose();
    client.close();
  }
}

Future<AdminMembersController> opened(MemberRepository repository) async {
  final controller = AdminMembersController(repository, owner);
  await controller.load();
  expect(controller.select(2), isTrue);
  return controller;
}

void main() {
  test(
    'known approval reads actual current status before returning ready',
    () async {
      final repository = MemberRepository();
      final controller = await opened(repository);
      await controller.submit(controller.selected!, AdminMemberAction.approve);
      expect(repository.submittedWrites, 1);
      expect(repository.readCalls, 2);
      expect(controller.phase, AdminMembersPhase.ready);
      expect(controller.selected!.status, AdminMemberStatus.approved);
      expect(controller.notice, AdminMembersNotice.knownRead);
      expect(controller.pending, isNull);
      controller.dispose();
    },
  );
  test('known receipt with failed read retries only GET', () async {
    final repository = MemberRepository()
      ..readAfterWriteError = const ApiFailure(503, 'owned read fault');
    final controller = await opened(repository);
    await controller.submit(controller.selected!, AdminMemberAction.approve);
    expect(controller.phase, AdminMembersPhase.knownNeedsRead);
    expect(controller.notice, AdminMembersNotice.knownNeedsRead);
    await controller.readCurrent();
    expect(controller.phase, AdminMembersPhase.ready);
    expect(repository.submittedWrites, 1);
    expect(repository.readCalls, 3);
    controller.dispose();
  });
  test(
    'matching state after unknown write still requires explicit review acknowledgement',
    () async {
      final repository = MemberRepository()
        ..writeError = const AdminMemberWriteUnknown();
      final controller = await opened(repository);
      await controller.submit(controller.selected!, AdminMemberAction.approve);
      expect(controller.phase, AdminMembersPhase.unknown);
      expect(repository.readCalls, 1);
      await controller.readCurrent();
      expect(controller.selected!.status, AdminMemberStatus.approved);
      expect(controller.phase, AdminMembersPhase.reviewingUnknown);
      expect(controller.notice, AdminMembersNotice.unknownCurrent);
      expect(controller.pending, isNotNull);
      expect(controller.acknowledgeUnknown(), isTrue);
      expect(controller.notice, AdminMembersNotice.unknownReviewed);
      expect(controller.phase, AdminMembersPhase.ready);
      expect(repository.submittedWrites, 1);
      controller.dispose();
    },
  );
  test(
    'unknown password reset cannot be confirmed by unchanged member metadata',
    () async {
      final repository = MemberRepository()
        ..data = initialPage(status: AdminMemberStatus.approved)
        ..writeError = const AdminMemberWriteUnknown();
      final controller = await opened(repository);
      bool submitted = false;
      await controller.submit(
        controller.selected!,
        AdminMemberAction.resetPassword,
        newPassword: 'owned-fixture-password',
        onSubmitted: () {
          submitted = true;
        },
      );
      expect(submitted, isTrue);
      await controller.readCurrent();
      expect(controller.phase, AdminMembersPhase.reviewingUnknown);
      expect(controller.notice, AdminMembersNotice.unknownCurrent);
      expect(controller.notice, isNot(AdminMembersNotice.knownPasswordReset));
      expect(repository.submittedWrites, 1);
      controller.dispose();
    },
  );
  test(
    'changed target preflight clears stale data and never signals submission',
    () async {
      final repository = MemberRepository()
        ..preflightError = const AdminMemberTargetChanged();
      final controller = await opened(repository);
      bool submitted = false;
      await controller.submit(
        controller.selected!,
        AdminMemberAction.reject,
        onSubmitted: () {
          submitted = true;
        },
      );
      expect(submitted, isFalse);
      expect(repository.submittedWrites, 0);
      expect(controller.page, isNull);
      expect(controller.selected, isNull);
      expect(controller.notice, AdminMembersNotice.targetChanged);
      expect(controller.phase, AdminMembersPhase.needsReload);
      controller.dispose();
    },
  );
  test(
    'protected-target refusal clears member data without claiming operator logout',
    () async {
      final repository = MemberRepository()
        ..preflightError = const AdminMemberOperationRefused(
          403,
          protectedTarget: true,
        );
      final controller = await opened(repository);
      await controller.submit(
        controller.selected!,
        AdminMemberAction.role,
        newRole: AdminMemberRole.administrator,
      );
      expect(controller.page, isNull);
      expect(controller.selected, isNull);
      expect(controller.notice, AdminMembersNotice.protectedTarget);
      expect(controller.phase, AdminMembersPhase.needsReload);
      expect(repository.submittedWrites, 0);
      controller.dispose();
    },
  );
  test('401 before mutation clears all protected member state', () async {
    final repository = MemberRepository()
      ..preflightError = const ApiFailure(401, 'owned revoked');
    final controller = await opened(repository);
    await controller.submit(controller.selected!, AdminMemberAction.approve);
    expect(controller.phase, AdminMembersPhase.permissionLost);
    expect(controller.page, isNull);
    expect(controller.selected, isNull);
    expect(controller.pending, isNull);
    expect(repository.submittedWrites, 0);
    controller.dispose();
  });
  test(
    'known write receipt remains distinct from subsequent owner loss',
    () async {
      final repository = MemberRepository()
        ..readAfterWriteError = const ApiFailure(401, 'owned revoked');
      final controller = await opened(repository);
      await controller.submit(controller.selected!, AdminMemberAction.approve);
      expect(controller.phase, AdminMembersPhase.permissionLost);
      expect(controller.notice, AdminMembersNotice.knownWriteOwnerLost);
      expect(controller.page, isNull);
      expect(controller.selected, isNull);
      expect(controller.pending, isNull);
      expect(repository.submittedWrites, 1);
      controller.dispose();
    },
  );
  test(
    'successful receipt for vanished target does not invent affected member',
    () async {
      final repository = MemberRepository()..removeTarget = true;
      final controller = await opened(repository);
      await controller.submit(controller.selected!, AdminMemberAction.approve);
      expect(controller.selected, isNull);
      expect(controller.notice, AdminMembersNotice.knownTargetMissing);
      expect(controller.phase, AdminMembersPhase.ready);
      expect(repository.submittedWrites, 1);
      controller.dispose();
    },
  );
  test(
    'different fresh state after receipt never silently retries a write',
    () async {
      final repository = MemberRepository()..applyWrite = false;
      final controller = await opened(repository);
      await controller.submit(controller.selected!, AdminMemberAction.approve);
      expect(controller.selected!.status, AdminMemberStatus.pending);
      expect(controller.notice, AdminMembersNotice.knownObservedDifferent);
      expect(repository.submittedWrites, 1);
      controller.dispose();
    },
  );
  test(
    'confirmation cannot mutate a different newly selected target',
    () async {
      final repository = MemberRepository();
      final controller = await opened(repository);
      final reviewed = controller.selected!;
      controller.select(1);
      await controller.submit(reviewed, AdminMemberAction.approve);
      expect(repository.writeAttempts, 0);
      expect(controller.selected!.id, 1);
      controller.dispose();
    },
  );
  test('late list result cannot repopulate a disposed scope', () async {
    final repository = MemberRepository();
    final gate = Completer<AdminMemberPage>();
    repository.readHandler = (_) => gate.future;
    final controller = AdminMembersController(repository, owner);
    int notifications = 0;
    controller.addListener(() {
      notifications++;
    });
    final work = controller.load();
    controller.dispose();
    final before = notifications;
    gate.complete(initialPage());
    await work;
    expect(notifications, before);
    expect(controller.page, isNull);
    expect(controller.selected, isNull);
  });
  test(
    'late mutation receipt after disposal never starts a readback',
    () async {
      final repository = MemberRepository()..writeGate = Completer<void>();
      final controller = await opened(repository);
      final work = controller.submit(
        controller.selected!,
        AdminMemberAction.approve,
      );
      controller.dispose();
      repository.writeGate!.complete();
      await work;
      expect(repository.readCalls, 1);
      expect(controller.page, isNull);
      expect(controller.pending, isNull);
    },
  );
  test(
    'page reduction moves to a valid page with an explicit adjustment flag',
    () async {
      final repository = MemberRepository();
      repository.readHandler = (number) async => number == 2
          ? const AdminMemberPage(items: [], page: 2, total: 1, totalPages: 1)
          : AdminMemberPage(
              items: [member(1)],
              page: 1,
              total: 1,
              totalPages: 1,
            );
      final controller = AdminMembersController(repository, owner);
      await controller.load(2);
      expect(controller.page!.page, 1);
      expect(controller.requestedPage, 1);
      expect(controller.pageAdjusted, isTrue);
      expect(controller.notice, AdminMembersNotice.pageAdjusted);
      expect(repository.readCalls, 2);
      controller.dispose();
    },
  );
}
