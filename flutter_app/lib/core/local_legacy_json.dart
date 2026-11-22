import 'dart:convert';
import 'local_content_crypto_limits.dart';

/// Bounded legacy input with duplicate-key and Unicode validation.
/// A file-level UTF-8 BOM is accepted; BOMs inside values remain unchanged.
/// Errors intentionally contain an offset rather than source values.
class LegacyJsonLimits {
  const LegacyJsonLimits({
    this.maxBytes = 64 * 1024 * 1024,
    this.maxStringBytes = localCryptoMaxWireBytes,
    this.maxEncodedStringCharacters = 64 * 1024 * 1024,
    this.maxDepth = 48,
    this.maxNodes = 1000000,
    this.maxObjectMembers = 256,
    this.maxArrayLength = 100000,
  });
  final int maxBytes, maxStringBytes, maxEncodedStringCharacters;
  final int maxDepth, maxNodes, maxObjectMembers, maxArrayLength;
}

Object? decodeLegacyJson(
  List<int> bytes, {
  LegacyJsonLimits limits = const LegacyJsonLimits(),
}) {
  if ([
    limits.maxBytes,
    limits.maxStringBytes,
    limits.maxEncodedStringCharacters,
    limits.maxDepth,
    limits.maxNodes,
    limits.maxObjectMembers,
    limits.maxArrayLength,
  ].any((value) => value <= 0)) {
    throw ArgumentError('Positive legacy JSON limits required');
  }
  if (bytes.length > limits.maxBytes) {
    throw const FormatException('Legacy JSON exceeds its input limit');
  }
  String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const FormatException('Legacy JSON must contain valid UTF-8');
  }
  return _LegacyJsonReader(source, limits).read();
}

class _LegacyJsonReader {
  _LegacyJsonReader(this.source, this.limits);
  final String source;
  final LegacyJsonLimits limits;
  int at = 0, nodes = 0;
  int get peek => at < source.length ? source.codeUnitAt(at) : -1;
  Never fail() => throw FormatException('Invalid legacy JSON at offset $at');
  bool digit(int value) => value >= 0x30 && value <= 0x39;
  bool high(int value) => value >= 0xd800 && value <= 0xdbff;
  bool low(int value) => value >= 0xdc00 && value <= 0xdfff;
  void space() {
    while (peek == 0x20 || peek == 0x09 || peek == 0x0a || peek == 0x0d) {
      at++;
    }
  }

  void expect(int value) {
    space();
    if (peek != value) fail();
    at++;
  }

  Object? read() {
    final value = readValue(0);
    space();
    if (at != source.length) fail();
    return value;
  }

  Object? readValue(int depth) {
    if (depth > limits.maxDepth || ++nodes > limits.maxNodes) fail();
    space();
    switch (peek) {
      case 0x7b:
        return object(depth);
      case 0x5b:
        return array(depth);
      case 0x22:
        return string();
      case 0x74:
        return literal('true', true);
      case 0x66:
        return literal('false', false);
      case 0x6e:
        return literal('null', null);
      default:
        return number();
    }
  }

  Object? literal(String word, Object? value) {
    if (!source.startsWith(word, at)) fail();
    at += word.length;
    return value;
  }

  Map<String, Object?> object(int depth) {
    at++;
    final result = <String, Object?>{};
    space();
    if (peek == 0x7d) {
      at++;
      return result;
    }
    while (true) {
      space();
      if (peek != 0x22 || result.length >= limits.maxObjectMembers) fail();
      final key = string(key: true);
      if (result.containsKey(key)) fail();
      expect(0x3a);
      result[key] = readValue(depth + 1);
      space();
      if (peek == 0x7d) {
        at++;
        return result;
      }
      expect(0x2c);
    }
  }

  List<Object?> array(int depth) {
    at++;
    final result = <Object?>[];
    space();
    if (peek == 0x5d) {
      at++;
      return result;
    }
    while (true) {
      if (result.length >= limits.maxArrayLength) fail();
      result.add(readValue(depth + 1));
      space();
      if (peek == 0x5d) {
        at++;
        return result;
      }
      expect(0x2c);
    }
  }

  int hex4() {
    if (at + 4 > source.length) fail();
    final value = int.tryParse(source.substring(at, at + 4), radix: 16);
    if (value == null) fail();
    // int.tryParse also accepts a sign; JSON Unicode escapes do not.
    for (var i = at; i < at + 4; i++) {
      final value = source.codeUnitAt(i);
      if (!(digit(value) ||
          value >= 0x41 && value <= 0x46 ||
          value >= 0x61 && value <= 0x66)) {
        fail();
      }
    }
    at += 4;
    return value;
  }

  String string({bool key = false}) {
    final start = at++;
    while (true) {
      if (at - start > limits.maxEncodedStringCharacters || peek < 0x20) {
        fail();
      }
      final value = peek;
      at++;
      if (value == 0x22) break;
      if (value == 0x5c) {
        final escaped = peek;
        at++;
        if (escaped == 0x75) {
          final unit = hex4();
          if (high(unit)) {
            if (peek != 0x5c ||
                at + 1 >= source.length ||
                source.codeUnitAt(at + 1) != 0x75) {
              fail();
            }
            at += 2;
            if (!low(hex4())) fail();
          } else if (low(unit)) {
            fail();
          }
        } else if (!const {
          0x22,
          0x5c,
          0x2f,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        }.contains(escaped)) {
          fail();
        }
      } else if (high(value)) {
        if (!low(peek)) fail();
        at++;
      } else if (low(value)) {
        fail();
      }
    }
    String result;
    try {
      result = jsonDecode(source.substring(start, at)) as String;
    } on FormatException {
      fail();
    }
    if (utf8.encode(result).length > (key ? 1024 : limits.maxStringBytes)) {
      fail();
    }
    return result;
  }

  num number() {
    final start = at;
    if (peek == 0x2d) at++;
    if (peek == 0x30) {
      at++;
      if (digit(peek)) fail();
    } else {
      if (peek < 0x31 || peek > 0x39) fail();
      while (digit(peek)) {
        at++;
        if (at - start > 64) fail();
      }
    }
    if (peek == 0x2e) {
      at++;
      if (!digit(peek)) fail();
      while (digit(peek)) {
        at++;
        if (at - start > 64) fail();
      }
    }
    if (peek == 0x65 || peek == 0x45) {
      at++;
      if (peek == 0x2b || peek == 0x2d) at++;
      if (!digit(peek)) fail();
      while (digit(peek)) {
        at++;
        if (at - start > 64) fail();
      }
    }
    final token = source.substring(start, at);
    num value;
    try {
      value = jsonDecode(token) as num;
    } on FormatException {
      fail();
    }
    if (!value.isFinite ||
        !token.contains('.') &&
            !token.contains('e') &&
            !token.contains('E') &&
            value is! int) {
      fail();
    }
    return value;
  }
}
