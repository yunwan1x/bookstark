import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'background_repository.dart';

enum BackgroundPhase {
  ready,
  checking,
  saving,
  failed,
  unknown,
  unverified,
  conflict,
  confirmed,
}

class BackgroundController extends ChangeNotifier {
  BackgroundController(this.repository, this.baseline);
  final BackgroundRepository repository;
  BackgroundPreference baseline;
  BackgroundPreference? observed, receipt;
  BackgroundDraft? submitted;
  Uint8List? verifiedImage;
  BackgroundPhase phase = BackgroundPhase.ready;
  bool inspecting = false, _closed = false;
  int _generation = 0;
  bool get busy =>
      inspecting ||
      phase == BackgroundPhase.checking ||
      phase == BackgroundPhase.saving;
  bool get unresolved =>
      phase == BackgroundPhase.unknown || phase == BackgroundPhase.unverified;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> save(BackgroundDraft draft) async {
    if (_closed || busy || unresolved || phase == BackgroundPhase.conflict) {
      return;
    }
    draft.validate(baseline);
    final g = ++_generation;
    submitted = draft;
    receipt = null;
    verifiedImage = null;
    phase = BackgroundPhase.checking;
    _emit();
    late BackgroundPreference fresh;
    try {
      fresh = await repository.read();
    } catch (_) {
      if (!_closed && g == _generation) {
        phase = BackgroundPhase.failed;
        _emit();
      }
      return;
    }
    if (_closed || g != _generation) {
      return;
    }
    if (!fresh.same(baseline)) {
      observed = fresh;
      phase = BackgroundPhase.conflict;
      _emit();
      return;
    }
    phase = BackgroundPhase.saving;
    _emit();
    try {
      final result = await repository.update(draft);
      if (_closed || g != _generation) {
        return;
      }
      receipt = result;
      phase = BackgroundPhase.unverified;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      final rejected =
          e is BackgroundPreflightFailure ||
          e is ApiFailure &&
              e.status >= 400 &&
              e.status < 500 &&
              e.status != 408;
      phase = rejected ? BackgroundPhase.failed : BackgroundPhase.unknown;
      _emit();
      return;
    }
    _emit();
    await inspect();
  }

  Future<void> inspect() async {
    final draft = submitted;
    if (_closed || busy || !unresolved || draft == null) {
      return;
    }
    final g = ++_generation;
    inspecting = true;
    _emit();
    try {
      final fresh = await repository.read();
      if (_closed || g != _generation) {
        return;
      }
      // A lost upload receipt cannot prove that a newly observed image is ours.
      // Keep it as observed state; never resend the original file automatically.
      final matches =
          draft.matches(fresh, uploadedHash: receipt?.imageHash) &&
          (receipt == null || receipt!.same(fresh)) &&
          (draft.image != null ||
              draft.remove ||
              fresh.imageHash == baseline.imageHash);
      if (!matches) {
        observed = fresh;
        phase = BackgroundPhase.conflict;
      } else {
        Uint8List? bytes;
        if (fresh.imageHash.isNotEmpty &&
            (fresh.mode == 'image' || draft.image != null)) {
          bytes = await repository.image(fresh.imageHash);
        }
        if (_closed || g != _generation) {
          return;
        }
        verifiedImage = bytes;
        baseline = fresh;
        observed = null;
        phase = BackgroundPhase.confirmed;
      }
    } catch (_) {
      if (_closed || g != _generation) {
        return;
      }
    } finally {
      if (!_closed && g == _generation) {
        inspecting = false;
        _emit();
      }
    }
  }

  BackgroundPreference useObserved() {
    if (_closed ||
        busy ||
        phase != BackgroundPhase.conflict ||
        observed == null) {
      throw StateError('No observed background');
    }
    baseline = observed!;
    observed = null;
    receipt = null;
    submitted = null;
    verifiedImage = null;
    phase = BackgroundPhase.ready;
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
    verifiedImage = null;
    submitted = null;
    observed = null;
    receipt = null;
    super.dispose();
  }
}
