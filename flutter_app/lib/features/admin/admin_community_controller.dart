import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'admin_community_repository.dart';
import 'admin_friend_links_models.dart';
import 'admin_comment_models.dart';
import 'admin_settings_repository.dart' show AdminPrincipal;

enum AdminCommunityPhase {
  loading,
  ready,
  submitting,
  knownNeedsRead,
  unknown,
  readingCurrent,
  reviewing,
  needsReload,
  permissionLost,
}

enum AdminCommunityPendingKind { known, unknown, notSubmitted }

enum AdminCommunityNotice {
  loaded,
  empty,
  loadFailed,
  invalidDraft,
  changedBeforeWrite,
  changedCurrent,
  operationRefused,
  preflightFailed,
  unknownWrite,
  unknownCurrent,
  reviewEnded,
  staleDraftDiscarded,
  knownNeedsRead,
  knownLinksRead,
  knownLinksDifferent,
  knownDeletedRead,
  knownDeleteZero,
  ownerLost,
  knownWriteOwnerLost,
}

abstract class AdminCommunityController extends ChangeNotifier {
  AdminCommunityController(this.owner);
  final AdminPrincipal owner;
  AdminCommunityPhase _phase = AdminCommunityPhase.loading;
  AdminCommunityNotice? _notice;
  AdminCommunityPendingKind? _pendingKind;
  bool _disposed = false;
  int _revision = 0, _operation = 0;
  Completer<void>? _abort;
  AdminCommunityPhase get phase => _phase;
  AdminCommunityNotice? get notice => _notice;
  AdminCommunityPendingKind? get pendingKind => _pendingKind;
  int get revision => _revision;
  bool get ready => !_disposed && _phase == AdminCommunityPhase.ready;
  bool get busy =>
      !_disposed &&
      _operation > 0 &&
      {
        AdminCommunityPhase.loading,
        AdminCommunityPhase.submitting,
        AdminCommunityPhase.readingCurrent,
      }.contains(_phase);
  bool get reviewing => _phase == AdminCommunityPhase.reviewing;
  bool get pending => _pendingKind != null;
  int _begin(AdminCommunityPhase phase) {
    if (_abort != null && !_abort!.isCompleted) {
      _abort!.complete();
    }
    _abort = Completer<void>();
    _phase = phase;
    _revision++;
    return ++_operation;
  }

  bool _current(int operation) => !_disposed && operation == _operation;
  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _ownerError(Object error) =>
      error is AdminCommunityOwnerLost ||
      error is ApiFailure && {401, 403}.contains(error.status);
  void clearData();
  void disposeRepository();
  bool _handleOwner(Object error, int operation, {bool known = false}) {
    if (!_current(operation)) return true;
    if (!_ownerError(error)) return false;
    clearData();
    _phase = AdminCommunityPhase.permissionLost;
    _notice = known
        ? AdminCommunityNotice.knownWriteOwnerLost
        : AdminCommunityNotice.ownerLost;
    _emit();
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    _revision++;
    if (_abort != null && !_abort!.isCompleted) {
      _abort!.complete();
    }
    clearData();
    disposeRepository();
    super.dispose();
  }
}

class AdminFriendLinkDraftRow {
  const AdminFriendLinkDraftRow(this.key, this.link);
  final int key;
  final AdminFriendLink link;
}

class AdminFriendLinksController extends AdminCommunityController {
  AdminFriendLinksController(this.repository, super.owner);
  final AdminFriendLinksRepository repository;
  AdminFriendLinksSnapshot? _baseline, _pendingDraft, _currentReview;
  List<AdminFriendLinkDraftRow> _rows = [];
  bool _simple = false;
  int _nextKey = 0;
  List<AdminFriendLinkDraftRow> get rows => List.unmodifiable(_rows);
  bool get simpleMode => _simple;
  AdminFriendLinksSnapshot? get baseline => _baseline;
  AdminFriendLinksSnapshot? get pendingDraft => _pendingDraft;
  AdminFriendLinksSnapshot? get currentReview => _currentReview;
  AdminFriendLinksSnapshot get draft => AdminFriendLinksSnapshot(
    items: [for (final row in _rows) row.link],
    simpleMode: _simple,
  );
  String _rawKey(AdminFriendLinksSnapshot value) => jsonEncode({
    'items': [for (final row in value.items) row.raw],
    'simple_mode': value.simpleMode,
  });
  bool get dirty => _baseline != null && _rawKey(draft) != _rawKey(_baseline!);
  @override
  void clearData() {
    _baseline = null;
    _pendingDraft = null;
    _currentReview = null;
    _pendingKind = null;
    _rows = [];
    _simple = false;
  }

  @override
  void disposeRepository() => repository.dispose();
  void _install(AdminFriendLinksSnapshot value) {
    _baseline = value;
    _rows = [
      for (final item in value.items) AdminFriendLinkDraftRow(++_nextKey, item),
    ];
    _simple = value.simpleMode;
    _pendingDraft = null;
    _currentReview = null;
    _pendingKind = null;
  }

  Future<bool> load({bool discardDraft = false}) async {
    if (_disposed || busy || pending || (dirty && !discardDraft)) return false;
    final operation = _begin(AdminCommunityPhase.loading);
    clearData();
    _notice = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_current(operation)) return false;
      _install(value);
      _phase = AdminCommunityPhase.ready;
      _notice = value.items.isEmpty
          ? AdminCommunityNotice.empty
          : AdminCommunityNotice.loaded;
      _emit();
      return true;
    } catch (error) {
      if (_handleOwner(error, operation)) return false;
      _phase = AdminCommunityPhase.needsReload;
      _notice = AdminCommunityNotice.loadFailed;
      _emit();
      return false;
    }
  }

  bool setSimpleMode(bool value) {
    if (!ready) return false;
    _simple = value;
    _revision++;
    _notice = null;
    _emit();
    return true;
  }

  bool applyRow(
    int? key,
    AdminFriendLink link, {
    required int expectedRevision,
  }) {
    if (!ready || expectedRevision != _revision) return false;
    try {
      link.validate();
    } on FormatException {
      _notice = AdminCommunityNotice.invalidDraft;
      _emit();
      return false;
    }
    if (key == null) {
      if (_rows.length >= 200) {
        _notice = AdminCommunityNotice.invalidDraft;
        _emit();
        return false;
      }
      _rows = [..._rows, AdminFriendLinkDraftRow(++_nextKey, link)];
    } else {
      if (!_rows.any((row) => row.key == key)) return false;
      _rows = [
        for (final row in _rows)
          row.key == key ? AdminFriendLinkDraftRow(key, link) : row,
      ];
    }
    _revision++;
    _notice = null;
    _emit();
    return true;
  }

  bool removeRow(int key, {required int expectedRevision}) {
    if (!ready ||
        expectedRevision != _revision ||
        !_rows.any((row) => row.key == key)) {
      return false;
    }
    _rows = [
      for (final row in _rows)
        if (row.key != key) row,
    ];
    _revision++;
    _notice = null;
    _emit();
    return true;
  }

  bool validateDraft() {
    if (!ready || !dirty) return false;
    try {
      draft.checkedBody();
      return true;
    } on FormatException {
      _notice = AdminCommunityNotice.invalidDraft;
      _emit();
      return false;
    }
  }

  Future<void> submit({required int expectedRevision}) async {
    if (expectedRevision != _revision ||
        !validateDraft() ||
        _baseline == null) {
      return;
    }
    final reviewed = _baseline!, submittedDraft = draft;
    final operation = _begin(AdminCommunityPhase.submitting);
    _pendingDraft = submittedDraft;
    _currentReview = null;
    _pendingKind = null;
    _notice = null;
    _emit();
    var known = false;
    try {
      await repository.replace(
        owner,
        reviewed,
        submittedDraft,
        abortTrigger: _abort!.future,
      );
      if (!_current(operation)) return;
      known = true;
      _pendingKind = AdminCommunityPendingKind.known;
      final current = await repository.read(
        owner,
        abortTrigger: _abort!.future,
      );
      if (!_current(operation)) return;
      final same = current.semanticKey == submittedDraft.semanticKey;
      _install(current);
      _phase = AdminCommunityPhase.ready;
      _notice = same
          ? AdminCommunityNotice.knownLinksRead
          : AdminCommunityNotice.knownLinksDifferent;
      _emit();
    } catch (error) {
      if (_handleOwner(error, operation, known: known)) return;
      if (known) {
        _pendingKind = AdminCommunityPendingKind.known;
        _phase = AdminCommunityPhase.knownNeedsRead;
        _notice = AdminCommunityNotice.knownNeedsRead;
      } else if (error is AdminCommunityWriteUnknown) {
        _pendingKind = AdminCommunityPendingKind.unknown;
        _phase = AdminCommunityPhase.unknown;
        _notice = AdminCommunityNotice.unknownWrite;
      } else if (error is AdminCommunityTargetChanged) {
        _pendingKind = AdminCommunityPendingKind.notSubmitted;
        _phase = AdminCommunityPhase.needsReload;
        _notice = AdminCommunityNotice.changedBeforeWrite;
      } else {
        _pendingKind = null;
        _pendingDraft = null;
        _phase = AdminCommunityPhase.needsReload;
        _notice = error is AdminCommunityOperationRefused
            ? AdminCommunityNotice.operationRefused
            : AdminCommunityNotice.preflightFailed;
      }
      _emit();
    }
  }

  Future<void> readCurrent() async {
    if (_disposed || busy || !pending) return;
    final kind = _pendingKind!, expected = _pendingDraft;
    final operation = _begin(AdminCommunityPhase.readingCurrent);
    _currentReview = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_current(operation)) return;
      if (kind == AdminCommunityPendingKind.known) {
        final same =
            expected != null && value.semanticKey == expected.semanticKey;
        _install(value);
        _phase = AdminCommunityPhase.ready;
        _notice = same
            ? AdminCommunityNotice.knownLinksRead
            : AdminCommunityNotice.knownLinksDifferent;
      } else {
        _currentReview = value;
        _phase = AdminCommunityPhase.reviewing;
        _notice = kind == AdminCommunityPendingKind.unknown
            ? AdminCommunityNotice.unknownCurrent
            : AdminCommunityNotice.changedCurrent;
      }
      _emit();
    } catch (error) {
      if (_handleOwner(
        error,
        operation,
        known: kind == AdminCommunityPendingKind.known,
      )) {
        return;
      }
      _phase = kind == AdminCommunityPendingKind.known
          ? AdminCommunityPhase.knownNeedsRead
          : kind == AdminCommunityPendingKind.unknown
          ? AdminCommunityPhase.unknown
          : AdminCommunityPhase.needsReload;
      _notice = AdminCommunityNotice.loadFailed;
      _emit();
    }
  }

  bool acknowledgeCurrent() {
    if (_disposed ||
        !reviewing ||
        _currentReview == null ||
        _pendingKind == AdminCommunityPendingKind.known) {
      return false;
    }
    final kind = _pendingKind;
    _install(_currentReview!);
    _phase = AdminCommunityPhase.ready;
    _revision++;
    _notice = kind == AdminCommunityPendingKind.unknown
        ? AdminCommunityNotice.reviewEnded
        : AdminCommunityNotice.staleDraftDiscarded;
    _emit();
    return true;
  }
}

class AdminCommentsController extends AdminCommunityController {
  AdminCommentsController(this.repository, super.owner);
  final AdminCommentsRepository repository;
  AdminCommentFilter _filter = const AdminCommentFilter();
  AdminCommentPage? _page, _currentReview;
  List<AdminCommentRecord> _pendingTargets = [];
  Set<int> _selected = {};
  int? _actualDeleted;
  bool _pageAdjusted = false;
  AdminCommentFilter get filter => _filter;
  AdminCommentPage? get page => _page;
  AdminCommentPage? get currentReview => _currentReview;
  List<AdminCommentRecord> get pendingTargets =>
      List.unmodifiable(_pendingTargets);
  Set<int> get selected => Set.unmodifiable(_selected);
  int? get actualDeleted => _actualDeleted;
  bool get pageAdjusted => _pageAdjusted;
  @override
  void clearData() {
    _page = null;
    _currentReview = null;
    _pendingTargets = [];
    _selected = {};
    _actualDeleted = null;
    _pendingKind = null;
    _pageAdjusted = false;
    _filter = const AdminCommentFilter();
  }

  @override
  void disposeRepository() => repository.dispose();
  Future<AdminCommentPage> _readValid(
    AdminCommentFilter filter,
    int page,
    Future<void> abort,
    int operation,
  ) async {
    final value = await repository.read(
      owner,
      filter,
      page,
      abortTrigger: abort,
    );
    if (!_current(operation)) {
      throw AdminCommunityOwnerLost();
    }
    if (value.page > value.totalPages) {
      final valid = await repository.read(
        owner,
        filter,
        value.totalPages,
        abortTrigger: abort,
      );
      if (!_current(operation)) {
        throw AdminCommunityOwnerLost();
      }
      if (valid.page > valid.totalPages) {
        throw const FormatException('Comment pagination changed again');
      }
      _pageAdjusted = true;
      return valid;
    }
    return value;
  }

  void _install(AdminCommentPage value) {
    _page = value;
    _currentReview = null;
    _selected = {};
    _pendingTargets = [];
    _pendingKind = null;
  }

  Future<bool> load({AdminCommentFilter? filter, int page = 1}) async {
    if (_disposed || busy || pending) return false;
    final desired = filter ?? _filter;
    desired.query(page);
    final operation = _begin(AdminCommunityPhase.loading);
    _page = null;
    _currentReview = null;
    _selected = {};
    _pendingTargets = [];
    _actualDeleted = null;
    _pageAdjusted = false;
    _filter = desired;
    _notice = null;
    _emit();
    try {
      final value = await _readValid(desired, page, _abort!.future, operation);
      if (!_current(operation)) return false;
      _install(value);
      _phase = AdminCommunityPhase.ready;
      _notice = value.total == 0
          ? AdminCommunityNotice.empty
          : AdminCommunityNotice.loaded;
      _emit();
      return true;
    } catch (error) {
      if (_handleOwner(error, operation)) return false;
      _phase = AdminCommunityPhase.needsReload;
      _notice = AdminCommunityNotice.loadFailed;
      _emit();
      return false;
    }
  }

  bool select(int id, bool selected) {
    if (!ready || _page == null || !_page!.items.any((row) => row.id == id)) {
      return false;
    }
    _selected = {..._selected};
    if (selected) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
    _revision++;
    _emit();
    return true;
  }

  List<AdminCommentRecord> reviewedSelection() {
    if (!ready || _page == null || _selected.isEmpty) return const [];
    return _page!.reviewedSelection(_selected);
  }

  Future<void> submitDelete({
    required int expectedRevision,
    required List<AdminCommentRecord> targets,
  }) async {
    if (!ready ||
        expectedRevision != _revision ||
        _page == null ||
        _selected.isEmpty) {
      return;
    }
    final selected = reviewedSelection();
    if (targets.length != selected.length ||
        targets.map((row) => row.id).toSet().length != targets.length ||
        !selected.every((row) => targets.any(row.sameReviewedTarget))) {
      return;
    }
    final originalPage = _page!.page, originalFilter = _filter;
    final operation = _begin(AdminCommunityPhase.submitting);
    _pendingTargets = List.unmodifiable(selected);
    _selected = {};
    _currentReview = null;
    _actualDeleted = null;
    _pendingKind = null;
    _pageAdjusted = false;
    _notice = null;
    _emit();
    var known = false;
    try {
      final receipt = await repository.delete(
        owner,
        selected,
        abortTrigger: _abort!.future,
      );
      if (!_current(operation)) return;
      known = true;
      _actualDeleted = receipt.deleted;
      _pendingKind = AdminCommunityPendingKind.known;
      final value = await _readValid(
        originalFilter,
        originalPage,
        _abort!.future,
        operation,
      );
      if (!_current(operation)) return;
      _install(value);
      _phase = AdminCommunityPhase.ready;
      _notice = receipt.deleted == 0
          ? AdminCommunityNotice.knownDeleteZero
          : AdminCommunityNotice.knownDeletedRead;
      _emit();
    } catch (error) {
      if (_handleOwner(error, operation, known: known)) return;
      if (known) {
        _pendingKind = AdminCommunityPendingKind.known;
        _phase = AdminCommunityPhase.knownNeedsRead;
        _notice = AdminCommunityNotice.knownNeedsRead;
      } else if (error is AdminCommunityWriteUnknown) {
        _pendingKind = AdminCommunityPendingKind.unknown;
        _phase = AdminCommunityPhase.unknown;
        _notice = AdminCommunityNotice.unknownWrite;
      } else {
        _pendingTargets = [];
        _pendingKind = null;
        _phase = AdminCommunityPhase.needsReload;
        _notice = error is AdminCommunityTargetChanged
            ? AdminCommunityNotice.changedBeforeWrite
            : error is AdminCommunityOperationRefused
            ? AdminCommunityNotice.operationRefused
            : AdminCommunityNotice.preflightFailed;
      }
      _emit();
    }
  }

  Future<void> readCurrent() async {
    if (_disposed || busy || !pending || _page == null) return;
    final kind = _pendingKind!, filter = _filter, page = _page!.page;
    final operation = _begin(AdminCommunityPhase.readingCurrent);
    _currentReview = null;
    _pageAdjusted = false;
    _emit();
    try {
      final value = await _readValid(filter, page, _abort!.future, operation);
      if (!_current(operation)) return;
      if (kind == AdminCommunityPendingKind.known) {
        _install(value);
        _phase = AdminCommunityPhase.ready;
        _notice = _actualDeleted == 0
            ? AdminCommunityNotice.knownDeleteZero
            : AdminCommunityNotice.knownDeletedRead;
      } else {
        _currentReview = value;
        _phase = AdminCommunityPhase.reviewing;
        _notice = AdminCommunityNotice.unknownCurrent;
      }
      _emit();
    } catch (error) {
      if (_handleOwner(
        error,
        operation,
        known: kind == AdminCommunityPendingKind.known,
      )) {
        return;
      }
      _phase = kind == AdminCommunityPendingKind.known
          ? AdminCommunityPhase.knownNeedsRead
          : AdminCommunityPhase.unknown;
      _notice = AdminCommunityNotice.loadFailed;
      _emit();
    }
  }

  bool acknowledgeCurrent() {
    if (_disposed ||
        !reviewing ||
        _currentReview == null ||
        _pendingKind != AdminCommunityPendingKind.unknown) {
      return false;
    }
    _install(_currentReview!);
    _actualDeleted = null;
    _phase = AdminCommunityPhase.ready;
    _notice = AdminCommunityNotice.reviewEnded;
    _revision++;
    _emit();
    return true;
  }
}
