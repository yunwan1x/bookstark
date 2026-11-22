import 'dart:async';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_repository.dart';
import 'admin_assets_scope.dart';
import 'admin_terminal_controller.dart';
import 'admin_terminal_protocol.dart';
import 'admin_terminal_transport.dart';
import 'admin_terminal_session_access.dart';

/// The reviewed metadata is fixed. A changed target requires a new review page.
class AdminTerminalAccess implements AdminTerminalSessionAccess {
  AdminTerminalAccess(this.scope, this.host)
    : repository = AdminAssetsRepository(scope.client);
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final AdminAssetsRepository repository;
  @override
  int scrollbackLines = 5000;
  bool _disposed = false;
  Completer<void>? _abort;
  void cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<void> verifyOwner() async {
    if (_disposed || !scope.guard()) {
      throw const TerminalException(TerminalFailure.unauthorized);
    }
    try {
      final profile = await scope.client.adminAssetPrincipalJson(
        abortTrigger: _abort?.future,
      );
      if (_disposed ||
          !scope.guard() ||
          profile['member_id'] != scope.owner.memberId ||
          profile['account'] != scope.owner.account ||
          profile['role'] != 0) {
        throw const TerminalException(TerminalFailure.unauthorized);
      }
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        throw const TerminalException(TerminalFailure.unauthorized);
      }
      throw const TerminalException(TerminalFailure.network);
    }
  }

  Future<void> prepare() async {
    cancel();
    final abort = Completer<void>();
    _abort = abort;
    try {
      final settings = await repository.readSettings(
        scope.owner,
        abortTrigger: abort.future,
      );
      final hosts = await repository.readHosts(
        scope.owner,
        abortTrigger: abort.future,
      );
      AdminAssetHostMetadata? fresh;
      for (final row in hosts) {
        if (row.id == host.id) fresh = row;
      }
      if (fresh == null || fresh.reviewFingerprint != host.reviewFingerprint) {
        throw const TerminalException(TerminalFailure.targetChanged);
      }
      await verifyOwner();
      scrollbackLines = settings.scrollbackLines;
    } on AdminAssetOwnerLost {
      throw const TerminalException(TerminalFailure.unauthorized);
    } on ApiFailure catch (error) {
      throw TerminalException(
        {401, 403}.contains(error.status)
            ? TerminalFailure.unauthorized
            : TerminalFailure.network,
      );
    }
  }

  @override
  AdminTerminalController create({
    TerminalTransport Function()? transportFactory,
  }) => AdminTerminalController(
    endpoint: terminalEndpoint(scope.client.baseUri, host.id),
    token: scope.client.exportSession()['token'],
    ownerActive: () => !_disposed && scope.guard(),
    prepare: prepare,
    verifyOwner: verifyOwner,
    onRetire: cancel,
    transportFactory: transportFactory,
  );
  @override
  void dispose() {
    _disposed = true;
    cancel();
    repository.dispose();
  }
}
