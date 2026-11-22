/// Public state deliberately contains no current or replacement key.
final class AdminAssetSettingsMetadata {
  const AdminAssetSettingsMetadata({
    required this.idleSeconds,
    required this.scrollbackLines,
    required this.encryptionEnabled,
  });
  final int idleSeconds, scrollbackLines;
  final bool encryptionEnabled;
  @override
  String toString() => 'AdminAssetSettingsMetadata';
}

enum AdminAssetKeyAction { keep, replace, disable }

final class AdminAssetSettingsReceipt {
  const AdminAssetSettingsReceipt(
    this.action,
    this.idleSeconds,
    this.scrollbackLines,
  );
  final AdminAssetKeyAction action;
  final int idleSeconds, scrollbackLines;
  // An acknowledged request is separate from a later read of current state.
  @override
  String toString() => 'AdminAssetSettingsReceipt';
}

class AdminAssetLegacyMigrationRequired implements Exception {
  const AdminAssetLegacyMigrationRequired(this.hostIds);
  final List<int> hostIds;
  @override
  String toString() => 'Host credentials require migration or rebinding';
}
