import 'admin_asset_models.dart';

/// Safe two-step intent. Repository identity checks reject forged/stale plans.
final class AdminAssetMigrationPlan {
  const AdminAssetMigrationPlan(this.host, this.credentialName);
  final AdminAssetHostMetadata host;
  final String credentialName;
  @override
  String toString() => 'AdminAssetMigrationPlan';
}

/// A known first-step receipt is never a receipt for binding the host.
final class AdminAssetMigrationCreated {
  const AdminAssetMigrationCreated(this.plan, this.credential);
  final AdminAssetMigrationPlan plan;
  final AdminAssetCredentialMetadata credential;
  @override
  String toString() => 'AdminAssetMigrationCreated';
}

final class AdminAssetMigrationBound {
  const AdminAssetMigrationBound(this.created, this.host);
  final AdminAssetMigrationCreated created;
  final AdminAssetHostMetadata host;
  @override
  String toString() => 'AdminAssetMigrationBound';
}
