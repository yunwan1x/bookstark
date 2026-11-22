import 'dart:convert';
import 'secure_record_store.dart';

enum NavigationView { cards, list, compact }

class NavigationPreferences {
  const NavigationPreferences({
    this.view = NavigationView.cards,
    this.groups = const {},
  });
  final NavigationView view;
  final Set<String> groups;
}

class NavigationPreferencesVault extends SecureRecordStore {
  NavigationPreferencesVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.navigation-preferences.v1');
  Future<NavigationPreferences> read() async {
    final value = await readRecord(null);
    if (value == null) return const NavigationPreferences();
    if (utf8.encode(value).length > 32 * 1024) {
      throw const FormatException('Navigation preferences too large');
    }
    final row = jsonDecode(value) as Map;
    if (row['version'] != 1 || row['groups'] is! List) {
      throw const FormatException('Invalid navigation preferences');
    }
    final view = NavigationView.values
        .where((item) => item.name == row['view'])
        .firstOrNull;
    if (view == null) throw const FormatException('Unknown navigation view');
    return NavigationPreferences(
      view: view,
      groups: (row['groups'] as List).cast<String>().toSet(),
    );
  }

  Future<void> write(NavigationPreferences value) {
    final text = jsonEncode({
      'version': 1,
      'view': value.view.name,
      'groups': value.groups.toList(),
    });
    if (utf8.encode(text).length > 32 * 1024) {
      throw const FormatException('Navigation preferences too large');
    }
    return writeRecord(null, text);
  }

  Future<void> clear() => removeRecord(null);
}
