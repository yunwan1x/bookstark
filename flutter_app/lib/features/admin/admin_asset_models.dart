import 'dart:convert';

enum AdminAssetAuth {
  password('password'),
  key('key');

  const AdminAssetAuth(this.value);
  final String value;
  static AdminAssetAuth parse(Object? value) => switch (value) {
    'password' => password,
    'key' => key,
    _ => throw const FormatException('Invalid asset authentication type'),
  };
}

enum AdminAssetStatus {
  unknown('unknown'),
  online('online'),
  offline('offline');

  const AdminAssetStatus(this.value);
  final String value;
  static AdminAssetStatus parse(Object? value) => switch (value) {
    'unknown' => unknown,
    'online' => online,
    'offline' => offline,
    _ => throw const FormatException('Invalid asset status'),
  };
}

enum AdminAssetSecretPresence { notProvided, empty, supplied }

int _integer(Object? value, {int minimum = 0, int maximum = 9007199254740991}) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Invalid asset integer');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Invalid asset text');
  return value;
}

AdminAssetSecretPresence _presence(Map<String, dynamic> data) {
  if (!data.containsKey('credential')) {
    return AdminAssetSecretPresence.notProvided;
  }
  final value = _string(data['credential']);
  // Only retain this enum, never the original map/string in a metadata DTO.
  return value.isEmpty
      ? AdminAssetSecretPresence.empty
      : AdminAssetSecretPresence.supplied;
}

/// Preserve the exact server timestamp for concurrency review (including nanos).
final class AdminAssetTimestamp {
  AdminAssetTimestamp._(this.raw, this.utc);
  final String raw;
  final DateTime utc;

  static AdminAssetTimestamp parse(Object? value) {
    final raw = _string(value);
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(raw);
    if (match == null) throw const FormatException('Invalid asset timestamp');
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final year = parts[0], month = parts[1], day = parts[2];
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        parts[3] > 23 ||
        parts[4] > 59 ||
        parts[5] > 59) {
      throw const FormatException('Invalid asset timestamp');
    }
    final zone = match.group(8)!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4, 6)) > 59)) {
      throw const FormatException('Invalid asset timestamp');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) throw const FormatException('Invalid asset timestamp');
    return AdminAssetTimestamp._(raw, parsed.toUtc());
  }

  bool get meaningful => utc.year > 1;
  @override
  String toString() => 'AdminAssetTimestamp';
}

final class AdminAssetCredentialMetadata {
  AdminAssetCredentialMetadata._({
    required this.id,
    required this.name,
    required this.username,
    required this.auth,
    required this.hint,
    required this.createdBy,
    required this.created,
    required this.modified,
    required this.secretPresence,
  });
  final int id, createdBy;
  final String name, username, hint;
  final AdminAssetAuth auth;
  final AdminAssetTimestamp created, modified;
  final AdminAssetSecretPresence secretPresence;

  factory AdminAssetCredentialMetadata.parse(Map<String, dynamic> data) =>
      AdminAssetCredentialMetadata._(
        id: _integer(data['id'], minimum: 1),
        name: _string(data['name']),
        username: _string(data['username']),
        auth: AdminAssetAuth.parse(data['auth_type']),
        hint: _string(data['credential_hint']),
        createdBy: _integer(data['created_by']),
        created: AdminAssetTimestamp.parse(data['create_time']),
        modified: AdminAssetTimestamp.parse(data['modify_time']),
        secretPresence: _presence(data),
      );

  String get reviewFingerprint => jsonEncode([
    id,
    name,
    username,
    auth.value,
    hint,
    createdBy,
    created.raw,
    modified.raw,
    secretPresence.name,
  ]);

  @override
  String toString() => 'AdminAssetCredentialMetadata#$id';
}

final class AdminAssetHostMetadata {
  AdminAssetHostMetadata._({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.shell,
    required this.cwd,
    required this.dockerSocket,
    required this.credentialId,
    required this.credentialName,
    required this.username,
    required this.auth,
    required this.hint,
    required this.status,
    required this.lastCheck,
    required this.createdBy,
    required this.created,
    required this.modified,
    required this.secretPresence,
  });
  final int id, port, credentialId, createdBy;
  final String name,
      host,
      shell,
      cwd,
      dockerSocket,
      credentialName,
      username,
      hint;
  final AdminAssetAuth auth;
  final AdminAssetStatus status;
  final AdminAssetTimestamp? lastCheck;
  final AdminAssetTimestamp created, modified;
  final AdminAssetSecretPresence secretPresence;

  factory AdminAssetHostMetadata.parse(Map<String, dynamic> data) =>
      AdminAssetHostMetadata._(
        id: _integer(data['id'], minimum: 1),
        name: _string(data['name']),
        host: _string(data['host']),
        port: _integer(data['port'], minimum: 1, maximum: 65535),
        shell: _string(data['shell']),
        cwd: _string(data['cwd']),
        dockerSocket: _string(data['docker_socket_path']),
        credentialId: _integer(data['credential_id']),
        credentialName: data.containsKey('credential_name')
            ? _string(data['credential_name'])
            : '',
        username: _string(data['username']),
        auth: AdminAssetAuth.parse(data['auth_type']),
        hint: _string(data['credential_hint']),
        status: AdminAssetStatus.parse(data['status']),
        lastCheck: data['last_check_time'] == null
            ? null
            : AdminAssetTimestamp.parse(data['last_check_time']),
        createdBy: _integer(data['created_by']),
        created: AdminAssetTimestamp.parse(data['create_time']),
        modified: AdminAssetTimestamp.parse(data['modify_time']),
        secretPresence: _presence(data),
      );

  bool get neverChecked =>
      status == AdminAssetStatus.unknown && !(lastCheck?.meaningful ?? false);
  String get reviewFingerprint => jsonEncode([
    id,
    name,
    host,
    port,
    shell,
    cwd,
    dockerSocket,
    credentialId,
    credentialName,
    username,
    auth.value,
    hint,
    status.value,
    lastCheck?.raw,
    createdBy,
    created.raw,
    modified.raw,
    secretPresence.name,
  ]);

  @override
  String toString() => 'AdminAssetHostMetadata#$id';
}

List<T> adminAssetMetadataList<T>(
  Map<String, dynamic> envelope,
  T Function(Map<String, dynamic>) parse,
  int Function(T) id,
) {
  if (envelope['code'] != 0 || envelope['code'] is! int) {
    throw const FormatException('Invalid asset response');
  }
  final rows = envelope['data'];
  if (rows is! List || rows.length > 10000) {
    throw const FormatException('Asset response exceeds supported bounds');
  }
  final result = <T>[], seen = <int>{};
  for (final row in rows) {
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Invalid asset record');
    }
    final parsed = parse(row);
    if (!seen.add(id(parsed))) {
      throw const FormatException('Duplicate asset identifier');
    }
    result.add(parsed);
  }
  return List.unmodifiable(result);
}
