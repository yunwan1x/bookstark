import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart'
    show AdminPrincipal;
import 'admin_members_models.dart';

enum AdminMemberAction { approve, reject, role, resetPassword }

extension AdminMemberActionPath on AdminMemberAction {
  String get path => switch (this) {
    AdminMemberAction.approve => 'approve',
    AdminMemberAction.reject => 'reject',
    AdminMemberAction.role => 'role',
    AdminMemberAction.resetPassword => 'reset-password',
  };
}

class AdminMemberTargetChanged implements Exception {
  const AdminMemberTargetChanged();
  @override
  String toString() => 'The reviewed member target changed; no write was sent';
}

class AdminMemberWriteUnknown implements Exception {
  const AdminMemberWriteUnknown();
  @override
  String toString() => 'Member mutation result is unknown; do not replay';
}

class AdminMemberOperationRefused implements Exception {
  const AdminMemberOperationRefused(
    this.status, {
    this.protectedTarget = false,
  });
  final int status;
  final bool protectedTarget;
  @override
  String toString() => 'Member operation refused (status: $status)';
}

class AdminMemberMutationReceipt {
  const AdminMemberMutationReceipt(this.action);
  final AdminMemberAction action;
  // Actual successful HTTP receipt only. Password is not observable on GET;
  // approve/reject do not guarantee an affected row in the current Go API.
}

class AdminMembersRepository {
  AdminMembersRepository(this.client);
  final BookstarkClient client;
  bool _disposed = false;
  int _operation = 0;
  AdminMemberPage? _lastPage;
  bool _verified = false;
  String? _sessionToken;

  void _clear() {
    _lastPage = null;
    _verified = false;
    _sessionToken = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    _clear();
  }

  String _token() {
    final value = client.exportSession()['token'];
    if (value == null || value.isEmpty) {
      _clear();
      throw StateError('Authenticated session required');
    }
    return value;
  }

  void _check(int operation, String token, AdminPrincipal owner) {
    if (_disposed ||
        operation != _operation ||
        _token() != token ||
        owner.role != 0 ||
        owner.memberId <= 0 ||
        owner.account.isEmpty) {
      throw StateError('Administrator ownership changed');
    }
  }

  Future<void> _verify(
    int operation,
    String token,
    AdminPrincipal owner,
    Future<void>? abortTrigger,
  ) async {
    final profile = await client.profileSettingsJson(
      abortTrigger: abortTrigger,
    );
    _check(operation, token, owner);
    if (profile['member_id'] != owner.memberId ||
        profile['account'] != owner.account ||
        profile['role'] is! int ||
        profile['role'] != 0) {
      _clear();
      throw StateError('Administrator ownership changed');
    }
  }

  Future<AdminMemberPage> _page(
    int operation,
    String token,
    AdminPrincipal owner,
    int page,
    Future<void>? abortTrigger,
  ) async {
    final response = await client.adminMembersPageJson(
      page,
      abortTrigger: abortTrigger,
    );
    _check(operation, token, owner);
    return AdminMemberPage.parse(response, requestedPage: page);
  }

  Future<AdminMemberPage> read(
    AdminPrincipal owner,
    int page, {
    Future<void>? abortTrigger,
  }) async {
    if (_disposed || page < 1) throw StateError('Invalid member read');
    final operation = ++_operation;
    final token = _token();
    _clear();
    try {
      _check(operation, token, owner);
      await _verify(operation, token, owner, abortTrigger);
      final result = await _page(operation, token, owner, page, abortTrigger);
      _check(operation, token, owner);
      _lastPage = result;
      _sessionToken = token;
      _verified = true;
      return result;
    } catch (_) {
      if (operation == _operation) _clear();
      rethrow;
    }
  }

  Future<AdminMemberMutationReceipt> write(
    AdminPrincipal owner,
    AdminMemberRecord reviewed,
    AdminMemberAction action, {
    AdminMemberRole? newRole,
    String? newPassword,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    final last = _lastPage;
    final token = _token();
    if (_disposed ||
        !_verified ||
        last == null ||
        _sessionToken != token ||
        !last.items.any((row) => row.sameReviewedTarget(reviewed))) {
      throw StateError('Fresh reviewed member list required');
    }
    if (action == AdminMemberAction.role) {
      if (newRole == null ||
          newRole == reviewed.role ||
          reviewed.id == owner.memberId ||
          newPassword != null) {
        throw const FormatException('Invalid role change');
      }
    } else if (newRole != null) {
      throw const FormatException('Unexpected role');
    }
    if (action == AdminMemberAction.resetPassword) {
      if (newPassword == null ||
          reviewed.status != AdminMemberStatus.approved) {
        throw const FormatException(
          'Approved member and new password required',
        );
      }
      AdminMemberPassword.validate(newPassword, newPassword);
    } else if (newPassword != null) {
      throw const FormatException('Unexpected password');
    }
    final operation = ++_operation;
    bool submitted = false;
    try {
      _check(operation, token, owner);
      await _verify(operation, token, owner, abortTrigger);
      final current = await _page(
        operation,
        token,
        owner,
        last.page,
        abortTrigger,
      );
      final found = current.items.where((row) => row.id == reviewed.id);
      if (found.length != 1 || !reviewed.sameReviewedTarget(found.single)) {
        _clear();
        throw const AdminMemberTargetChanged();
      }
      _check(operation, token, owner);
      final response = await client.adminMemberActionJson(
        reviewed.id,
        action: action.path,
        role: newRole?.value,
        password: newPassword,
        abortTrigger: abortTrigger,
        onSubmitted: () {
          submitted = true;
          onSubmitted?.call();
        },
      );
      _check(operation, token, owner);
      if (response['code'] is! int ||
          response['code'] != 0 ||
          response['message'] is! String ||
          (response['message'] as String).isEmpty) {
        throw const FormatException('Missing actual member mutation receipt');
      }
      _clear();
      return AdminMemberMutationReceipt(action);
    } on ApiFailure catch (error) {
      _clear();
      if (error.status == 401) rethrow;
      if (error.status == 403 &&
          submitted &&
          action == AdminMemberAction.role) {
        // The existing API also uses 403 for the protected built-in target.
        // Verify the operator again before classifying that as an action refusal.
        await _verify(operation, token, owner, abortTrigger);
        throw const AdminMemberOperationRefused(403, protectedTarget: true);
      }
      if (error.status == 403) rethrow;
      if (submitted && !{400, 404, 429}.contains(error.status)) {
        throw const AdminMemberWriteUnknown();
      }
      if (submitted) throw AdminMemberOperationRefused(error.status);
      rethrow;
    } catch (_) {
      _clear();
      if (submitted) throw const AdminMemberWriteUnknown();
      rethrow;
    }
  }
}
