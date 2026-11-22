import 'package:bookstark_flutter/core/api_client.dart';
import 'admin_settings_repository.dart' show AdminPrincipal;
import 'admin_friend_links_models.dart';
import 'admin_comment_models.dart';

class AdminCommunityOwnerLost extends StateError {
  AdminCommunityOwnerLost() : super('Administrator ownership changed');
}

class AdminCommunityTargetChanged implements Exception {
  const AdminCommunityTargetChanged();
  @override
  String toString() =>
      'Reviewed community configuration changed; no write sent';
}

class AdminCommunityWriteUnknown implements Exception {
  const AdminCommunityWriteUnknown();
  @override
  String toString() => 'Community operation result unknown; do not replay';
}

class AdminCommunityOperationRefused implements Exception {
  const AdminCommunityOperationRefused(this.status);
  final int status;
  @override
  String toString() => 'Community operation refused (status: $status)';
}

class _Ticket {
  const _Ticket(this.operation, this.token, this.owner);
  final int operation;
  final String token;
  final AdminPrincipal owner;
}

abstract class _OwnedRepository {
  _OwnedRepository(this.client)
    : _initialToken = client.exportSession()['token'];
  final BookstarkClient client;
  final String? _initialToken;
  bool _disposed = false;
  int _operation = 0;
  void clearReview();
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    clearReview();
  }

  String token() {
    final current = client.exportSession()['token'];
    if (_disposed ||
        current == null ||
        current.isEmpty ||
        current != _initialToken) {
      clearReview();
      throw AdminCommunityOwnerLost();
    }
    return current;
  }

  _Ticket start(AdminPrincipal owner) {
    final current = token();
    if (owner.role != 0 || owner.memberId <= 0 || owner.account.isEmpty) {
      clearReview();
      throw AdminCommunityOwnerLost();
    }
    return _Ticket(++_operation, current, owner);
  }

  void check(_Ticket ticket) {
    if (_disposed ||
        ticket.operation != _operation ||
        token() != ticket.token) {
      throw AdminCommunityOwnerLost();
    }
  }

  void invalidate(_Ticket ticket) {
    if (ticket.operation == _operation) clearReview();
  }

  Future<void> verify(_Ticket ticket, Future<void>? abort) async {
    final profile = await client.profileSettingsJson(abortTrigger: abort);
    check(ticket);
    if (profile['member_id'] != ticket.owner.memberId ||
        profile['account'] != ticket.owner.account ||
        profile['role'] is! int ||
        profile['role'] != 0) {
      invalidate(ticket);
      throw AdminCommunityOwnerLost();
    }
  }

  Future<T> mutation<T>(
    _Ticket ticket,
    Future<T> Function(void Function()) action, {
    void Function()? onSubmitted,
  }) async {
    var submitted = false;
    try {
      final result = await action(() {
        check(ticket);
        submitted = true;
        onSubmitted?.call();
      });
      check(ticket);
      invalidate(ticket);
      return result;
    } on AdminCommunityOwnerLost {
      invalidate(ticket);
      rethrow;
    } on ApiFailure catch (error) {
      invalidate(ticket);
      if (error.status == 401 || error.status == 403) rethrow;
      if (submitted) {
        if ({400, 404, 429}.contains(error.status)) {
          throw AdminCommunityOperationRefused(error.status);
        }
        throw const AdminCommunityWriteUnknown();
      }
      rethrow;
    } catch (_) {
      invalidate(ticket);
      if (submitted) throw const AdminCommunityWriteUnknown();
      rethrow;
    }
  }
}

class AdminFriendLinksReceipt {
  const AdminFriendLinksReceipt();
}

class AdminFriendLinksRepository extends _OwnedRepository {
  AdminFriendLinksRepository(super.client);
  AdminFriendLinksSnapshot? _reviewed;
  String? _reviewToken;
  @override
  void clearReview() {
    _reviewed = null;
    _reviewToken = null;
  }

  Future<AdminFriendLinksSnapshot> _get(
    _Ticket ticket,
    Future<void>? abort,
  ) async {
    final data = await client.adminFriendLinksJson(abortTrigger: abort);
    check(ticket);
    return AdminFriendLinksSnapshot.parse(data);
  }

  Future<AdminFriendLinksSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = start(owner);
    clearReview();
    try {
      await verify(ticket, abortTrigger);
      final result = await _get(ticket, abortTrigger);
      check(ticket);
      _reviewed = result;
      _reviewToken = ticket.token;
      return result;
    } catch (_) {
      invalidate(ticket);
      rethrow;
    }
  }

  Future<AdminFriendLinksReceipt> replace(
    AdminPrincipal owner,
    AdminFriendLinksSnapshot reviewed,
    AdminFriendLinksSnapshot draft, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    final current = token();
    if (_reviewed == null ||
        _reviewToken != current ||
        _reviewed!.semanticKey != reviewed.semanticKey) {
      throw const AdminCommunityTargetChanged();
    }
    final body = draft.checkedBody();
    final ticket = start(owner);
    return mutation(ticket, (submitted) async {
      await verify(ticket, abortTrigger);
      final fresh = await _get(ticket, abortTrigger);
      if (fresh.semanticKey != reviewed.semanticKey) {
        throw const AdminCommunityTargetChanged();
      }
      check(ticket);
      final receipt = await client.adminFriendLinksJson(
        replacement: body,
        abortTrigger: abortTrigger,
        onSubmitted: submitted,
      );
      check(ticket);
      if (receipt['code'] is! int ||
          receipt['code'] != 0 ||
          receipt['message'] is! String ||
          (receipt['message'] as String).isEmpty) {
        throw const FormatException('Missing friend link acknowledgement');
      }
      return const AdminFriendLinksReceipt();
    }, onSubmitted: onSubmitted);
  }
}

class AdminCommentsRepository extends _OwnedRepository {
  AdminCommentsRepository(super.client);
  AdminCommentPage? _reviewed;
  AdminCommentFilter? _filter;
  String? _reviewToken;
  @override
  void clearReview() {
    _reviewed = null;
    _filter = null;
    _reviewToken = null;
  }

  Future<AdminCommentPage> _get(
    _Ticket ticket,
    AdminCommentFilter filter,
    int page,
    Future<void>? abort,
  ) async {
    final data = await client.adminShareCommentsJson(
      page,
      keyword: filter.keyword,
      status: filter.status?.value,
      targetType: filter.target?.value,
      abortTrigger: abort,
    );
    check(ticket);
    return AdminCommentPage.parse(data, requestedPage: page);
  }

  Future<AdminCommentPage> read(
    AdminPrincipal owner,
    AdminCommentFilter filter,
    int page, {
    Future<void>? abortTrigger,
  }) async {
    filter.query(page);
    final ticket = start(owner);
    clearReview();
    try {
      await verify(ticket, abortTrigger);
      final result = await _get(ticket, filter, page, abortTrigger);
      check(ticket);
      _reviewed = result;
      _filter = filter;
      _reviewToken = ticket.token;
      return result;
    } catch (_) {
      invalidate(ticket);
      rethrow;
    }
  }

  Future<AdminCommentDeleteReceipt> delete(
    AdminPrincipal owner,
    List<AdminCommentRecord> reviewedTargets, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    final current = token(), page = _reviewed, filter = _filter;
    final targets = List<AdminCommentRecord>.unmodifiable(reviewedTargets);
    if (page == null ||
        filter == null ||
        _reviewToken != current ||
        targets.isEmpty ||
        targets.length > 20 ||
        targets.map((row) => row.id).toSet().length != targets.length ||
        !targets.every((target) => page.items.any(target.sameReviewedTarget))) {
      throw const AdminCommunityTargetChanged();
    }
    final ticket = start(owner);
    return mutation(ticket, (submitted) async {
      await verify(ticket, abortTrigger);
      final fresh = await _get(ticket, filter, page.page, abortTrigger);
      if (!targets.every(
        (target) => fresh.items.any(target.sameReviewedTarget),
      )) {
        throw const AdminCommunityTargetChanged();
      }
      check(ticket);
      final data = await client.adminDeleteShareCommentsJson(
        [for (final target in targets) target.id],
        abortTrigger: abortTrigger,
        onSubmitted: submitted,
      );
      check(ticket);
      return AdminCommentDeleteReceipt.fromAcknowledgedData(data);
    }, onSubmitted: onSubmitted);
  }
}
