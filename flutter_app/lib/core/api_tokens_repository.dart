import 'dart:convert';
import 'api_client.dart';
import 'profile_repository.dart';

void validateApiTokenName(String name) {
  for (var i = 0; i < name.length; i++) {
    final unit = name.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= name.length ||
          name.codeUnitAt(i) < 0xdc00 ||
          name.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid token name Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid token name Unicode');
    }
  }
  if (utf8.encode(name).length > 100) {
    throw const FormatException('Token name exceeds100 UTF8 bytes');
  }
}

String maskApiToken(String value) =>
    '${value.substring(0, 4)}****${value.substring(value.length - 4)}';

class ApiTokenEntry {
  const ApiTokenEntry({
    required this.id,
    required this.memberId,
    required this.name,
    required this.masked,
    required this.createdAt,
  });
  final int id, memberId;
  final String name, masked, createdAt;
  factory ApiTokenEntry.fromJson(Map row, int memberId) {
    final id = row['token_id'],
        owner = row['member_id'],
        name = row['name'],
        masked = row['masked_token'],
        created = row['create_time'];
    if (id is! int ||
        id <= 0 ||
        owner is! int ||
        owner != memberId ||
        name is! String ||
        masked is! String ||
        !RegExp(r'^[0-9a-f]{4}\*{4}[0-9a-f]{4}$').hasMatch(masked) ||
        created is! String ||
        created.length > 80 ||
        DateTime.tryParse(created) == null) {
      throw const FormatException('Invalid owned API token metadata');
    }
    validateApiTokenName(name);
    return ApiTokenEntry(
      id: id,
      memberId: memberId,
      name: name,
      masked: masked,
      createdAt: created,
    );
  }
  bool same(ApiTokenEntry other) =>
      id == other.id &&
      memberId == other.memberId &&
      name == other.name &&
      masked == other.masked &&
      createdAt == other.createdAt;
}

class CreatedApiToken {
  const CreatedApiToken(this.entry, this.secret);
  final ApiTokenEntry entry;
  final String secret;
  @override
  String toString() => 'CreatedApiToken(id: ${entry.id}, secret: hidden)';
}

class ApiTokensPage {
  ApiTokensPage(List<ApiTokenEntry> entries)
    : entries = List.unmodifiable(entries);
  final List<ApiTokenEntry> entries;
  bool get truncated => entries.length == 100;
  // Go orders IDs ascending and caps at100. Absence beyond the last returned
  // ID is not evidence of deletion when the list is full.
  bool provesAbsent(int id) =>
      !entries.any((entry) => entry.id == id) &&
      (!truncated || entries.last.id >= id);
}

class ApiTokenPreflightFailure implements Exception {
  const ApiTokenPreflightFailure();
}

abstract interface class ApiTokensRepository {
  Future<ApiTokensPage> read();
  Future<CreatedApiToken> create(String name);
  Future<void> revoke(ApiTokenEntry entry);
  void dispose();
}

class RemoteApiTokensRepository implements ApiTokensRepository {
  RemoteApiTokensRepository(this.client, {required this.memberId});
  final BookstarkClient client;
  final int memberId;
  final _observed = <int, ApiTokenEntry>{}, _issued = <int, ApiTokenEntry>{};
  bool _closed = false;
  Future<String?> _owner() async {
    if (_closed) {
      throw const ApiTokenPreflightFailure();
    }
    final token = client.exportSession()['token'];
    try {
      await RemoteProfileRepository(client, memberId: memberId).read();
    } catch (_) {
      throw const ApiTokenPreflightFailure();
    }
    if (_closed || token != client.exportSession()['token']) {
      throw const ApiTokenPreflightFailure();
    }
    return token;
  }

  void _current(String? token) {
    if (_closed || token != client.exportSession()['token']) {
      throw StateError('API token owner context changed');
    }
  }

  @override
  Future<ApiTokensPage> read() async {
    final token = await _owner();
    final row = await client.listApiTokensJson();
    _current(token);
    final data = row['data'];
    if (data is! List || data.length > 100) {
      throw const FormatException('Invalid capped API token list');
    }
    final entries = <ApiTokenEntry>[];
    var previous = 0;
    for (final item in data) {
      if (item is! Map) {
        throw const FormatException('Invalid API token metadata');
      }
      final entry = ApiTokenEntry.fromJson(item, memberId);
      if (entry.id <= previous) {
        throw const FormatException(
          'API token identities must be unique and ascending',
        );
      }
      entries.add(entry);
      previous = entry.id;
    }
    _observed
      ..clear()
      ..addEntries(entries.map((entry) => MapEntry(entry.id, entry)));
    return ApiTokensPage(entries);
  }

  @override
  Future<CreatedApiToken> create(String name) async {
    validateApiTokenName(name);
    final token = await _owner();
    final row = await client.createApiTokenJson(name);
    _current(token);
    final data = row['data'], secret = row['token'];
    if (data is! Map ||
        secret is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(secret)) {
      throw const FormatException('Missing actual one-time token receipt');
    }
    final entry = ApiTokenEntry.fromJson(data, memberId);
    if (entry.name != (name.isEmpty ? 'default' : name) ||
        entry.masked != maskApiToken(secret)) {
      throw const FormatException('Token receipt metadata differs');
    }
    _issued[entry.id] = entry;
    return CreatedApiToken(entry, secret);
  }

  @override
  Future<void> revoke(ApiTokenEntry entry) async {
    final known = _observed[entry.id] ?? _issued[entry.id];
    if (known == null || !known.same(entry)) {
      throw const ApiTokenPreflightFailure();
    }
    final token = await _owner();
    final row = await client.deleteApiTokenJson(entry.id);
    _current(token);
    if (!{0, 200}.contains(row['code']) || row['message'] is! String) {
      throw const FormatException('Missing actual token revocation receipt');
    }
  }

  @override
  void dispose() {
    _closed = true;
    _observed.clear();
    _issued.clear();
  }
}
