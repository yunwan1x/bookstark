import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'share_settings_repository.dart';

enum ShareSettingsPhase { idle, loading, ready, writing, failed, unknown }

/// No disk drafts or implicit writes. Unknown mutations require explicit recovery.
class ShareSettingsController extends ChangeNotifier {
  ShareSettingsController(this.repository, this.target);
  final ShareSettingsRepository repository;
  final OwnerShareTarget target;
  ShareSettingsPhase phase = ShareSettingsPhase.idle;
  bool? published;
  bool? observedAfterUnknown;
  OwnerShareReceipt? receipt;
  bool _closed = false;
  int _generation = 0;
  bool get busy =>
      phase == ShareSettingsPhase.loading ||
      phase == ShareSettingsPhase.writing;
  bool get uncertain => phase == ShareSettingsPhase.unknown;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (_closed || busy || uncertain) {
      return;
    }
    final generation = ++_generation;
    receipt = null;
    published = null;
    phase = ShareSettingsPhase.loading;
    _emit();
    try {
      final value = await repository.status(target);
      if (_closed || generation != _generation) {
        return;
      }
      published = value;
      phase = ShareSettingsPhase.ready;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      phase = ShareSettingsPhase.failed;
    }
    _emit();
  }

  Future<void> publish({bool acknowledgeUnknown = false}) async {
    if (_closed || busy || uncertain && !acknowledgeUnknown) {
      return;
    }
    await _write(() async {
      final actual = await repository.publish(target);
      return (true, actual);
    });
  }

  Future<void> changeToken(ShareTokenAction action) async {
    final current = receipt;
    if (_closed ||
        busy ||
        uncertain ||
        current == null ||
        !target.supportsEditing) {
      return;
    }
    // Hide the old capability before sending any reset/disable/enable request.
    receipt = current.withoutToken();
    await _write(
      () async => (true, await repository.changeToken(target, current, action)),
    );
  }

  Future<void> unpublish({bool acknowledgeUnknown = false}) async {
    if (_closed || busy || uncertain && !acknowledgeUnknown) {
      return;
    }
    receipt = null;
    await _write(() async {
      await repository.unpublish(target);
      return (false, null);
    });
  }

  Future<void> _write(
    Future<(bool, OwnerShareReceipt?)> Function() operation,
  ) async {
    final generation = ++_generation;
    phase = ShareSettingsPhase.writing;
    observedAfterUnknown = null;
    _emit();
    try {
      final value = await operation();
      if (_closed || generation != _generation) {
        return;
      }
      published = value.$1;
      receipt = value.$2;
      phase = ShareSettingsPhase.ready;
    } catch (error) {
      if (_closed || generation != _generation) {
        return;
      }
      // A receipt/transport/5xx failure may follow an applied mutation.
      final rejected =
          error is ApiFailure &&
          error.status >= 400 &&
          error.status < 500 &&
          error.status != 408;
      phase = rejected ? ShareSettingsPhase.failed : ShareSettingsPhase.unknown;
      receipt = null;
    }
    _emit();
  }

  Future<void> inspectUnknown() async {
    if (_closed || !uncertain) {
      return;
    }
    final generation = ++_generation;
    try {
      final actual = await repository.status(target);
      if (_closed || generation != _generation) {
        return;
      }
      observedAfterUnknown = actual;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      observedAfterUnknown = null;
    }
    // A boolean never proves which edit token is current. Do not unlock writes.
    _emit();
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    receipt = null;
    super.dispose();
  }
}
