import 'dart:convert';

enum AdminMemberRole {
  administrator(0),
  member(1);

  const AdminMemberRole(this.value);
  final int value;
  static AdminMemberRole parse(Object? value) => value is! int
      ? throw const FormatException('Invalid role integer')
      : switch (value) {
          0 => administrator,
          1 => member,
          _ => throw const FormatException('Unsupported member role'),
        };
}

enum AdminMemberStatus {
  pending(0),
  approved(1),
  rejected(2);

  const AdminMemberStatus(this.value);
  final int value;
  static AdminMemberStatus parse(Object? value) => value is! int
      ? throw const FormatException('Invalid approval integer')
      : switch (value) {
          0 => pending,
          1 => approved,
          2 => rejected,
          _ => throw const FormatException(
            'Unsupported member approval status',
          ),
        };
}

/// Only the fields actually selected by ListAllMembers. Email/default_home are
/// zero-valued serialization artifacts, not contact information or preferences.
class AdminMemberRecord {
  const AdminMemberRecord({
    required this.id,
    required this.account,
    required this.role,
    required this.status,
    required this.created,
    required this.createdUnix,
    required this.lastLogin,
  });
  final int id;
  final String account;
  final AdminMemberRole role;
  final AdminMemberStatus status;
  final DateTime created;
  final int createdUnix;
  final DateTime? lastLogin;

  factory AdminMemberRecord.parse(Object? value) {
    final row = _object(value);
    return AdminMemberRecord(
      id: _integer(row['member_id'], minimum: 1),
      account: _account(row['account']),
      role: AdminMemberRole.parse(row['role']),
      status: AdminMemberStatus.parse(row['status']),
      created: _time(row['create_time']),
      createdUnix: _integer(row['create_at'], minimum: 0),
      lastLogin: row['last_login_time'] == null
          ? null
          : _time(row['last_login_time']),
    );
  }

  /// Confirmation must be bound to the identity, role and approval state that
  /// were actually reviewed. A fresh list cannot establish a mutation receipt.
  bool sameReviewedTarget(AdminMemberRecord other) =>
      id == other.id &&
      account == other.account &&
      role == other.role &&
      status == other.status;

  @override
  String toString() => 'AdminMemberRecord(id: $id, personalFields: [redacted])';
}

class AdminMemberPage {
  const AdminMemberPage({
    required this.items,
    required this.page,
    required this.total,
    required this.totalPages,
  });
  static const pageSize = 20;
  final List<AdminMemberRecord> items;
  final int page, total, totalPages;
  bool get hasPrevious => page > 1;
  bool get hasNext => page < totalPages;

  factory AdminMemberPage.parse(
    Map<String, Object?> envelope, {
    required int requestedPage,
  }) {
    if (requestedPage < 1 ||
        envelope['code'] is! int ||
        envelope['page'] is! int ||
        envelope['page_size'] is! int ||
        envelope['code'] != 0 ||
        envelope['page'] != requestedPage ||
        envelope['page_size'] != pageSize) {
      throw const FormatException('Invalid member page metadata');
    }
    final total = _integer(envelope['total'], minimum: 0);
    final pages = _integer(envelope['total_pages'], minimum: 1);
    final expected = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
    if (pages != expected) {
      throw const FormatException('Inconsistent member page total');
    }
    final data = envelope['data'];
    if (data != null && data is! List) {
      throw const FormatException('Invalid member list');
    }
    final items = (data as List? ?? const [])
        .map(AdminMemberRecord.parse)
        .toList();
    if (items.length > pageSize ||
        items.length > total ||
        requestedPage > pages && items.isNotEmpty) {
      throw const FormatException('Invalid member list bounds');
    }
    int previous = 0;
    for (final item in items) {
      if (item.id <= previous) {
        throw const FormatException('Member IDs must be unique and increasing');
      }
      previous = item.id;
    }
    return AdminMemberPage(
      items: List.unmodifiable(items),
      page: requestedPage,
      total: total,
      totalPages: pages,
    );
  }
}

class AdminMemberPassword {
  const AdminMemberPassword._();
  static void validate(String password, String confirmation) {
    final bytes = utf8.encode(password).length;
    if (bytes < 6 || bytes > 72) {
      throw const FormatException('Password must contain 6–72 UTF-8 bytes');
    }
    if (password != confirmation) {
      throw const FormatException('Password confirmation does not match');
    }
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid member object');
  }
  return Map<String, Object?>.from(value);
}

int _integer(Object? value, {required int minimum}) {
  if (value is! int || value < minimum) {
    throw const FormatException('Invalid member integer');
  }
  return value;
}

String _account(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Missing member account');
  }
  return value;
}

DateTime _time(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid member timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Invalid member timestamp');
  return parsed;
}
