import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'profile_repository.dart';

enum ProfileEditPhase {
  ready,
  checking,
  saving,
  failed,
  unknown,
  unverified,
  conflict,
  confirmed,
}

class ProfileEditController extends ChangeNotifier {
  ProfileEditController(this.repository, this.baseline);
  final ProfileRepository repository;
  MemberProfile baseline;
  MemberProfile? observed;
  ProfileDraft? submitted;
  ProfileEditPhase phase = ProfileEditPhase.ready;
  bool receivedWriteReceipt = false;
  bool _closed = false;
  int _generation = 0;
  bool get busy =>
      phase == ProfileEditPhase.checking || phase == ProfileEditPhase.saving;
  bool get unresolved =>
      phase == ProfileEditPhase.unknown || phase == ProfileEditPhase.unverified;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> save(
    ProfileDraft draft, {
    MemberProfile? overwriteObserved,
  }) async {
    if (_closed ||
        busy ||
        unresolved ||
        phase == ProfileEditPhase.conflict && overwriteObserved == null) {
      return;
    }
    draft.validate();
    if (overwriteObserved != null &&
        (observed == null ||
            !overwriteObserved.sameEditableFields(observed!))) {
      throw StateError('An observed conflict is required');
    }
    final generation = ++_generation;
    submitted = draft;
    receivedWriteReceipt = false;
    phase = ProfileEditPhase.checking;
    _emit();
    final MemberProfile fresh;
    try {
      fresh = await repository.read();
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      phase = ProfileEditPhase.failed;
      _emit();
      return;
    }
    if (_closed || generation != _generation) {
      return;
    }
    if (fresh.id != baseline.id) {
      phase = ProfileEditPhase.failed;
      _emit();
      return;
    }
    if (draft.matches(fresh)) {
      baseline = fresh;
      observed = null;
      phase = ProfileEditPhase.confirmed;
      _emit();
      return;
    }
    if (!fresh.sameEditableFields(overwriteObserved ?? baseline)) {
      observed = fresh;
      phase = ProfileEditPhase.conflict;
      _emit();
      return;
    }
    phase = ProfileEditPhase.saving;
    _emit();
    try {
      await repository.update(draft);
      if (_closed || generation != _generation) {
        return;
      }
      receivedWriteReceipt = true;
      phase = ProfileEditPhase.unverified;
    } catch (error) {
      if (_closed || generation != _generation) {
        return;
      }
      final rejected =
          error is ApiFailure &&
          error.status >= 400 &&
          error.status < 500 &&
          error.status != 408;
      phase = rejected ? ProfileEditPhase.failed : ProfileEditPhase.unknown;
      _emit();
      return;
    }
    _emit();
    await inspect();
  }

  Future<void> inspect() async {
    final desired = submitted;
    if (_closed || busy || desired == null || !unresolved) {
      return;
    }
    final generation = ++_generation;
    try {
      final fresh = await repository.read();
      if (_closed || generation != _generation) {
        return;
      }
      if (fresh.id != baseline.id) {
        _emit();
        return;
      }
      if (desired.matches(fresh)) {
        baseline = fresh;
        observed = null;
        phase = ProfileEditPhase.confirmed;
      } else {
        observed = fresh;
        phase = ProfileEditPhase.conflict;
      }
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
    }
    _emit();
  }

  MemberProfile useObserved() {
    if (_closed ||
        busy ||
        phase != ProfileEditPhase.conflict ||
        observed == null) {
      throw StateError('No observed profile');
    }
    baseline = observed!;
    observed = null;
    submitted = null;
    phase = ProfileEditPhase.ready;
    _emit();
    return baseline;
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    submitted = null;
    observed = null;
    super.dispose();
  }
}
