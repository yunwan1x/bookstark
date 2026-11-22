import 'dart:async';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_repository.dart';
import 'admin_assets_scope.dart';
import 'admin_remote_dav_models.dart';

enum AdminDavMutation { create, update, delete, test }

final class AdminDavReview {
  AdminDavReview._(this.action, this.server, this.draft, this.credential);
  final AdminDavMutation action;
  final AdminDavServer? server;
  final AdminDavDraft? draft;
  final AdminAssetCredentialMetadata credential;
}

final class AdminDavBinding {
  const AdminDavBinding(this.server, this.credential);
  final AdminDavServer server;
  final AdminAssetCredentialMetadata credential;
}

final class AdminDavUnconfirmed {
  AdminDavUnconfirmed(AdminDavReview plan)
    : action = plan.action,
      serverId = plan.server?.id;
  final AdminDavMutation action;
  final int? serverId;
  bool catalogObserved = false;
}

final class AdminDavTestReceipt {
  AdminDavTestReceipt(this.status, this.checked);
  final AdminAssetStatus status;
  final AdminAssetTimestamp checked;
}

/// Owns metadata only. All requests target BookStark, never the remote URL.
class AdminDavRepository {
  AdminDavRepository(this.scope) : assets = AdminAssetsRepository(scope.client);
  final AdminAssetsScope scope;
  final AdminAssetsRepository assets;
  Completer<void>? _abort;
  bool _disposed = false, _busy = false;
  int _generation = 0;
  AdminDavReview? _review;
  AdminDavUnconfirmed? unknown;
  bool get active => !_disposed && scope.active;

  void _guard() {
    if (!active || !scope.guard()) throw AdminAssetOwnerLost();
    if (_abort?.isCompleted == true) throw AdminAssetReadSuperseded();
  }

  Future<void> _verify() async {
    _guard();
    final raw = await scope.client.adminAssetPrincipalJson(
      abortTrigger: _abort?.future,
    );
    _guard();
    final principal = raw;
    if (principal['member_id'] != scope.owner.memberId ||
        principal['account'] != scope.owner.account ||
        principal['role'] != 0) {
      scope.close();
      throw AdminAssetOwnerLost();
    }
  }

  Future<T> _operation<T>(Future<T> Function() action) async {
    _guard();
    if (_busy) throw const AdminAssetOperationBusy();
    _busy = true;
    final abort = Completer<void>(), generation = _generation;
    _abort = abort;
    try {
      await _verify();
      final result = await action();
      _guard();
      if (generation != _generation) throw AdminAssetReadSuperseded();
      return result;
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      rethrow;
    } on AdminAssetOwnerLost {
      scope.close();
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
      _busy = false;
    }
  }

  Future<List<AdminDavConnection>> _catalog({
    String query = '',
    AdminAssetStatus? status,
  }) async {
    final raw = await scope.client.adminDavServersJson(
      query: query,
      status: status?.value,
      abortTrigger: _abort?.future,
    );
    _guard();
    final data = raw['data'];
    if (data is! List) throw const FormatException('Invalid DAV catalog');
    final rows = <AdminDavConnection>[];
    final ids = <Object>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid DAV connection');
      }
      final row = AdminDavConnection.parse(item);
      final id = row is AdminDavServer ? row.id : 'local';
      if (!ids.add(id)) throw const FormatException('Duplicate DAV connection');
      rows.add(row);
    }
    return List.unmodifiable(rows);
  }

  Future<List<AdminDavConnection>> list({
    String query = '',
    AdminAssetStatus? status,
  }) => _operation(() => _catalog(query: query, status: status));

  Future<List<AdminAssetCredentialMetadata>> credentials() =>
      _operation(() async {
        final rows = await assets.readCredentials(
          scope.owner,
          abortTrigger: _abort?.future,
        );
        _guard();
        return List.unmodifiable(
          rows.where((row) => row.auth == AdminAssetAuth.password),
        );
      });

  Future<AdminDavServer> _freshServer(AdminDavServer baseline) async {
    final rows = await _catalog();
    final matches = rows
        .whereType<AdminDavServer>()
        .where((row) => row.id == baseline.id)
        .toList();
    if (matches.length != 1 ||
        matches.single.fingerprint != baseline.fingerprint) {
      throw const AdminAssetTargetChanged();
    }
    return matches.single;
  }

  Future<AdminAssetCredentialMetadata> _credential(int id) async {
    final rows = await assets.readCredentials(
      scope.owner,
      abortTrigger: _abort?.future,
    );
    _guard();
    final matches = rows.where((row) => row.id == id).toList();
    if (matches.length != 1 || matches.single.auth != AdminAssetAuth.password) {
      throw const AdminAssetTargetChanged();
    }
    return matches.single;
  }

  Future<AdminDavBinding> bind(AdminDavServer server) => _operation(() async {
    final fresh = await _freshServer(server);
    final credential = await _credential(fresh.credentialId);
    return AdminDavBinding(fresh, credential);
  });

  Future<void> verifyBinding(AdminDavBinding binding) => _operation(() async {
    await _freshServer(binding.server);
    final current = await _credential(binding.credential.id);
    if (current.reviewFingerprint != binding.credential.reviewFingerprint) {
      throw const AdminAssetTargetChanged();
    }
  });

  Future<AdminDavReview> review(
    AdminDavMutation action, {
    AdminDavServer? server,
    AdminDavDraft? draft,
  }) => _operation(() async {
    if (unknown != null) throw const AdminAssetWriteUnknown();
    if ((action == AdminDavMutation.create) != (server == null) ||
        ({AdminDavMutation.create, AdminDavMutation.update}.contains(action)) !=
            (draft != null)) {
      throw const FormatException('Invalid DAV review');
    }
    if (server != null) await _freshServer(server);
    final credential = await _credential(
      draft?.credentialId ?? server!.credentialId,
    );
    final plan = AdminDavReview._(action, server, draft, credential);
    _review = plan;
    return plan;
  });

  Future<Object?> submit(AdminDavReview plan) => _operation(() async {
    if (unknown != null || !identical(plan, _review)) {
      throw const AdminAssetTargetChanged();
    }
    if (plan.server != null) await _freshServer(plan.server!);
    final credential = await _credential(plan.credential.id);
    if (credential.reviewFingerprint != plan.credential.reviewFingerprint) {
      throw const AdminAssetTargetChanged();
    }
    await _verify();
    _review =
        null; // Every confirmation is single-use even when dispatch is refused.
    var submitted = false;
    try {
      final raw = await scope.client.adminDavServersJson(
        operation: switch (plan.action) {
          AdminDavMutation.create || AdminDavMutation.update => 'save',
          AdminDavMutation.delete => 'delete',
          AdminDavMutation.test => 'test',
        },
        id: plan.server?.id,
        body: plan.draft?.json,
        abortTrigger: _abort?.future,
        onSubmitted: () => submitted = true,
      );
      _guard();
      if (plan.action == AdminDavMutation.delete) return null;
      final data = Map<String, dynamic>.from(raw);
      if (plan.action == AdminDavMutation.test) {
        // Do not retain message: Go may put an upstream credential-bearing URL in it.
        return AdminDavTestReceipt(
          AdminAssetStatus.parse(data['status']),
          AdminAssetTimestamp.parse(data['checked_at']),
        );
      }
      final saved = AdminDavServer.parse(data);
      if (plan.server != null && saved.id != plan.server!.id ||
          saved.name != plan.draft!.name ||
          saved.url != plan.draft!.url ||
          saved.root != plan.draft!.root ||
          saved.credentialId != plan.draft!.credentialId) {
        throw const FormatException('DAV saved metadata differs from review');
      }
      return saved;
    } catch (error) {
      if (!active) throw AdminAssetOwnerLost();
      if (error is ApiFailure && {401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      if (submitted &&
          !(error is ApiFailure && error.status >= 400 && error.status < 500)) {
        unknown = AdminDavUnconfirmed(plan);
        throw const AdminAssetWriteUnknown();
      }
      rethrow;
    }
  });

  /// A fresh catalog is an observation, never a receipt for an unknown mutation.
  Future<List<AdminDavConnection>> observeUnknown() => _operation(() async {
    final held = unknown;
    if (held == null) throw const AdminAssetTargetChanged();
    final rows = await _catalog();
    if (!identical(held, unknown)) throw const AdminAssetTargetChanged();
    held.catalogObserved = true;
    return rows;
  });

  void finishUnknownReview() {
    _guard();
    if (unknown?.catalogObserved != true || _busy) {
      throw const AdminAssetTargetChanged();
    }
    unknown = null;
    _review = null;
  }

  void background() {
    _generation++;
    if (_abort?.isCompleted == false) _abort!.complete();
    _review = null;
    unknown?.catalogObserved = false;
    assets.closeSecrets();
  }

  void dispose() {
    if (_disposed) return;
    background();
    _disposed = true;
    assets.dispose();
  }
}
