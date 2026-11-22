import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_legacy_json.dart';

Object? parse(
  String source, [
  LegacyJsonLimits limits = const LegacyJsonLimits(),
]) => decodeLegacyJson(utf8.encode(source), limits: limits);

void main() {
  test(
    'legacy JSON accepts full crypto transport strings above the old5MiB cap',
    () {
      final body = '\ufeff${'x' * (6 * 1024 * 1024)}';
      expect((parse(jsonEncode({'body': body})) as Map)['body'], body);
      expect(
        () => parse(
          jsonEncode({'body': body}),
          const LegacyJsonLimits(maxStringBytes: 5 * 1024 * 1024),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Go-style pretty JSON retains exact body bytes and nested unknown fields',
    () {
      const body = '\uFEFF# 原文😀\r\n{"future": [1, true, null]}';
      final wire = const JsonEncoder.withIndent('  ').convert({
        'blog_content': body,
        'future': {
          'version': 7,
          'styles': ['comma,label', '资料'],
        },
        'id': 9223372036854775807,
      });
      final value = parse(wire) as Map<String, Object?>;
      expect(value['blog_content'], body);
      expect(value['id'], 9223372036854775807);
      expect(value['future'], {
        'version': 7,
        'styles': ['comma,label', '资料'],
      });
    },
  );

  test(
    'duplicate keys including escaped aliases never silently replace content',
    () {
      for (final wire in [
        '{"content":"first","content":"second"}',
        r'{"a":1,"\u0061":2}',
        '{"nested":{"x":null,"x":false}}',
      ]) {
        expect(() => parse(wire), throwsFormatException);
      }
    },
  );

  test('unpaired Unicode escapes and invalid UTF-8 are refused', () {
    for (final wire in [
      r'{"x":"\uD800"}',
      r'{"x":"\uDC00"}',
      r'{"x":"\uD800\u0041"}',
      r'{"x":"\u+123"}',
    ]) {
      expect(() => parse(wire), throwsFormatException);
    }
    expect(() => decodeLegacyJson([0xff]), throwsFormatException);
    expect(parse(r'{"x":"\uD83D\uDE00"}'), {'x': '😀'});
  });

  test('malformed structure, raw controls and trailing input are rejected', () {
    for (final wire in [
      '',
      '{"x":}',
      '[1,]',
      '{"x":1,}',
      '{"x"\n1}',
      'true false',
      '{"x":"raw\nline"}',
      '{1:"x"}',
    ]) {
      expect(() => parse(wire), throwsFormatException);
    }
  });

  test('file BOM is tolerated without removing a BOM from a body value', () {
    expect(parse('\uFEFF{"body":"\\uFEFF# text\\r\\n"}'), {
      'body': '\uFEFF# text\r\n',
    });
  });

  test('numeric grammar never rounds a too-large integer into an ID', () {
    for (final wire in [
      '01',
      '+1',
      '1.',
      '.1',
      '1e',
      '1e+',
      '1e999',
      '9223372036854775808',
      'NaN',
      'Infinity',
    ]) {
      expect(() => parse(wire), throwsFormatException);
    }
    expect(parse('[-1,0,1.5,1e2,true,false,null]'), [
      -1,
      0,
      1.5,
      100.0,
      true,
      false,
      null,
    ]);
  });

  test(
    'each structural or allocation budget rejects before accepting input',
    () {
      expect(
        () => parse('{"a":{"b":1}}', const LegacyJsonLimits(maxDepth: 1)),
        throwsFormatException,
      );
      expect(
        () => parse('[0,1]', const LegacyJsonLimits(maxArrayLength: 1)),
        throwsFormatException,
      );
      expect(
        () =>
            parse('{"a":1,"b":2}', const LegacyJsonLimits(maxObjectMembers: 1)),
        throwsFormatException,
      );
      expect(
        () => parse('[0,1]', const LegacyJsonLimits(maxNodes: 2)),
        throwsFormatException,
      );
      expect(
        () => parse('"资料"', const LegacyJsonLimits(maxStringBytes: 5)),
        throwsFormatException,
      );
      expect(
        () => parse(
          '"12345"',
          const LegacyJsonLimits(maxEncodedStringCharacters: 4),
        ),
        throwsFormatException,
      );
      expect(
        () => parse('{"a":1}', const LegacyJsonLimits(maxBytes: 6)),
        throwsFormatException,
      );
    },
  );

  test(
    'failure messages never include source bodies or credential-like values',
    () {
      try {
        parse('{"password":"sentinel-secret","password":"other"}');
        fail('duplicate was accepted');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('sentinel-secret')));
        expect(error.toString(), isNot(contains('password')));
      }
    },
  );
}
