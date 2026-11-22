import 'dart:async';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_scope.dart';
import 'admin_assets_repository.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';
import 'admin_terminal_controller.dart';
import 'admin_terminal_protocol.dart';
import 'admin_terminal_transport.dart';
import 'admin_terminal_session_access.dart';

class DockerTerminalAccess implements AdminTerminalSessionAccess {
  DockerTerminalAccess(
    this.scope,
    this.host,
    this.container, {
    AdminAssetCredentialMetadata? credential,
  }) : repository = AdminDockerRepository(scope, host, credential: credential);
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final DockerInspect container;
  final AdminDockerRepository repository;
  @override
  int scrollbackLines = 5000;
  Completer<void>? _abort;
  bool _disposed = false;
  void cancel() {
    repository.cancel();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<void> _translate(Future<void> Function() task) async {
    try {
      if (_disposed || !scope.guard()) throw AdminAssetOwnerLost();
      await task();
    } on AdminAssetOwnerLost {
      throw const TerminalException(TerminalFailure.unauthorized);
    } on AdminAssetTargetChanged {
      throw const TerminalException(TerminalFailure.targetChanged);
    } on ApiFailure catch (error) {
      throw TerminalException(
        {401, 403}.contains(error.status)
            ? TerminalFailure.unauthorized
            : TerminalFailure.network,
      );
    }
  }

  Future<void> prepare() => _translate(() async {
    cancel();
    final abort = Completer<void>();
    _abort = abort;
    await repository.verifyContainer(container);
    final settings = await repository.assets.readSettings(
      scope.owner,
      abortTrigger: abort.future,
    );
    if (_disposed || abort.isCompleted) {
      throw const TerminalException(TerminalFailure.closed);
    }
    scrollbackLines = settings.scrollbackLines;
    await repository.verifyContainer(container);
  });
  Future<void> verifyOwner() => _translate(() => repository.verifyOwner());
  @override
  AdminTerminalController create({
    TerminalTransport Function()? transportFactory,
  }) {
    final base = scope.client.baseUri;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(container.id)) {
      throw const TerminalException(TerminalFailure.protocol);
    }
    final endpoint = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path:
          '${base.path}/api/admin/assets/ssh-hosts/${host.id}/docker-containers/${container.id}/terminal',
    );
    return AdminTerminalController(
      endpoint: endpoint,
      token: scope.client.exportSession()['token'],
      ownerActive: () => !_disposed && scope.guard(),
      prepare: prepare,
      verifyOwner: verifyOwner,
      onRetire: cancel,
      transportFactory: transportFactory,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    repository.dispose();
  }
}
