import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';

enum NoteActionProperty { pin, visibility }

enum NoteActionIssue {
  notOwner,
  wrongType,
  invalidMetadata,
  forbidden,
  notFound,
  unknown,
  unconfirmed,
}

class NoteActionScopeRetired implements Exception {
  const NoteActionScopeRetired();
}

class NoteActionBusy implements Exception {
  const NoteActionBusy();
}

class NoteActionUnavailable implements Exception {
  const NoteActionUnavailable(this.issue);
  final NoteActionIssue issue;
}

class NoteActionState {
  const NoteActionState({
    required this.id,
    required this.memberId,
    required this.editorType,
    required this.pinned,
    required this.isPublic,
  });
  final int id, memberId;
  final String editorType;
  final bool pinned, isPublic;
}

class NotePinActionResult {
  const NotePinActionResult({
    required this.id,
    required this.property,
    required this.desired,
    required this.mutationAttempted,
    this.observed,
    this.issue,
    this.recoveredAfterFailure = false,
  });
  final int id;
  final NoteActionProperty property;
  final bool desired, mutationAttempted, recoveredAfterFailure;
  final NoteActionState? observed;
  final NoteActionIssue? issue;
  bool get confirmed =>
      issue == null &&
      observed != null &&
      (property == NoteActionProperty.pin
              ? observed!.pinned
              : observed!.isPublic) ==
          desired;
}

class NoteBatchPinResult {
  NoteBatchPinResult({
    required this.scope,
    required Set<int> requestedIds,
    required Set<int> verifiedIds,
    required Map<int, NoteActionIssue> issues,
    this.affected,
    this.mutationAttempted = false,
    this.recoveredAfterFailure = false,
  }) : requestedIds = Set.unmodifiable(requestedIds),
       verifiedIds = Set.unmodifiable(verifiedIds),
       issues = Map.unmodifiable(issues);
  final String scope;
  final Set<int> requestedIds, verifiedIds;
  final Map<int, NoteActionIssue> issues;
  final int? affected;
  final bool mutationAttempted, recoveredAfterFailure;
  Set<int> get remainingIds =>
      Set.unmodifiable(requestedIds.difference(verifiedIds));
}

/// Desired-state adapter for Go's non-idempotent toggle routes.
/// Fresh bounded metadata must include owner/id/type and both actual flags.
/// Current Go GetBlog lacks the two flags: production activation requires the
/// reviewed additive Go metadata fields. Missing fields fail closed here.
class NotePinActions {
  NotePinActions({
    required this.client,
    required this.memberId,
    required this.scope,
    this.isCurrent,
    this.requestDeadline = const Duration(seconds: 20),
    this.maxBatchIds = 500,
  }) {
    if (memberId <= 0 ||
        scope.isEmpty ||
        requestDeadline <= Duration.zero ||
        maxBatchIds <= 0 ||
        maxBatchIds > 500) {
      throw ArgumentError('Invalid owned note-action scope');
    }
  }
  final BookstarkClient client;
  final int memberId, maxBatchIds;
  final String scope;
  final bool Function()? isCurrent;
  final Duration requestDeadline;
  final _retired = Completer<void>();
  static final _active = <String, Set<int>>{};
  void retire() {
    if (!_retired.isCompleted) _retired.complete();
  }

  void _guard() {
    if (_retired.isCompleted || isCurrent?.call() == false) {
      throw const NoteActionScopeRetired();
    }
  }

  void _id(int id) {
    if (id <= 0) throw const FormatException('Positive note ID required');
  }

  Future<T> _bounded<T>(Future<T> Function(Future<void> abort) action) async {
    _guard();
    final abort = Completer<void>();
    final stop = Future.any<void>([abort.future, _retired.future]);
    try {
      final result = await action(stop).timeout(
        requestDeadline,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('Note action timed out');
        },
      );
      _guard();
      return result;
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<T> _own<T>(Set<int> ids, Future<T> Function() action) async {
    _guard();
    final active = _active.putIfAbsent(scope, () => {});
    if (ids.any(active.contains)) throw const NoteActionBusy();
    active.addAll(ids);
    try {
      return await action();
    } finally {
      active.removeAll(ids);
      if (active.isEmpty && identical(_active[scope], active)) {
        _active.remove(scope);
      }
    }
  }

  static const _formats = {
    'markdown',
    'html',
    'spreadsheet',
    'drawing',
    'mindmap',
    'richdoc',
    'presentation',
  };
  Future<NoteActionState> readState(int id) async {
    _id(id);
    _guard();
    final row = await _bounded(
      (abort) => client.articleMetadata(id, abortTrigger: abort),
    );
    _guard();
    if (row['blog_id'] != id ||
        row['member_id'] is! int ||
        (row['member_id'] as int) <= 0) {
      throw const NoteActionUnavailable(NoteActionIssue.invalidMetadata);
    }
    // GET allows admin read-through, but the toggle SQL only writes own rows.
    if (row['member_id'] != memberId) {
      throw const NoteActionUnavailable(NoteActionIssue.notOwner);
    }
    if (row['blog_type'] != 'note') {
      throw const NoteActionUnavailable(NoteActionIssue.wrongType);
    }
    final pin = row['is_pinned'],
        visibility = row['visibility'],
        format = row['editor_type'];
    if (pin is! int ||
        !{0, 1}.contains(pin) ||
        visibility is! int ||
        !{0, 1}.contains(visibility) ||
        format is! String ||
        !_formats.contains(format)) {
      throw const NoteActionUnavailable(NoteActionIssue.invalidMetadata);
    }
    return NoteActionState(
      id: id,
      memberId: memberId,
      editorType: format,
      pinned: pin == 1,
      isPublic: visibility == 1,
    );
  }

  Future<NotePinActionResult> setPinned(int id, bool desired) =>
      _set(id, NoteActionProperty.pin, desired);
  Future<NotePinActionResult> setPublic(int id, bool desired) =>
      _set(id, NoteActionProperty.visibility, desired);
  Future<NotePinActionResult> _set(
    int id,
    NoteActionProperty property,
    bool desired,
  ) async {
    _id(id);
    return _own({id}, () async {
      final before = await readState(id);
      bool value(NoteActionState state) =>
          property == NoteActionProperty.pin ? state.pinned : state.isPublic;
      if (value(before) == desired) {
        return NotePinActionResult(
          id: id,
          property: property,
          desired: desired,
          mutationAttempted: false,
          observed: before,
        );
      }
      var failed = false;
      try {
        // Existing client requires a JSON object; Go toggle ignores the empty
        // object. Never send an invented target-value field.
        await _bounded(
          (abort) => client.mutate(
            'PATCH',
            '/api/blogs/$id/${property == NoteActionProperty.pin ? 'pin' : 'visibility'}',
            const {},
            abortTrigger: abort,
            beforeSubmit: _guard,
          ),
        );
      } on NoteActionScopeRetired {
        rethrow;
      } on ApiFailure catch (error) {
        if (error.status == 401 || error.status == 403) rethrow;
        failed = true;
      } catch (_) {
        failed = true;
      }
      _guard();
      try {
        // One readonly reconciliation, even after timeout or lost response.
        // Never resend this toggle automatically.
        final after = await readState(id);
        return NotePinActionResult(
          id: id,
          property: property,
          desired: desired,
          mutationAttempted: true,
          observed: after,
          recoveredAfterFailure: failed,
          issue: value(after) == desired ? null : NoteActionIssue.unconfirmed,
        );
      } on NoteActionScopeRetired {
        rethrow;
      } on ApiFailure catch (error) {
        if (error.status == 401) rethrow;
        return NotePinActionResult(
          id: id,
          property: property,
          desired: desired,
          mutationAttempted: true,
          recoveredAfterFailure: failed,
          issue: _issue(error),
        );
      } catch (error) {
        return NotePinActionResult(
          id: id,
          property: property,
          desired: desired,
          mutationAttempted: true,
          recoveredAfterFailure: failed,
          issue: _issue(error),
        );
      }
    });
  }

  NoteActionIssue _issue(Object error) {
    if (error is NoteActionUnavailable) return error.issue;
    if (error is ApiFailure && error.status == 403) {
      return NoteActionIssue.forbidden;
    }
    if (error is ApiFailure && error.status == 404) {
      return NoteActionIssue.notFound;
    }
    if (error is FormatException) return NoteActionIssue.invalidMetadata;
    return NoteActionIssue.unknown;
  }

  Future<NoteBatchPinResult> pinSelected(Iterable<int> selectedIds) async {
    final ids = Set<int>.of(selectedIds);
    if (ids.isEmpty || ids.length > maxBatchIds) {
      throw const FormatException(
        'Explicit selected IDs exceed this action budget',
      );
    }
    for (final id in ids) {
      _id(id);
    }
    return _own(ids, () async {
      final verified = <int>{},
          toPin = <int>{},
          issues = <int, NoteActionIssue>{};
      for (final id in ids) {
        _guard();
        try {
          final before = await readState(id);
          if (before.pinned) {
            verified.add(id);
          } else {
            toPin.add(id);
          }
        } on NoteActionScopeRetired {
          rethrow;
        } on ApiFailure catch (error) {
          if (error.status == 401) rethrow;
          issues[id] = _issue(error);
        } catch (error) {
          issues[id] = _issue(error);
        }
      }
      int? affected;
      var failed = false;
      if (toPin.isNotEmpty) {
        try {
          final response = await _bounded(
            (abort) => client.mutate(
              'POST',
              '/api/blogs/batch-pin',
              {'ids': toPin.toList()..sort()},
              abortTrigger: abort,
              beforeSubmit: _guard,
            ),
          );
          // BookstarkClient.post unwraps an object-valued data envelope.
          final count = response['affected'];
          if (count is int && count >= 0 && count <= toPin.length) {
            affected = count;
          } else {
            failed = true;
          }
        } on NoteActionScopeRetired {
          rethrow;
        } on ApiFailure catch (error) {
          if (error.status == 401) rethrow;
          if (error.status == 403) {
            for (final id in toPin) {
              issues[id] = NoteActionIssue.forbidden;
            }
            return NoteBatchPinResult(
              scope: scope,
              requestedIds: ids,
              verifiedIds: verified,
              issues: issues,
              mutationAttempted: true,
            );
          }
          failed = true;
        } catch (_) {
          failed = true;
        }
        for (final id in toPin) {
          _guard();
          try {
            final after = await readState(id);
            if (after.pinned) {
              verified.add(id);
            } else {
              issues[id] = NoteActionIssue.unconfirmed;
            }
          } on NoteActionScopeRetired {
            rethrow;
          } on ApiFailure catch (error) {
            if (error.status == 401) rethrow;
            issues[id] = _issue(error);
          } catch (error) {
            issues[id] = _issue(error);
          }
        }
      }
      _guard();
      return NoteBatchPinResult(
        scope: scope,
        requestedIds: ids,
        verifiedIds: verified,
        issues: issues,
        affected: affected,
        mutationAttempted: toPin.isNotEmpty,
        recoveredAfterFailure: failed,
      );
    });
  }
}
