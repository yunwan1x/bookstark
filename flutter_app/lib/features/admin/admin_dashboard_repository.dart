import 'package:bookstark_flutter/core/api_client.dart';

/// Server-supported query ranges. Keep this allowlist aligned with
/// controllers/dashboard.go; the server silently maps unknown values to 7d.
enum DashboardRange {
  hours24('24h'),
  days7('7d'),
  days30('30d'),
  days90('90d');

  const DashboardRange(this.queryValue);
  final String queryValue;

  /// The backend stores daily aggregates only. Even the 24h request currently
  /// returns daily data and includes the entire starting calendar date.
  String get bucketDescription => 'daily';
}

class DashboardStats {
  const DashboardStats({required this.totalVisits, required this.uniqueIps});
  final int totalVisits;

  /// Sum of daily UV counts, not distinct IPs over the selected period.
  final int uniqueIps;

  factory DashboardStats.fromJson(Object? value) {
    final json = _object(value, 'stats');
    return DashboardStats(
      totalVisits: _nonNegativeInt(json['total_visits'], 'total_visits'),
      uniqueIps: _nonNegativeInt(json['unique_ips'], 'unique_ips'),
    );
  }
}

class DashboardTrendPoint {
  const DashboardTrendPoint({
    required this.bucketLabel,
    required this.pageViews,
    required this.uniqueIps,
  });

  /// Backend label as returned. Daily ranges use YYYY-MM-DD; the 24h query
  /// currently returns daily source rows labeled YYYY-MM-DD 00:00. These
  /// labels are not parsed as precise timestamps or assigned a timezone.
  final String bucketLabel;
  final int pageViews;
  final int uniqueIps;

  factory DashboardTrendPoint.fromJson(Object? value) {
    final json = _object(value, 'trend point');
    final label = json['time'];
    if (label is! String || !_validBucketLabel(label)) {
      throw const FormatException('Invalid dashboard trend time');
    }
    return DashboardTrendPoint(
      bucketLabel: label,
      pageViews: _nonNegativeInt(json['page_views'], 'page_views'),
      uniqueIps: _nonNegativeInt(json['unique_ips'], 'unique_ips'),
    );
  }
}

class DashboardVisitLog {
  const DashboardVisitLog({
    required this.visitId,
    required this.ip,
    required this.path,
    required this.memberId,
    required this.visitTime,
    required this.account,
  });
  final int visitId;
  final String ip;
  final String path;
  final int memberId;

  /// Requires an explicit RFC3339 offset. Go serializes time.Time with an
  /// offset; converting to local display time belongs in the presentation.
  final DateTime visitTime;
  final String account;

  bool get anonymous => memberId == 0;

  factory DashboardVisitLog.fromJson(Object? value) {
    final json = _object(value, 'visit log');
    final rawTime = json['visit_time'];
    if (rawTime is! String || !_validRfc3339(rawTime)) {
      throw const FormatException('Invalid dashboard visit_time');
    }
    final time = DateTime.tryParse(rawTime);
    if (time == null) {
      throw const FormatException('Invalid dashboard visit_time');
    }
    final memberId = _nonNegativeInt(json['member_id'], 'member_id');
    return DashboardVisitLog(
      visitId: _positiveInt(json['visit_id'], 'visit_id'),
      ip: _nonEmptyString(json['ip'], 'ip'),
      path: _nonEmptyString(json['path'], 'path'),
      memberId: memberId,
      visitTime: time,
      account: _string(json['account'], 'account'),
    );
  }
}

class DashboardLogPage {
  const DashboardLogPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });
  final List<DashboardVisitLog> items;
  final int total;
  final int page;
  final int pageSize;

  /// Server returns at least 1, including when total == 0.
  final int totalPages;

  factory DashboardLogPage.fromEnvelope(
    Object? value, {
    required int requestedPage,
    int expectedPageSize = 20,
  }) {
    final json = _object(value, 'logs response');
    if (json['code'] != 0) {
      throw const FormatException('Invalid logs response code');
    }
    final raw = json['data'];
    if (raw is! List) throw const FormatException('Invalid logs data');
    final total = _nonNegativeInt(json['total'], 'total');
    final page = _positiveInt(json['page'], 'page');
    final pageSize = _positiveInt(json['page_size'], 'page_size');
    final pages = _positiveInt(json['total_pages'], 'total_pages');
    if (page != requestedPage ||
        pageSize != expectedPageSize ||
        pages != (total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize) ||
        raw.length > pageSize) {
      throw const FormatException('Invalid logs pagination metadata');
    }
    return DashboardLogPage(
      items: List.unmodifiable(raw.map(DashboardVisitLog.fromJson)),
      total: total,
      page: page,
      pageSize: pageSize,
      totalPages: pages,
    );
  }
}

/// Read-only adapter over the three AdminRequired Go GET routes. The caller
/// gates the feature on the current server profile's role; this repository
/// always relies on server authorization and propagates ApiFailure (including
/// 401/403). It performs no caching or persistence.
class AdminDashboardRepository {
  AdminDashboardRepository(this._client)
    : _session = _client.exportSession()['token'];
  final BookstarkClient _client;
  final String? _session;

  void _checkSession() {
    if (_client.exportSession()['token'] != _session) {
      throw const ApiFailure(401, 'Administrator session changed');
    }
  }

  Future<Map<String, Object?>> _get(
    String path, {
    Future<void>? abortTrigger,
  }) async {
    _checkSession();
    final response = await _client.get(path, abortTrigger: abortTrigger);
    _checkSession();
    return response;
  }

  static const pageSize = 20;

  Future<DashboardStats> stats(
    DashboardRange range, {
    Future<void>? abortTrigger,
  }) async {
    final response = await _get(
      '/api/admin/dashboard/stats?range=${range.queryValue}',
      abortTrigger: abortTrigger,
    );
    // BookstarkClient unwraps object-valued data; also accept the exact
    // envelope shape for isolated adapters/tests, but validate its code.
    final body = response.containsKey('data')
        ? _checkedData(response, 'stats')
        : response;
    return DashboardStats.fromJson(body);
  }

  Future<List<DashboardTrendPoint>> trend(
    DashboardRange range, {
    Future<void>? abortTrigger,
  }) async {
    final response = await _get(
      '/api/admin/dashboard/trend?range=${range.queryValue}',
      abortTrigger: abortTrigger,
    );
    final body = _checkedData(response, 'trend');
    // GetVisitTrend currently returns a nil Go slice when there are no rows,
    // which JSON encodes as null. Treat only that known empty representation
    // as empty; malformed non-list values still fail.
    if (body == null) return const [];
    if (body is! List) throw const FormatException('Invalid trend data');
    return List.unmodifiable(body.map(DashboardTrendPoint.fromJson));
  }

  Future<DashboardLogPage> logs(int page, {Future<void>? abortTrigger}) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final response = await _get(
      '/api/admin/dashboard/logs?page=$page&pageSize=$pageSize',
      abortTrigger: abortTrigger,
    );
    return DashboardLogPage.fromEnvelope(response, requestedPage: page);
  }

  Object? _checkedData(Map<String, Object?> response, String name) {
    if (response['code'] != 0 || !response.containsKey('data')) {
      throw FormatException('Invalid dashboard $name envelope');
    }
    return response['data'];
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name object');
  final entries = <MapEntry<String, Object?>>[];
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $name key');
    entries.add(MapEntry(entry.key as String, entry.value));
  }
  return Map<String, Object?>.fromEntries(entries);
}

int _positiveInt(Object? value, String name) {
  if (value is! int || value <= 0) throw FormatException('Invalid $name');
  return value;
}

int _nonNegativeInt(Object? value, String name) {
  if (value is! int || value < 0) throw FormatException('Invalid $name');
  return value;
}

String _nonEmptyString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name');
  }
  return value;
}

String _string(Object? value, String name) {
  if (value is! String) throw FormatException('Invalid $name');
  return value;
}

bool _validRfc3339(String value) {
  final match = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|([+-])([0-9]{2}):([0-9]{2}))$',
  ).firstMatch(value);
  if (match == null) return false;

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final offsetHour = match[10] == null ? 0 : int.parse(match[10]!);
  final offsetMinute = match[11] == null ? 0 : int.parse(match[11]!);
  if (offsetHour > 23 || offsetMinute > 59) return false;

  final normalized = DateTime.utc(year, month, day, hour, minute, second);
  return normalized.year == year &&
      normalized.month == month &&
      normalized.day == day &&
      normalized.hour == hour &&
      normalized.minute == minute &&
      normalized.second == second &&
      DateTime.tryParse(value) != null;
}

bool _validBucketLabel(String value) {
  final day = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$').firstMatch(value);
  final hour = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):00$',
  ).firstMatch(value);
  final match = day ?? hour;
  if (match == null) return false;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final date = int.parse(match[3]!);
  final h = hour == null ? 0 : int.parse(match[4]!);
  final parsed = DateTime.utc(year, month, date, h);
  return parsed.year == year &&
      parsed.month == month &&
      parsed.day == date &&
      parsed.hour == h;
}
