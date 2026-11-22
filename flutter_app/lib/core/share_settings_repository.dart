import 'api_client.dart';
import 'public_share_models.dart';

enum ShareTokenAction { enable, reset, disable }

class OwnerShareTarget {
  OwnerShareTarget({
    required this.kind,
    required this.id,
    required this.title,
    this.protected = false,
  }) {
    if (id <= 0 ||
        id > 9007199254740991 ||
        title.length > 10000 ||
        protected && kind != PublicShareKind.blog) {
      throw const FormatException('Invalid owner sharing target');
    }
  }
  final PublicShareKind kind;
  final int id;
  final String title;
  final bool protected;
  bool get supportsEditing => kind != PublicShareKind.book;
  String get path => '/api/shares/${kind.name}/$id';
}

/// Session-only publication receipt. Do not log, persist or export its token.
class OwnerShareReceipt {
  OwnerShareReceipt(this.target, this.reference, String token)
    : _token = token {
    if (token.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid sharing capability receipt');
    }
  }
  final OwnerShareTarget target;
  final PublicShareReference reference;
  final String _token;
  bool get editingEnabled => _token.isNotEmpty;
  Uri? get editingUri => editingEnabled
      ? reference.canonicalUri.replace(queryParameters: {'token': _token})
      : null;
  OwnerShareReceipt withoutToken() => OwnerShareReceipt(target, reference, '');
  @override
  String toString() => 'OwnerShareReceipt(<redacted>)';
}

abstract interface class ShareSettingsRepository {
  Future<bool> status(OwnerShareTarget target);
  Future<OwnerShareReceipt> publish(OwnerShareTarget target);
  Future<OwnerShareReceipt> changeToken(
    OwnerShareTarget target,
    OwnerShareReceipt current,
    ShareTokenAction action,
  );
  Future<void> unpublish(OwnerShareTarget target);
}

class RemoteShareSettingsRepository implements ShareSettingsRepository {
  RemoteShareSettingsRepository(this.client);
  final BookstarkClient client;
  @override
  Future<bool> status(OwnerShareTarget target) async {
    final row = await client.shareSettingsJson(target.kind, target.id);
    if (row.keys.any((key) => key != '${target.id}') ||
        row.values.any((value) => value is! bool)) {
      throw const FormatException('Invalid sharing status');
    }
    return row['${target.id}'] == true;
  }

  @override
  Future<OwnerShareReceipt> publish(OwnerShareTarget target) async {
    // This is an explicit publication. Never use it as an automatic status GET.
    // enable_edit=false preserves existing capabilities on the legacy server.
    final row = await client.shareSettingsJson(
      target.kind,
      target.id,
      action: 'publish',
    );
    final identify = row['share_identify'], token = row['edit_token'];
    if (identify is! String || token is! String) {
      throw const FormatException('Missing actual publication receipt');
    }
    return OwnerShareReceipt(
      target,
      PublicShareReference(client.baseUri, identify),
      target.supportsEditing ? token : '',
    );
  }

  @override
  Future<OwnerShareReceipt> changeToken(
    OwnerShareTarget target,
    OwnerShareReceipt current,
    ShareTokenAction action,
  ) async {
    if (!target.supportsEditing ||
        current.reference.server != client.baseUri ||
        current.target.kind != target.kind ||
        current.target.id != target.id) {
      throw StateError('Editing is unavailable in this sharing context');
    }
    final row = await client.shareSettingsJson(
      target.kind,
      target.id,
      action: action.name,
    );
    final token = row['edit_token'];
    if (token is! String ||
        action == ShareTokenAction.disable && token.isNotEmpty ||
        action != ShareTokenAction.disable && token.isEmpty) {
      throw const FormatException('Invalid editing capability receipt');
    }
    return OwnerShareReceipt(target, current.reference, token);
  }

  @override
  Future<void> unpublish(OwnerShareTarget target) async {
    await client.shareSettingsJson(target.kind, target.id, action: 'unpublish');
  }
}
