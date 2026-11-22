import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_repository.dart';
import 'admin_remote_dav_models.dart';
import 'admin_remote_dav_repository.dart';

enum AdminDavFailure { read, changed, refused, unknown, ownerLost, background }

class AdminDavController extends ChangeNotifier {
  AdminDavController(this.repository);
  final AdminDavRepository repository;
  List<AdminDavConnection>? rows;
  List<AdminAssetCredentialMetadata>? credentialRows;
  AdminDavReview? review;
  AdminDavServer? saved;
  AdminDavTestReceipt? tested;
  AdminDavMutation? receipt;
  AdminDavFailure? failure;
  bool busy = false, suspended = false, disposed = false;
  int _epoch = 0;
  bool get active => !disposed && repository.active;
  bool get canAct =>
      active && !busy && !suspended && repository.unknown == null;
  bool get canRead => active && !busy;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  void _error(Object error) {
    failure = switch (error) {
      AdminAssetOwnerLost() => AdminDavFailure.ownerLost,
      AdminAssetTargetChanged() => AdminDavFailure.changed,
      AdminAssetWriteUnknown() => AdminDavFailure.unknown,
      ApiFailure(:final status) when status >= 400 && status < 500 =>
        AdminDavFailure.refused,
      _ => AdminDavFailure.read,
    };
    review = null;
    if (failure == AdminDavFailure.ownerLost ||
        failure == AdminDavFailure.unknown) {
      rows = null;
      credentialRows = null;
      saved = null;
      tested = null;
      receipt = null;
    }
  }

  Future<bool> _run(Future<void> Function(int) work) async {
    if (!active || busy) return false;
    final epoch = _epoch;
    busy = true;
    failure = null;
    _notify();
    try {
      await work(epoch);
      return !disposed && epoch == _epoch;
    } catch (error) {
      if (!disposed && epoch == _epoch) _error(error);
      return false;
    } finally {
      if (!disposed) {
        busy = false;
        _notify();
      }
    }
  }

  bool _current(int epoch) => !disposed && epoch == _epoch && repository.active;

  Future<bool> load({String query = '', AdminAssetStatus? status}) async {
    if (!canRead || repository.unknown != null) return false;
    suspended = false;
    rows = null;
    return _run((epoch) async {
      final value = await repository.list(query: query, status: status);
      if (_current(epoch)) rows = value;
    });
  }

  Future<bool> loadCredentials() async {
    if (!canAct) return false;
    credentialRows = null;
    return _run((epoch) async {
      final value = await repository.credentials();
      if (_current(epoch)) credentialRows = value;
    });
  }

  Future<bool> prepare(
    AdminDavMutation action, {
    AdminDavServer? server,
    AdminDavDraft? draft,
  }) async {
    if (!canAct) return false;
    review = null;
    receipt = null;
    saved = null;
    tested = null;
    return _run((epoch) async {
      final value = await repository.review(
        action,
        server: server,
        draft: draft,
      );
      if (_current(epoch)) review = value;
    });
  }

  void cancelReview() {
    if (busy || disposed) return;
    review = null;
    _notify();
  }

  Future<bool> submit() async {
    final held = review;
    if (!canAct || held == null) return false;
    review = null;
    receipt = null;
    saved = null;
    tested = null;
    return _run((epoch) async {
      final value = await repository.submit(held);
      if (!_current(epoch)) return;
      receipt = held.action;
      if (value is AdminDavServer) saved = value;
      if (value is AdminDavTestReceipt) tested = value;
      // Read again is explicit; a later failed GET is not a failed write.
    });
  }

  Future<AdminDavBinding?> bind(AdminDavServer server) async {
    if (!canAct) return null;
    AdminDavBinding? result;
    final ok = await _run((epoch) async {
      final value = await repository.bind(server);
      if (_current(epoch)) result = value;
    });
    return ok ? result : null;
  }

  Future<bool> observeUnknown() async {
    if (!canRead || suspended || repository.unknown == null) return false;
    rows = null;
    return _run((epoch) async {
      final value = await repository.observeUnknown();
      if (_current(epoch)) rows = value;
    });
  }

  void finishUnknownReview() {
    if (!canRead || suspended || rows == null) return;
    repository.finishUnknownReview();
    failure = null;
    receipt = null;
    _notify();
  }

  void background() {
    if (disposed) return;
    _epoch++;
    suspended = true;
    rows = null;
    credentialRows = null;
    review = null;
    saved = null;
    tested = null;
    receipt = null;
    failure = AdminDavFailure.background;
    repository.background();
    _notify();
  }

  @override
  void dispose() {
    if (disposed) return;
    _epoch++;
    disposed = true;
    rows = null;
    credentialRows = null;
    review = null;
    saved = null;
    tested = null;
    repository.dispose();
    super.dispose();
  }
}
