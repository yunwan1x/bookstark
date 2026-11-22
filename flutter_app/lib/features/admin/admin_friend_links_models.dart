import 'dart:convert';

class AdminFriendLink {
  AdminFriendLink._(this.raw);
  final Map<String, Object?> raw;
  factory AdminFriendLink.parse(Object? value) {
    final row = _object(value);
    _int(row['link_id'], minimum: 1);
    for (final key in [
      'link_name',
      'link_url',
      'group_name',
      'qr_code',
      'description',
    ]) {
      _text(row[key]);
    }
    for (final key in ['group_order', 'sort_weight', 'is_enabled']) {
      _int(row[key]);
    }
    return AdminFriendLink._(row);
  }
  factory AdminFriendLink.create() => AdminFriendLink._(
    _object({
      'link_id': 0,
      'link_name': '',
      'link_url': '',
      'group_name': '',
      'group_order': 0,
      'qr_code': '',
      'description': '',
      'sort_weight': 0,
      'is_enabled': 1,
    }),
  );
  String get name => raw['link_name'] as String;
  String get url => raw['link_url'] as String;
  String get group => raw['group_name'] as String;
  String get qr => raw['qr_code'] as String;
  String get description => raw['description'] as String;
  int get groupOrder => raw['group_order'] as int;
  int get weight => raw['sort_weight'] as int;
  bool get enabled => raw['is_enabled'] != 0;
  AdminFriendLink edit({
    String? name,
    String? url,
    String? group,
    String? qr,
    String? description,
    int? groupOrder,
    int? weight,
    bool? enabled,
  }) => AdminFriendLink._(
    _object({
      ...raw,
      'link_name': ?name,
      'link_url': ?url,
      'group_name': ?group,
      'qr_code': ?qr,
      'description': ?description,
      if (groupOrder != null) 'group_order': _int(groupOrder),
      if (weight != null) 'sort_weight': _int(weight),
      if (enabled != null) 'is_enabled': enabled ? 1 : 0,
    }),
  );
  void validate() {
    if (utf8.encode(name).length > 100 || utf8.encode(url).length > 2048) {
      throw const FormatException('Friend link raw byte limit exceeded');
    }
    final n = name.trim(),
        u = url.trim(),
        g = group.trim(),
        q = qr.trim(),
        d = description.trim();
    if (n.isEmpty ||
        utf8.encode(g).length > 100 ||
        utf8.encode(q).length > 2048 ||
        utf8.encode(d).length > 1000) {
      throw const FormatException('Invalid normalized friend link fields');
    }
    if (q.isNotEmpty && !canonicalFriendQr(q)) {
      throw const FormatException('QR must be a canonical uploaded image');
    }
    if (u.isEmpty) {
      if (q.isNotEmpty) return;
      throw const FormatException('Friend link needs URL or QR');
    }
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(u)) {
      throw const FormatException('Invalid URL control character');
    }
    final parsed = Uri.tryParse(u);
    if (parsed == null ||
        !{'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty) {
      throw const FormatException('Friend URL needs an HTTP(S) host');
    }
    for (var i = 0; i < u.length; i++) {
      if (u.codeUnitAt(i) == 37 &&
          (i + 2 >= u.length ||
              int.tryParse(u.substring(i + 1, i + 3), radix: 16) == null)) {
        throw const FormatException('Invalid URL percent encoding');
      }
    }
  }

  Map<String, Object?> get semantic {
    final result = {...raw};
    for (final key in [
      'link_id',
      'create_time',
      'modify_time',
      'created_by',
      'updated_by',
    ]) {
      result.remove(key);
    }
    result.addAll({
      'link_name': name.trim(),
      'link_url': url.trim(),
      'group_name': group.trim(),
      'qr_code': qr.trim(),
      'description': description.trim(),
      'is_enabled': enabled ? 1 : 0,
    });
    return result;
  }

  @override
  String toString() => 'AdminFriendLink(fields: [redacted])';
}

class AdminFriendLinksSnapshot {
  AdminFriendLinksSnapshot({
    required List<AdminFriendLink> items,
    required this.simpleMode,
  }) : items = List.unmodifiable(items) {
    if (items.length > 200) {
      throw const FormatException('Too many friend links');
    }
  }
  final List<AdminFriendLink> items;
  final bool simpleMode;
  factory AdminFriendLinksSnapshot.parse(Map<String, Object?> data) {
    final rows = data['items'];
    if ((rows != null && rows is! List) || data['simple_mode'] is! bool) {
      throw const FormatException('Invalid friend link snapshot');
    }
    return AdminFriendLinksSnapshot(
      items: [
        for (final row in rows as List? ?? const []) AdminFriendLink.parse(row),
      ],
      simpleMode: data['simple_mode'] as bool,
    );
  }
  Map<String, Object?> checkedBody() {
    final groups = <String, (String, String)>{};
    for (final item in items) {
      item.validate();
      if (item.qr.trim().isNotEmpty) {
        final key = item.group.trim(),
            meta = (item.name.trim(), item.description.trim());
        if (groups.containsKey(key) && groups[key] != meta) {
          throw const FormatException(
            'QR group title and description must agree',
          );
        }
        groups[key] = meta;
      }
    }
    final body = <String, Object?>{
      'items': [for (final item in items) item.raw],
      'simple_mode': simpleMode,
    };
    if (utf8.encode(jsonEncode(body)).length > 1024 * 1024) {
      throw const FormatException('Friend link request exceeds 1MiB');
    }
    return body;
  }

  String get semanticKey {
    final rows = items.indexed.toList();
    rows.sort((a, b) {
      final group = a.$2.groupOrder.compareTo(b.$2.groupOrder);
      if (group != 0) return group;
      final weight = a.$2.weight.compareTo(b.$2.weight);
      return weight == 0 ? a.$1.compareTo(b.$1) : weight;
    });
    return jsonEncode(
      _ordered({
        'items': [for (final row in rows) row.$2.semantic],
        'simple_mode': simpleMode,
      }),
    );
  }

  @override
  String toString() =>
      'AdminFriendLinksSnapshot(count: ${items.length}, fields: [redacted])';
}

bool canonicalFriendQr(String value) {
  if (!value.startsWith('/upload-files/') ||
      value.contains('?') ||
      value.contains('#')) {
    return false;
  }
  final raw = utf8.encode(value), decoded = <int>[];
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] != 37) {
      decoded.add(raw[i]);
      continue;
    }
    if (i + 2 >= raw.length) return false;
    final byte = int.tryParse(
      String.fromCharCodes(raw.sublist(i + 1, i + 3)),
      radix: 16,
    );
    if (byte == null) return false;
    decoded.add(byte);
    i += 2;
  }
  if (decoded.contains(92)) return false;
  final path = String.fromCharCodes(decoded);
  if (path
      .split('/')
      .skip(1)
      .any((part) => part.isEmpty || part == '.' || part == '..')) {
    return false;
  }
  if (![
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
  ].any((ext) => path.toLowerCase().endsWith(ext))) {
    return false;
  }
  final encoded = StringBuffer();
  for (final byte in decoded) {
    final allowed =
        (byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) ||
        ('-_.~'
                r'$&+,/:;=@')
            .codeUnits
            .contains(byte);
    if (allowed) {
      encoded.writeCharCode(byte);
    } else {
      encoded.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return encoded.toString() == value;
}

Object? _ordered(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) return [for (final item in value) _ordered(item)];
  return value;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid friend link object');
  }
  return Map.unmodifiable(
    value.map((key, value) => MapEntry(key as String, _freeze(value))),
  );
}

Object? _freeze(Object? value) {
  if (value is Map) return _object(value);
  if (value is List) return List.unmodifiable(value.map(_freeze));
  if (value == null ||
      value is String ||
      value is bool ||
      value is int ||
      (value is double && value.isFinite)) {
    return value;
  }
  throw const FormatException('Invalid friend link JSON');
}

int _int(Object? value, {int minimum = -9007199254740991}) {
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw const FormatException('Invalid friend link integer');
  }
  return value;
}

String _text(Object? value) => value is String
    ? value
    : throw const FormatException('Invalid friend link text');
