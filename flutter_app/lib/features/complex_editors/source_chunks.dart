/// Small boundary index over an immutable source string.
///
/// Chunks are measured in UTF-16 code units to match String.substring while
/// ensuring a valid surrogate pair is never split between visible rows.
class SourceChunks {
  SourceChunks(this.source, {this.chunkSize = 4096})
    : assert(chunkSize > 1),
      boundaries = List<int>.unmodifiable(_buildBoundaries(source, chunkSize));

  final String source;
  final int chunkSize;
  final List<int> boundaries;

  int get length => boundaries.length - 1;

  String at(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return source.substring(boundaries[index], boundaries[index + 1]);
  }

  static int utf8ByteLength(String source) {
    var bytes = 0;
    var index = 0;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit <= 0x7f) {
        bytes++;
      } else if (unit <= 0x7ff) {
        bytes += 2;
      } else if (_isHighSurrogate(unit) &&
          index + 1 < source.length &&
          _isLowSurrogate(source.codeUnitAt(index + 1))) {
        bytes += 4;
        index++;
      } else {
        // Includes unpaired surrogates, encoded by Dart as U+FFFD.
        bytes += 3;
      }
      index++;
    }
    return bytes;
  }

  static List<int> _buildBoundaries(String source, int chunkSize) {
    final result = <int>[0];
    while (result.last < source.length) {
      final start = result.last;
      var end = (start + chunkSize).clamp(0, source.length);
      if (end < source.length &&
          end > start &&
          _isHighSurrogate(source.codeUnitAt(end - 1)) &&
          _isLowSurrogate(source.codeUnitAt(end))) {
        end--;
      }
      result.add(end);
    }
    return result;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
}
