/// The code editor displays logical LF lines, while stored HTML retains its
/// original newline bytes. Unchanged text and selection-only events are inert.
class HtmlSourceBuffer {
  HtmlSourceBuffer(String source) : _source = source;
  String _source;
  String get source => _source;
  static final _break = RegExp(r'\r\n|\r|\n');
  static String normalize(String value) => value.replaceAll(_break, '\n');
  String get text => normalize(_source);

  String apply(String edited) {
    edited = normalize(edited);
    final before = text;
    if (edited == before) return _source;
    var start = 0;
    while (start < before.length &&
        start < edited.length &&
        before.codeUnitAt(start) == edited.codeUnitAt(start)) {
      start++;
    }
    var suffix = 0;
    while (suffix < before.length - start &&
        suffix < edited.length - start &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            edited.codeUnitAt(edited.length - 1 - suffix)) {
      suffix++;
    }
    int rawOffset(int normalized) {
      var logical = 0, raw = 0;
      while (logical < normalized) {
        if (_source.codeUnitAt(raw) == 13 &&
            raw + 1 < _source.length &&
            _source.codeUnitAt(raw + 1) == 10) {
          raw++;
        }
        raw++;
        logical++;
      }
      return raw;
    }

    final rawStart = rawOffset(start),
        rawEnd = rawOffset(before.length - suffix);
    final removed = _source.substring(rawStart, rawEnd);
    final inserted = edited.substring(start, edited.length - suffix);
    final previousBreaks = _break
        .allMatches(removed)
        .map((m) => m.group(0)!)
        .toList();
    final count = '\n'.allMatches(inserted).length;
    final preferred = _break.firstMatch(_source)?.group(0) ?? '\n';
    var index = 0;
    final replacement = inserted.replaceAllMapped(RegExp('\n'), (_) {
      // Replacing several words without adding/removing lines retains every
      // mixed line ending in that span, rather than normalizing the whole file.
      return previousBreaks.length == count
          ? previousBreaks[index++]
          : preferred;
    });
    _source =
        _source.substring(0, rawStart) +
        replacement +
        _source.substring(rawEnd);
    assert(normalize(_source) == edited);
    return _source;
  }
}
