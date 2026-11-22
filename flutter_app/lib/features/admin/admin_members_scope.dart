import 'admin_settings_scope.dart';

/// Reuses the session-owned administrator lifetime without loading settings.
class AdminMembersScope extends AdminSettingsScope {
  AdminMembersScope(super.client, super.owner);
}
