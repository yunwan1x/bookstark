import 'dart:convert';

/// Scratch proposal: complete strict JSON/UTF8 validation with bounded list
/// metadata projection. Returns the ORIGINAL root envelope, before client unwrap.
/// No HTTP, credentials, SQLite or UI authority lives in this parser.
Future<Map<String, Object?>> readNotesListMetadataJson(
  Stream<List<int>> input, {
  int maxBytes = 128 * 1024 * 1024,
  int maxMetadataChars = 256 * 1024,
  int maxPreviewRunes = 512,
  int maxItems = 200,
  int maxDepth = 32,
  int maxFieldChars = 8192,
  int maxKeyChars = 512,
}) async {
  if (maxBytes <= 0 ||
      maxMetadataChars <= 0 ||
      maxPreviewRunes < 0 ||
      maxItems <= 0 ||
      maxDepth <= 0 ||
      maxFieldChars <= 0 ||
      maxKeyChars <= 0) {
    throw ArgumentError('Invalid list projection bounds');
  }
  final parser = _ListProjection(
    maxMetadataChars,
    maxPreviewRunes,
    maxItems,
    maxDepth,
    maxFieldChars,
    maxKeyChars,
  );
  var bytes = 0;
  final checked = input.map((chunk) {
    bytes += chunk.length;
    if (bytes > maxBytes) {
      throw const FormatException('Note list response exceeds read bound');
    }
    return chunk;
  });
  await for (final text in checked.transform(const Utf8Decoder())) {
    parser.add(text);
  }
  return parser.finish();
}

final class _ListFrame {
  _ListFrame(this.object, {this.rows = false});
  final bool object, rows;
  String state = 'valueOrEnd';
  String? key;
  final keys = <String>{};
  int items = 0;
}

final class _ListProjection {
  _ListProjection(
    this.limit,
    this.previewLimit,
    this.itemLimit,
    this.depthLimit,
    this.fieldLimit,
    this.keyLimit,
  );
  final int limit, previewLimit, itemLimit, depthLimit, fieldLimit, keyLimit;
  final _out = StringBuffer(), _token = StringBuffer();
  final _stack = <_ListFrame>[];
  int _size = 0,
      _tokenSize = 0,
      _runes = 0,
      _unicodeDigits = 0,
      _unicodeValue = 0;
  int? _highSurrogate;
  bool _string = false,
      _escape = false,
      _key = false,
      _drop = false,
      _preview = false;
  bool _rootDone = false, _primitive = false;
  Never _bad() =>
      throw const FormatException('Invalid note list metadata JSON');
  bool get _expectsValue => _stack.isEmpty
      ? !_rootDone
      : {'value', 'valueOrEnd'}.contains(_stack.last.state);
  bool get _bodyField =>
      _stack.isNotEmpty &&
      _stack.last.object &&
      {'blog_content', 'blog_desc'}.contains(_stack.last.key);
  void _write(String value) {
    _size += value.length;
    if (_size > limit) {
      throw const FormatException('Note list metadata exceeds read bound');
    }
    _out.write(value);
  }

  void _value() {
    if (!_expectsValue) _bad();
    if (_stack.isEmpty) {
      _rootDone = true;
    } else {
      final frame = _stack.last;
      if (!frame.object) {
        frame.items++;
        // The real API list is root.data; also accept one wrapper level while
        // retaining its envelope. Other arrays have their own bounded item cap.
        if (frame.items > (frame.rows ? itemLimit : 512)) _bad();
      }
      frame.state = 'comma';
    }
  }

  void _startString() {
    _key =
        _stack.isNotEmpty &&
        _stack.last.object &&
        {'key', 'keyOrEnd'}.contains(_stack.last.state);
    if (!_key && !_expectsValue) _bad();
    _drop = !_key && _bodyField;
    _preview =
        !_key &&
        _stack.isNotEmpty &&
        _stack.last.object &&
        _stack.last.key == 'content_preview';
    _token.clear();
    _tokenSize = 0;
    _runes = 0;
    _unicodeDigits = 0;
    _unicodeValue = 0;
    _highSurrogate = null;
    _escape = false;
    _string = true;
  }

  void _unit(int unit) {
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (_highSurrogate != null) _bad();
      _highSurrogate = unit;
      return;
    }
    var scalar = unit;
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      final high = _highSurrogate;
      if (high == null) _bad();
      scalar = 0x10000 + ((high - 0xd800) << 10) + unit - 0xdc00;
      _highSurrogate = null;
    } else if (_highSurrogate != null) {
      _bad();
    }
    _runes++;
    // Even discarded suffixes still pass every escape/control/Unicode check.
    if (_drop || (_preview && _runes > previewLimit)) return;
    _tokenSize += scalar > 0xffff ? 2 : 1;
    if (_tokenSize >
        (_key
            ? keyLimit
            : _preview
            ? previewLimit * 2
            : fieldLimit)) {
      throw const FormatException(
        'Note list metadata string exceeds read bound',
      );
    }
    _token.writeCharCode(scalar);
  }

  void _stringUnit(int c) {
    if (_unicodeDigits > 0) {
      final digit = c >= 48 && c <= 57
          ? c - 48
          : c >= 65 && c <= 70
          ? c - 55
          : c >= 97 && c <= 102
          ? c - 87
          : -1;
      if (digit < 0) _bad();
      _unicodeValue = (_unicodeValue << 4) | digit;
      if (--_unicodeDigits == 0) _unit(_unicodeValue);
      return;
    }
    if (_escape) {
      _escape = false;
      if (c == 117) {
        _unicodeDigits = 4;
        _unicodeValue = 0;
      } else {
        final value = switch (c) {
          34 => 34,
          92 => 92,
          47 => 47,
          98 => 8,
          102 => 12,
          110 => 10,
          114 => 13,
          116 => 9,
          _ => -1,
        };
        if (value < 0) _bad();
        _unit(value);
      }
      return;
    }
    if (c == 92) {
      _escape = true;
      return;
    }
    if (c == 34) {
      if (_highSurrogate != null) _bad();
      _string = false;
      final value = _token.toString();
      if (_key) {
        final frame = _stack.last;
        if (!frame.keys.add(value) || frame.keys.length > 128) _bad();
        frame.key = value;
        frame.state = 'colon';
      } else {
        _value();
      }
      _write(_drop ? 'null' : jsonEncode(value));
      return;
    }
    if (c < 32) _bad();
    _unit(c);
  }

  void _endPrimitive() {
    final raw = _token.toString();
    if (!RegExp(
      r'^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$',
    ).hasMatch(raw)) {
      _bad();
    }
    if (_bodyField && raw != 'null') _bad();
    if (!{'true', 'false', 'null'}.contains(raw)) {
      final number = num.tryParse(raw);
      if (number == null || !number.isFinite) _bad();
      // Preserve identities across Dart VM and JavaScript; do not silently round
      // an oversized integral ID in Web JSON decoding. Root may tighten by field.
      if (number.abs() > 9007199254740991) _bad();
      final field = _stack.isNotEmpty && _stack.last.object
          ? _stack.last.key
          : null;
      if ({
            'blog_id',
            'page',
            'page_size',
            'total',
            'total_pages',
            'code',
            'visibility',
            'is_pinned',
          }.contains(field) &&
          (raw.contains('.') || raw.contains('e') || raw.contains('E'))) {
        _bad();
      }
    }
    _write(raw);
    _value();
    _primitive = false;
    _token.clear();
  }

  void add(String text) {
    for (final c in text.codeUnits) {
      if (_string) {
        _stringUnit(c);
        continue;
      }
      if (_primitive) {
        if ({32, 9, 10, 13, 44, 93, 125}.contains(c)) {
          _endPrimitive();
        } else {
          if (_token.length >= 64) _bad();
          _token.writeCharCode(c);
          continue;
        }
      }
      if ({32, 9, 10, 13}.contains(c)) continue;
      if (c == 34) {
        _startString();
      } else if (c == 123 || c == 91) {
        if (_bodyField) _bad();
        final rows =
            c == 91 &&
            _stack.isNotEmpty &&
            _stack.length <= 2 &&
            _stack.last.object &&
            _stack.last.key == 'data';
        _value();
        if (_stack.length >= depthLimit) _bad();
        final frame = _ListFrame(c == 123, rows: rows);
        frame.state = frame.object ? 'keyOrEnd' : 'valueOrEnd';
        _stack.add(frame);
        _write(String.fromCharCode(c));
      } else if (c == 125 || c == 93) {
        if (_stack.isEmpty) _bad();
        final frame = _stack.last;
        if (frame.object != (c == 125) ||
            !{'comma', 'keyOrEnd', 'valueOrEnd'}.contains(frame.state)) {
          _bad();
        }
        _stack.removeLast();
        _write(String.fromCharCode(c));
      } else if (c == 58) {
        if (_stack.isEmpty ||
            !_stack.last.object ||
            _stack.last.state != 'colon') {
          _bad();
        }
        _stack.last.state = 'value';
        _write(':');
      } else if (c == 44) {
        if (_stack.isEmpty || _stack.last.state != 'comma') _bad();
        _stack.last.state = _stack.last.object ? 'key' : 'value';
        _write(',');
      } else {
        if (!_expectsValue) _bad();
        _primitive = true;
        _token.clear();
        _token.writeCharCode(c);
      }
    }
  }

  Map<String, Object?> finish() {
    if (_primitive) _endPrimitive();
    if (_string || _stack.isNotEmpty || !_rootDone) _bad();
    final decoded = jsonDecode(_out.toString());
    if (decoded is! Map<String, dynamic>) _bad();
    return Map<String, Object?>.from(decoded);
  }
}
