import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart'
    show AdminPrincipal;
import 'admin_members_models.dart';
import 'admin_members_repository.dart';

enum AdminMembersPhase {
  loading,
  ready,
  submitting,
  knownNeedsRead,
  unknown,
  readingCurrent,
  reviewingUnknown,
  needsReload,
  permissionLost,
}

enum AdminMembersNotice {
  loaded,
  empty,
  pageAdjusted,
  loadFailed,
  preflightFailed,
  targetChanged,
  operationRefused,
  protectedTarget,
  ownerLost,
  knownNeedsRead,
  knownRead,
  knownTargetMissing,
  knownObservedDifferent,
  knownPasswordReset,
  knownWriteOwnerLost,
  unknown,
  unknownCurrent,
  unknownReviewed,
}

class AdminMemberPending {
  const AdminMemberPending(this.target, this.action, this.page, {this.newRole});
  final AdminMemberRecord target;
  final AdminMemberAction action;
  final int page;
  final AdminMemberRole? newRole;
  // Never store a password, confirmation, request body or secret digest.
}

class AdminMembersController extends ChangeNotifier {
  AdminMembersController(this.repository, this.owner);
  final AdminMembersRepository repository;
  final AdminPrincipal owner;
  AdminMembersPhase phase = AdminMembersPhase.loading;
  AdminMembersNotice? notice;
  AdminMemberPage? page;
  AdminMemberRecord? selected;
  AdminMemberPending? pending;
  int requestedPage = 1;
  int revision = 0;
  bool pageAdjusted = false;
  int _ticket = 0;
  bool _disposed = false;
  bool _knownReceipt = false;
  Completer<void>? _abort;
  bool get ready => !_disposed && phase == AdminMembersPhase.ready;
  bool get busy => {
    AdminMembersPhase.loading,
    AdminMembersPhase.submitting,
    AdminMembersPhase.readingCurrent,
  }.contains(phase);
  bool get hasUnresolved => pending != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _cancel() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
  }

  int _begin() {
    _cancel();
    _abort = Completer<void>();
    revision++;
    return ++_ticket;
  }

  bool _alive(int ticket) => !_disposed && ticket == _ticket;
  void _clearData() {
    page = null;
    selected = null;
  }

  void _ownerLost({bool known = false}) {
    _clearData();
    pending = null;
    _knownReceipt = false;
    phase = AdminMembersPhase.permissionLost;
    notice = known
        ? AdminMembersNotice.knownWriteOwnerLost
        : AdminMembersNotice.ownerLost;
  }

  bool _authorityError(Object error) =>
      error is StateError ||
      error is ApiFailure && {401, 403}.contains(error.status);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticket++;
    _cancel();
    _clearData();
    pending = null;
    repository.dispose();
    super.dispose();
  }

  Future<AdminMemberPage> _readValidPage(int ticket, int number) async {
    var result = await repository.read(
      owner,
      number,
      abortTrigger: _abort!.future,
    );
    if (!_alive(ticket)) return result;
    if (result.page > result.totalPages && result.items.isEmpty) {
      notice = AdminMembersNotice.pageAdjusted;
      pageAdjusted = true;
      requestedPage = result.totalPages;
      result = await repository.read(
        owner,
        result.totalPages,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return result;
      if (result.page > result.totalPages) {
        throw const FormatException('Member pages changed again');
      }
    }
    return result;
  }

  Future<void> load([int? number]) async {
    if (_disposed || phase == AdminMembersPhase.submitting || pending != null) {
      return;
    }
    final target = number ?? requestedPage;
    if (target < 1) return;
    final ticket = _begin();
    requestedPage = target;
    phase = AdminMembersPhase.loading;
    notice = null;
    pageAdjusted = false;
    _clearData();
    _emit();
    try {
      final result = await _readValidPage(ticket, target);
      if (!_alive(ticket)) return;
      page = result;
      requestedPage = result.page;
      phase = AdminMembersPhase.ready;
      notice ??= result.items.isEmpty
          ? AdminMembersNotice.empty
          : AdminMembersNotice.loaded;
    } catch (error) {
      if (!_alive(ticket)) return;
      if (_authorityError(error)) {
        _ownerLost();
      } else {
        phase = AdminMembersPhase.needsReload;
        notice = AdminMembersNotice.loadFailed;
        _clearData();
      }
    }
    _emit();
  }

  bool select(int id) {
    if (!ready || page == null) return false;
    final matches = page!.items.where((member) => member.id == id);
    if (matches.length != 1) return false;
    selected = matches.single;
    revision++;
    _emit();
    return true;
  }

  void closeDetail() {
    if (!ready) return;
    selected = null;
    revision++;
    _emit();
  }

  Future<void> submit(
    AdminMemberRecord confirmedTarget,
    AdminMemberAction action, {
    AdminMemberRole? newRole,
    String? newPassword,
    void Function()? onSubmitted,
  }) async {
    final target = selected;
    final currentPage = page;
    if (!ready ||
        target == null ||
        currentPage == null ||
        !target.sameReviewedTarget(confirmedTarget)) {
      return;
    }
    final ticket = _begin();
    pending = AdminMemberPending(
      target,
      action,
      currentPage.page,
      newRole: newRole,
    );
    _knownReceipt = false;
    phase = AdminMembersPhase.submitting;
    notice = null;
    _emit();
    try {
      await repository.write(
        owner,
        target,
        action,
        newRole: newRole,
        newPassword: newPassword,
        abortTrigger: _abort!.future,
        onSubmitted: onSubmitted,
      );
      if (!_alive(ticket)) return;
      _knownReceipt = true;
      phase = AdminMembersPhase.knownNeedsRead;
      notice = AdminMembersNotice.knownNeedsRead;
      _emit();
      await _readKnown(ticket);
    } on AdminMemberWriteUnknown {
      if (!_alive(ticket)) return;
      phase = AdminMembersPhase.unknown;
      notice = AdminMembersNotice.unknown;
      _emit();
    } on AdminMemberTargetChanged {
      if (!_alive(ticket)) return;
      pending = null;
      _clearData();
      phase = AdminMembersPhase.needsReload;
      notice = AdminMembersNotice.targetChanged;
      _emit();
    } on AdminMemberOperationRefused catch (error) {
      if (!_alive(ticket)) return;
      pending = null;
      _clearData();
      phase = AdminMembersPhase.needsReload;
      notice = error.protectedTarget
          ? AdminMembersNotice.protectedTarget
          : AdminMembersNotice.operationRefused;
      _emit();
    } catch (error) {
      if (!_alive(ticket)) return;
      if (_authorityError(error)) {
        _ownerLost();
      } else {
        pending = null;
        _clearData();
        phase = AdminMembersPhase.needsReload;
        notice = AdminMembersNotice.preflightFailed;
      }
      _emit();
    }
  }

  Future<void> _readKnown(int ticket) async {
    final operation = pending;
    if (operation == null || !_knownReceipt) return;
    try {
      final result = await _readValidPage(ticket, operation.page);
      if (!_alive(ticket)) return;
      page = result;
      requestedPage = result.page;
      final matches = result.items.where(
        (row) =>
            row.id == operation.target.id &&
            row.account == operation.target.account,
      );
      selected = matches.length == 1 ? matches.single : null;
      if (selected == null) {
        notice = AdminMembersNotice.knownTargetMissing;
      } else if (operation.action == AdminMemberAction.resetPassword) {
        notice = AdminMembersNotice.knownPasswordReset;
      } else {
        final expected = switch (operation.action) {
          AdminMemberAction.approve =>
            selected!.status == AdminMemberStatus.approved,
          AdminMemberAction.reject =>
            selected!.status == AdminMemberStatus.rejected,
          AdminMemberAction.role => selected!.role == operation.newRole,
          AdminMemberAction.resetPassword => true,
        };
        notice = expected
            ? AdminMembersNotice.knownRead
            : AdminMembersNotice.knownObservedDifferent;
      }
      pending = null;
      _knownReceipt = false;
      phase = AdminMembersPhase.ready;
      _emit();
    } catch (error) {
      if (!_alive(ticket)) return;
      if (_authorityError(error)) {
        _ownerLost(known: true);
      } else {
        phase = AdminMembersPhase.knownNeedsRead;
        notice = AdminMembersNotice.knownNeedsRead;
      }
      _emit();
    }
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        busy ||
        pending == null ||
        !{
          AdminMembersPhase.unknown,
          AdminMembersPhase.reviewingUnknown,
          AdminMembersPhase.knownNeedsRead,
        }.contains(phase)) {
      return;
    }
    final ticket = _begin();
    if (_knownReceipt) {
      phase = AdminMembersPhase.readingCurrent;
      _emit();
      await _readKnown(ticket);
      return;
    }
    final operation = pending!;
    phase = AdminMembersPhase.readingCurrent;
    _emit();
    try {
      final result = await _readValidPage(ticket, operation.page);
      if (!_alive(ticket)) return;
      page = result;
      requestedPage = result.page;
      final matches = result.items.where(
        (row) =>
            row.id == operation.target.id &&
            row.account == operation.target.account,
      );
      selected = matches.length == 1 ? matches.single : null;
      phase = AdminMembersPhase.reviewingUnknown;
      notice = AdminMembersNotice.unknownCurrent;
    } catch (error) {
      if (!_alive(ticket)) return;
      if (_authorityError(error)) {
        _ownerLost();
      } else {
        phase = AdminMembersPhase.unknown;
        notice = AdminMembersNotice.unknown;
      }
    }
    _emit();
  }

  bool acknowledgeUnknown() {
    if (_disposed ||
        phase != AdminMembersPhase.reviewingUnknown ||
        page == null) {
      return false;
    }
    pending = null;
    _knownReceipt = false;
    phase = AdminMembersPhase.ready;
    notice = AdminMembersNotice.unknownReviewed;
    revision++;
    _emit();
    return true;
  }
}
