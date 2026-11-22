import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'reminder_repository.dart';

enum ReminderPhase {
  ready,
  checking,
  saving,
  failed,
  unknown,
  unverified,
  conflict,
  confirmed,
}

enum ReminderMailPhase {
  ready,
  sending,
  acknowledged,
  rejected,
  limited,
  unknown,
}

class ReminderController extends ChangeNotifier {
  ReminderController(this.repository, this.baseline);
  final ReminderRepository repository;
  ReminderSettings baseline;
  ReminderSettings? observed;
  ReminderDraft? submitted;
  ReminderPhase phase = ReminderPhase.ready;
  ReminderMailPhase mailPhase = ReminderMailPhase.ready;
  bool receivedReceipt = false, _closed = false;
  int _generation = 0;
  bool get busy =>
      phase == ReminderPhase.checking ||
      phase == ReminderPhase.saving ||
      mailPhase == ReminderMailPhase.sending;
  bool get unresolved =>
      phase == ReminderPhase.unknown || phase == ReminderPhase.unverified;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  bool _rejected(Object e) =>
      e is ReminderPreflightFailure ||
      e is ApiFailure && e.status >= 400 && e.status < 500 && e.status != 408;
  Future<void> save(ReminderDraft draft) async {
    if (_closed || busy || unresolved || phase == ReminderPhase.conflict) {
      return;
    }
    draft.validate();
    final g = ++_generation;
    submitted = draft;
    receivedReceipt = false;
    phase = ReminderPhase.checking;
    _emit();
    late ReminderSettings fresh;
    try {
      fresh = await repository.read();
    } catch (_) {
      if (!_closed && g == _generation) {
        phase = ReminderPhase.failed;
        _emit();
      }
      return;
    }
    if (_closed || g != _generation) {
      return;
    }
    if (draft.same(fresh.preferences)) {
      baseline = fresh;
      phase = ReminderPhase.confirmed;
      _emit();
      return;
    }
    if (!baseline.sameContext(fresh)) {
      observed = fresh;
      phase = ReminderPhase.conflict;
      _emit();
      return;
    }
    if (draft.enabled && (!fresh.available || fresh.email.isEmpty)) {
      phase = ReminderPhase.failed;
      _emit();
      return;
    }
    phase = ReminderPhase.saving;
    _emit();
    try {
      await repository.update(draft);
      if (_closed || g != _generation) {
        return;
      }
      receivedReceipt = true;
      phase = ReminderPhase.unverified;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      phase = _rejected(e) ? ReminderPhase.failed : ReminderPhase.unknown;
      _emit();
      return;
    }
    _emit();
    await inspect();
  }

  Future<void> inspect() async {
    if (_closed || busy || !unresolved || submitted == null) {
      return;
    }
    final g = ++_generation;
    try {
      final fresh = await repository.read();
      if (_closed || g != _generation) {
        return;
      }
      if (submitted!.same(fresh.preferences)) {
        baseline = fresh;
        observed = null;
        phase = ReminderPhase.confirmed;
      } else {
        observed = fresh;
        phase = ReminderPhase.conflict;
      }
    } catch (_) {
      if (_closed || g != _generation) {
        return;
      }
    }
    _emit();
  }

  ReminderSettings useObserved() {
    if (_closed ||
        busy ||
        phase != ReminderPhase.conflict ||
        observed == null) {
      throw StateError('No observed reminder settings');
    }
    baseline = observed!;
    observed = null;
    submitted = null;
    phase = ReminderPhase.ready;
    _emit();
    return baseline;
  }

  Future<void> sendTest(String confirmedEmail) async {
    if (_closed || busy) {
      return;
    }
    final g = ++_generation;
    mailPhase = ReminderMailPhase.sending;
    _emit();
    try {
      await repository.sendTest(confirmedEmail);
      if (_closed || g != _generation) {
        return;
      }
      mailPhase = ReminderMailPhase.acknowledged;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      mailPhase = e is ApiFailure && e.status == 429
          ? ReminderMailPhase.limited
          : _rejected(e)
          ? ReminderMailPhase.rejected
          : ReminderMailPhase.unknown;
    }
    _emit();
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
