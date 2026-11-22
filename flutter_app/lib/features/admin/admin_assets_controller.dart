import 'admin_asset_secret_lease.dart';
import 'admin_asset_migration.dart';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import 'admin_asset_drafts.dart';
import 'admin_asset_models.dart';
import 'admin_asset_settings.dart';
import 'admin_assets_repository.dart';
import 'admin_settings_repository.dart';

enum AdminAssetCatalog { hosts, credentials, settings }

enum AdminAssetLoadState { idle, loading, ready, failed }

enum AdminAssetOperationState {
  idle,
  submitting,
  acknowledged,
  unknown,
  refused,
  changed,
  migrationRequired,
  ownerLost,
}

/// Safe view state only: no form input, response maps or raw server errors.
class AdminAssetsController extends ChangeNotifier {
  AdminAssetsController(this.repository, this.owner);
  final AdminAssetsRepository repository;
  final AdminPrincipal owner;
  bool _disposed = false;
  int _generation = 0;
  AdminAssetCatalog? unknownReviewCatalog;
  AdminAssetCatalog? lastUnconfirmedOperation;
  final _loads = {
    for (final kind in AdminAssetCatalog.values) kind: AdminAssetLoadState.idle,
  };
  AdminAssetOperationState operation = AdminAssetOperationState.idle;
  List<AdminAssetHostMetadata>? hosts;
  List<AdminAssetCredentialMetadata>? credentials;
  AdminAssetSettingsMetadata? settings;
  AdminAssetConnectionReceipt? connectionReceipt;
  int? testedHostId;
  AdminAssetDeleteReceipt? deleteReceipt;
  AdminAssetSettingsReceipt? settingsReceipt;
  AdminAssetHostMetadata? savedHost;
  AdminAssetCredentialMetadata? savedCredential;
  List<int> migrationHostIds = const [];
  AdminAssetMigrationPlan? migrationPlan;
  AdminAssetMigrationCreated? migrationCreated;
  AdminAssetMigrationBound? migrationBound;
  bool preparingMigration = false, migrationRetired = false;
  bool get migrationPartial =>
      migrationCreated != null && migrationBound == null;
  String appliedQuery = '';
  AdminAssetStatus? appliedStatus;

  bool get closed =>
      _disposed || operation == AdminAssetOperationState.ownerLost;
  bool get canWrite =>
      !preparingMigration &&
      !closed &&
      operation != AdminAssetOperationState.submitting &&
      operation != AdminAssetOperationState.unknown;
  AdminAssetLoadState loadState(AdminAssetCatalog kind) => _loads[kind]!;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearData() {
    hosts = null;
    credentials = null;
    settings = null;
    migrationPlan = null;
    migrationCreated = null;
    migrationBound = null;
    preparingMigration = false;
    migrationRetired = false;
    connectionReceipt = null;
    testedHostId = null;
    deleteReceipt = null;
    settingsReceipt = null;
    savedHost = null;
    savedCredential = null;
    migrationHostIds = const [];
    for (final kind in AdminAssetCatalog.values) {
      _loads[kind] = AdminAssetLoadState.idle;
    }
  }

  void _ownerLost() {
    _generation++;
    _clearData();
    repository.dispose();
    operation = AdminAssetOperationState.ownerLost;
  }

  bool _isOwnerError(Object e) =>
      e is AdminAssetOwnerLost ||
      e is ApiFailure && {401, 403}.contains(e.status);

  Future<bool> load(
    AdminAssetCatalog kind, {
    String query = '',
    AdminAssetStatus? status,
  }) async {
    if (closed || operation == AdminAssetOperationState.submitting) {
      return false;
    }
    final generation = _generation;
    _loads[kind] = AdminAssetLoadState.loading;
    switch (kind) {
      case AdminAssetCatalog.hosts:
        hosts = null;
      case AdminAssetCatalog.credentials:
        credentials = null;
      case AdminAssetCatalog.settings:
        settings = null;
    }
    _notify();
    try {
      switch (kind) {
        case AdminAssetCatalog.hosts:
          final rows = await repository.readHosts(
            owner,
            query: query,
            status: status,
          );
          if (_disposed || generation != _generation) return false;
          hosts = rows;
          appliedQuery = repository.reviewedHostQuery!;
          appliedStatus = status;
        case AdminAssetCatalog.credentials:
          final rows = await repository.readCredentials(owner);
          if (_disposed || generation != _generation) return false;
          credentials = rows;
        case AdminAssetCatalog.settings:
          final value = await repository.readSettings(owner);
          if (_disposed || generation != _generation) return false;
          settings = value;
      }
      _loads[kind] = AdminAssetLoadState.ready;
      _notify();
      return true;
    } catch (error) {
      if (_disposed ||
          generation != _generation ||
          error is AdminAssetReadSuperseded) {
        return false;
      }
      if (_isOwnerError(error)) {
        _ownerLost();
      } else {
        _loads[kind] = AdminAssetLoadState.failed;
      }
      _notify();
      return false;
    }
  }

  Future<bool> _write(
    Future<void> Function() action, {
    AdminAssetCatalog reviewCatalog = AdminAssetCatalog.hosts,
  }) async {
    if (!canWrite) return false;
    _generation++;
    operation = AdminAssetOperationState.submitting;
    connectionReceipt = null;
    testedHostId = null;
    deleteReceipt = null;
    settingsReceipt = null;
    savedHost = null;
    savedCredential = null;
    migrationHostIds = const [];
    _notify();
    try {
      await action();
      if (_disposed) return false;
      operation = AdminAssetOperationState.acknowledged;
      unknownReviewCatalog = null;
      // Acknowledgement is retained separately from optional current-state reads.
      _clearCatalogs();
      _notify();
      return true;
    } catch (error) {
      if (_disposed) return false;
      if (_isOwnerError(error)) {
        _ownerLost();
      } else if (error is AdminAssetWriteUnknown) {
        operation = AdminAssetOperationState.unknown;
        unknownReviewCatalog = reviewCatalog;
        lastUnconfirmedOperation = reviewCatalog;
      } else if (error is AdminAssetTargetChanged) {
        operation = AdminAssetOperationState.changed;
      } else if (error is AdminAssetLegacyMigrationRequired) {
        migrationHostIds = error.hostIds;
        operation = AdminAssetOperationState.migrationRequired;
      } else {
        operation = AdminAssetOperationState.refused;
      }
      _clearCatalogs();
      _notify();
      return false;
    }
  }

  void _clearCatalogs() {
    hosts = null;
    credentials = null;
    settings = null;
    for (final kind in AdminAssetCatalog.values) {
      _loads[kind] = AdminAssetLoadState.idle;
    }
  }

  Future<bool> createHost(
    AdminAssetHostDraft draft,
    AdminAssetCredentialMetadata chosen,
  ) => _write(() async {
    final result = await repository.createHost(owner, draft, chosen);
    if (!_disposed) {
      savedHost = result;
    }
  });
  Future<bool> updateHost(
    AdminAssetHostMetadata baseline,
    AdminAssetHostDraft draft, {
    AdminAssetCredentialMetadata? chosen,
  }) => _write(() async {
    final result = await repository.updateHost(
      owner,
      baseline,
      draft,
      chosen: chosen,
    );
    if (!_disposed) {
      savedHost = result;
    }
  });
  Future<bool> createCredential(
    AdminAssetCredentialDraft draft,
    String replacement, {
    void Function()? onSubmitted,
  }) => _write(() async {
    final result = await repository.createCredential(
      owner,
      draft,
      replacement,
      onSubmitted: onSubmitted,
    );
    if (!_disposed) {
      savedCredential = result;
    }
  }, reviewCatalog: AdminAssetCatalog.credentials);
  Future<bool> updateCredential(
    AdminAssetCredentialMetadata baseline,
    AdminAssetCredentialDraft draft, {
    String? replacement,
    void Function()? onSubmitted,
  }) => _write(() async {
    final result = await repository.updateCredential(
      owner,
      baseline,
      draft,
      replacement: replacement,
      onSubmitted: onSubmitted,
    );
    if (!_disposed) {
      savedCredential = result;
    }
  }, reviewCatalog: AdminAssetCatalog.credentials);
  Future<bool> deleteHost(AdminAssetHostMetadata baseline) => _write(() async {
    final result = await repository.deleteHost(owner, baseline);
    if (!_disposed) {
      deleteReceipt = result;
    }
  });
  Future<bool> deleteCredential(AdminAssetCredentialMetadata baseline) =>
      _write(() async {
        final result = await repository.deleteCredential(owner, baseline);
        if (!_disposed) {
          deleteReceipt = result;
        }
      }, reviewCatalog: AdminAssetCatalog.credentials);
  Future<bool> testHost(AdminAssetHostMetadata baseline) => _write(() async {
    final result = await repository.testHost(owner, baseline);
    if (!_disposed) {
      connectionReceipt = result;
      testedHostId = baseline.id;
    }
  });
  Future<bool> saveSettings(
    AdminAssetSettingsMetadata baseline, {
    required int idleSeconds,
    required int scrollbackLines,
    required AdminAssetKeyAction action,
    String? replacement,
    void Function()? onSubmitted,
  }) => _write(() async {
    final result = await repository.saveSettings(
      owner,
      baseline,
      idleSeconds: idleSeconds,
      scrollbackLines: scrollbackLines,
      action: action,
      replacement: replacement,
      onSubmitted: onSubmitted,
    );
    if (!_disposed) {
      settingsReceipt = result;
    }
  }, reviewCatalog: AdminAssetCatalog.settings);

  /// Explicitly finish a read-only review; this never adopts a guessed create ID.
  bool finishUnknownReview(AdminAssetCatalog kind) {
    if (operation != AdminAssetOperationState.unknown ||
        migrationPartial ||
        kind != unknownReviewCatalog ||
        _loads[kind] != AdminAssetLoadState.ready) {
      return false;
    }
    operation = AdminAssetOperationState.idle;
    unknownReviewCatalog = null;
    _notify();
    return true;
  }

  Future<AdminAssetSecretLease> _viewSecret(
    Future<AdminAssetSecretLease> Function() action,
  ) async {
    if (closed) throw AdminAssetOwnerLost();
    try {
      final lease = await action();
      if (closed) {
        lease.close();
        throw AdminAssetOwnerLost();
      }
      return lease;
    } catch (error) {
      if (!_disposed && _isOwnerError(error)) {
        _ownerLost();
        _notify();
      }
      rethrow;
    }
  }

  Future<AdminAssetSecretLease> revealCredential(
    AdminAssetCredentialMetadata reviewed,
  ) => _viewSecret(() => repository.revealCredential(owner, reviewed));
  Future<AdminAssetSecretLease> revealSettingsKey(
    AdminAssetSettingsMetadata reviewed,
  ) => _viewSecret(() => repository.revealSettingsKey(owner, reviewed));

  void background() {
    repository.closeSecrets();
    _generation++;
    migrationRetired =
        migrationRetired ||
        migrationPlan != null ||
        migrationCreated != null ||
        preparingMigration;
    migrationPlan = null;
    for (final kind in AdminAssetCatalog.values) {
      if (_loads[kind] == AdminAssetLoadState.loading) {
        _loads[kind] = AdminAssetLoadState.idle;
      }
    }
    _notify();
  }

  Future<bool> prepareMigration(
    AdminAssetHostMetadata host,
    String name,
  ) async {
    if (!canWrite || migrationPartial) return false;
    final generation = ++_generation;
    preparingMigration = true;
    migrationCreated = null;
    migrationPlan = null;
    migrationBound = null;
    migrationRetired = false;
    _notify();
    try {
      final plan = await repository.prepareLegacyMigration(owner, host, name);
      if (_disposed || generation != _generation) return false;
      migrationPlan = plan;
      return true;
    } catch (error) {
      if (_disposed || generation != _generation) return false;
      if (_isOwnerError(error)) {
        _ownerLost();
      } else {
        operation = error is AdminAssetTargetChanged
            ? AdminAssetOperationState.changed
            : AdminAssetOperationState.refused;
      }
      return false;
    } finally {
      if (!_disposed) {
        preparingMigration = false;
        _notify();
      }
    }
  }

  Future<bool> createMigrationCredential() {
    final plan = migrationPlan;
    if (plan == null || migrationRetired || migrationCreated != null) {
      return Future.value(false);
    }
    return _write(() async {
      final result = await repository.createLegacyMigrationCredential(
        owner,
        plan,
      );
      if (!_disposed) migrationCreated = result;
    }, reviewCatalog: AdminAssetCatalog.credentials);
  }

  Future<bool> bindMigration() {
    final created = migrationCreated;
    if (created == null || migrationRetired || migrationBound != null) {
      return Future.value(false);
    }
    return _write(() async {
      final result = await repository.bindLegacyMigration(owner, created);
      if (!_disposed) {
        migrationBound = result;
        savedHost = result.host;
      }
    });
  }

  bool finishMigrationReview() {
    if (closed ||
        !(migrationPlan != null ||
            migrationCreated != null ||
            migrationBound != null ||
            migrationRetired) ||
        operation == AdminAssetOperationState.submitting ||
        _loads[AdminAssetCatalog.hosts] != AdminAssetLoadState.ready ||
        _loads[AdminAssetCatalog.credentials] != AdminAssetLoadState.ready) {
      return false;
    }
    repository.closeSecrets();
    migrationPlan = null;
    migrationCreated = null;
    migrationBound = null;
    migrationRetired = false;
    unknownReviewCatalog = null;
    operation = AdminAssetOperationState.idle;
    _notify();
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _clearData();
    repository.dispose();
    super.dispose();
  }
}
