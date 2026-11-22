/// Matches the shipped Go search's ASCII whole-word post-filter.
bool isAsciiSearchWord(String query) =>
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(query);
bool matchesSearchWord(String text, String query) => RegExp(
  '(^|[^A-Za-z0-9_])${RegExp.escape(query)}'
  r'($|[^A-Za-z0-9_])',
  caseSensitive: false,
).hasMatch(text);

/// Bounded-memory counterpart of BookStark's current search snippet contract.
String searchSnippet(String text, String query) {
  if (text.isEmpty) return '';
  final match = RegExp(
    RegExp.escape(query),
    caseSensitive: false,
  ).firstMatch(text);
  final stats = _runeStats(text, match?.start);
  final totalRunes = stats.$1;
  if (match == null) {
    return totalRunes <= 150 ? text : '${_sliceRunes(text, 0, 150)}...';
  }
  final matchRuneIndex = stats.$2;
  final queryRuneCount = _runeCount(query);
  final half = (150 - queryRuneCount) ~/ 2;
  var start = (matchRuneIndex - half).clamp(0, totalRunes);
  var end = start + 150;
  if (end > totalRunes) {
    end = totalRunes;
    start = (end - 150).clamp(0, totalRunes);
  }
  return '${start > 0 ? '...' : ''}'
      '${_sliceRunes(text, start, end)}'
      '${end < totalRunes ? '...' : ''}';
}

(int, int) _runeStats(String value, int? targetCodeUnitOffset) {
  var count = 0;
  var offset = 0;
  var targetRuneIndex = 0;
  var targetSeen = targetCodeUnitOffset == null;
  while (offset < value.length) {
    if (!targetSeen && offset == targetCodeUnitOffset) {
      targetRuneIndex = count;
      targetSeen = true;
    }
    final width = _runeCodeUnitWidth(value, offset);
    if (!targetSeen &&
        targetCodeUnitOffset! > offset &&
        targetCodeUnitOffset < offset + width) {
      // A regex may match a single UTF-16 code unit within a surrogate pair.
      // The old substring(...).runes.length counts that partial pair as one.
      targetRuneIndex = count + 1;
      targetSeen = true;
    }
    offset += width;
    count++;
  }
  if (!targetSeen) targetRuneIndex = count;
  return (count, targetRuneIndex);
}

int _runeCount(String value) => _runeStats(value, null).$1;

String _sliceRunes(String value, int startRune, int endRune) {
  var offset = 0;
  var runeIndex = 0;
  var startOffset = startRune == 0 ? 0 : -1;
  while (runeIndex < endRune) {
    if (runeIndex == startRune) startOffset = offset;
    offset += _runeCodeUnitWidth(value, offset);
    runeIndex++;
  }
  if (startOffset < 0) startOffset = offset;
  return value.substring(startOffset, offset);
}

int _runeCodeUnitWidth(String value, int offset) {
  final first = value.codeUnitAt(offset);
  if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < value.length) {
    final second = value.codeUnitAt(offset + 1);
    if (second >= 0xDC00 && second <= 0xDFFF) return 2;
  }
  return 1;
}
