enum LegacyTimestampReason { invalid, missing }

final class LegacyTimestampFailure implements Exception {
  const LegacyTimestampFailure(this.reason);
  final LegacyTimestampReason reason;
  @override
  String toString() => 'Legacy resource time cannot be represented';
}

final _legacyTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})([ T])(\d{2}):(\d{2}):(\d{2})(?:[.,](\d{1,9}))?(Z|[+-]\d{2}:\d{2})?$',
);

bool _goSpace(int unit) =>
    unit >= 9 && unit <= 13 ||
    unit == 32 ||
    unit == 0x85 ||
    unit == 0xa0 ||
    unit == 0x1680 ||
    unit >= 0x2000 && unit <= 0x200a ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202f ||
    unit == 0x205f ||
    unit == 0x3000;
String _trimGoSpace(String raw) {
  var begin = 0, end = raw.length;
  while (begin < end && _goSpace(raw.codeUnitAt(begin))) {
    begin++;
  }
  while (end > begin && _goSpace(raw.codeUnitAt(end - 1))) {
    end--;
  }
  return raw.substring(begin, end);
}

/// RFC3339 with up to nanoseconds, or Go's SQL UTC form. Never uses device TZ.
/// Original strings remain in the source metadata. Empty is distinct from an
/// invalid nonempty timestamp; no DateTime normalization silently repairs dates.
int? legacyImportTimestamp(String raw) {
  final text = _trimGoSpace(raw);
  if (text.isEmpty) return null;
  final match = _legacyTime.firstMatch(text);
  if (match == null) {
    throw const LegacyTimestampFailure(LegacyTimestampReason.invalid);
  }
  int number(int i) => int.parse(match.group(i)!);
  final year = number(1),
      month = number(2),
      day = number(3),
      hour = number(5),
      minute = number(6),
      second = number(7);
  final zone = match.group(9);
  if (match.group(4) == 'T' && zone == null ||
      match.group(4) == ' ' && zone != null) {
    throw const LegacyTimestampFailure(LegacyTimestampReason.invalid);
  }
  final base = DateTime.utc(year, month, day, hour, minute, second);
  if (base.year != year ||
      base.month != month ||
      base.day != day ||
      base.hour != hour ||
      base.minute != minute ||
      base.second != second) {
    throw const LegacyTimestampFailure(LegacyTimestampReason.invalid);
  }
  var offset = 0;
  if (zone != null && zone != 'Z') {
    final hours = int.parse(zone.substring(1, 3)),
        minutes = int.parse(zone.substring(4, 6));
    if (hours > 23 || minutes > 59) {
      throw const LegacyTimestampFailure(LegacyTimestampReason.invalid);
    }
    offset = (hours * 60 + minutes) * 60000 * (zone.startsWith('-') ? -1 : 1);
  }
  final fraction = match.group(8);
  final millis = fraction == null
      ? 0
      : int.parse(fraction.padRight(9, '0')) ~/ 1000000;
  // Adding a nonnegative fractional part to the exact second also reproduces
  // Go UnixMilli's floor for times before the Unix epoch.
  return base.millisecondsSinceEpoch - offset + millis;
}

int resolveLegacyImportTimestamp({
  required String modified,
  required String created,
  required String exported,
}) {
  final value =
      legacyImportTimestamp(modified) ??
      legacyImportTimestamp(created) ??
      legacyImportTimestamp(exported);
  if (value == null) {
    throw const LegacyTimestampFailure(LegacyTimestampReason.missing);
  }
  return value;
}
