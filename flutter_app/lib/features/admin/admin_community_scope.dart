import 'admin_settings_scope.dart';

/// Session-owned community pages; never loads system settings.
class AdminCommunityScope extends AdminSettingsScope {
  AdminCommunityScope(super.client, super.owner);
}
