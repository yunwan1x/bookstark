import 'dart:convert';

/// Validates body strings incrementally, discarding them before JSON decoding.
Future<Map<String, Object?>> readArticleMetadataJson(
  Stream<List<int>> input, {
  int maxBytes = 128 * 1024 * 1024,
  int maxMetadataChars = 128 * 1024,
}) async {
  final parser = _MetadataProjection(maxMetadataChars);
  var bytes = 0;
  final checked = input.map((chunk) {
    bytes += chunk.length;
    if (bytes > maxBytes) {
      throw const FormatException('Article response exceeds read bound');
    }
    return chunk;
  });
  await for (final text in checked.transform(const Utf8Decoder())) {
    parser.add(text);
  }
  return parser.finish();
}

final class _Frame {
  _Frame(this.object);
  final bool object;
  String state = 'valueOrEnd';
  String? key;
  final keys = <String>{};
}

final class _MetadataProjection {
  _MetadataProjection(this.limit);
  final int limit;
  final _out = StringBuffer();
  final _token = StringBuffer();
  final _stack = <_Frame>[];
  int _size = 0, _tokenSize = 0, _unicode = 0;
  bool _string = false, _escape = false, _key = false, _drop = false;
  bool _rootDone = false, _primitive = false;

  Never _bad() => throw const FormatException('Invalid article metadata JSON');
  void _write(String value) {
    _size += value.length;
    if (_size > limit) {
      throw const FormatException('Article metadata exceeds read bound');
    }
    _out.write(value);
  }

  bool get _expectsValue => _stack.isEmpty
      ? !_rootDone
      : {'value', 'valueOrEnd'}.contains(_stack.last.state);
  void _value() {
    if (!_expectsValue) _bad();
    if (_stack.isEmpty) {
      _rootDone = true;
    } else {
      _stack.last.state = 'comma';
    }
  }

  void _startString() {
    _key =
        _stack.isNotEmpty &&
        _stack.last.object &&
        {'key', 'keyOrEnd'}.contains(_stack.last.state);
    if (!_key && !_expectsValue) _bad();
    _drop =
        !_key &&
        _stack.isNotEmpty &&
        _stack.last.object &&
        {'blog_content', 'blog_desc'}.contains(_stack.last.key);
    _token.clear();
    _tokenSize = 0;
    _unicode = 0;
    _escape = false;
    _string = true;
  }

  void _stringChar(int c) {
    if (_unicode > 0) {
      if (!((c >= 48 && c <= 57) ||
          (c >= 65 && c <= 70) ||
          (c >= 97 && c <= 102))) {
        _bad();
      }
      _unicode--;
    } else if (_escape) {
      _escape = false;
      if (c == 117) {
        _unicode = 4;
      } else if (![34, 92, 47, 98, 102, 110, 114, 116].contains(c)) {
        _bad();
      }
    } else if (c == 92) {
      _escape = true;
    } else if (c == 34) {
      _string = false;
      if (_key) {
        final key = jsonDecode('"${_token.toString()}"') as String;
        final frame = _stack.last;
        if (!frame.keys.add(key)) _bad();
        frame.key = key;
        frame.state = 'colon';
      } else {
        _value();
      }
      _write(_drop ? 'null' : '"${_token.toString()}"');
      return;
    } else if (c < 32) {
      _bad();
    }
    if (!_drop) {
      _tokenSize++;
      if (_tokenSize > (_key ? 512 : 8192)) {
        throw const FormatException(
          'Article metadata string exceeds read bound',
        );
      }
      _token.writeCharCode(c);
    }
  }

  void _endPrimitive() {
    final raw = _token.toString();
    if (!RegExp(
      r'^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$',
    ).hasMatch(raw)) {
      _bad();
    }
    _write(raw);
    _value();
    _primitive = false;
    _token.clear();
  }

  void add(String text) {
    for (final c in text.codeUnits) {
      if (_string) {
        _stringChar(c);
        continue;
      }
      if (_primitive) {
        if (c == 32 ||
            c == 9 ||
            c == 10 ||
            c == 13 ||
            c == 44 ||
            c == 93 ||
            c == 125) {
          _endPrimitive();
        } else {
          if (_token.length >= 64) _bad();
          _token.writeCharCode(c);
          continue;
        }
      }
      if (c == 32 || c == 9 || c == 10 || c == 13) continue;
      if (c == 34) {
        _startString();
      } else if (c == 123 || c == 91) {
        if (_stack.isNotEmpty &&
            _stack.last.object &&
            {'blog_content', 'blog_desc'}.contains(_stack.last.key)) {
          _bad();
        }
        _value();
        if (_stack.length >= 32) _bad();
        final frame = _Frame(c == 123);
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
