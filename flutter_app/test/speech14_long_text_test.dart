import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/speech_text.dart';

void main() {
  test('long single paragraph preserves all Unicode beyond old20k cap', () {
    final text = List.filled(30000, '𠮷🙂字').join();
    final pieces = speechSegments(text);
    expect(pieces.join(), text);
    expect(pieces.every((p) => p.runes.length <= 200), isTrue);
    expect(pieces.length, greaterThan(100));
  });
  test('oversized input rejects explicitly rather than silently trimming', () {
    expect(
      () => speechSegments('a' * (20 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('fences and script are not spoken in long text', () {
    final text = List.filled(300, '段落正文。').join();
    final result = speechSegments(
      '$text\n\n```\nsecret code\n```\n<script>hidden</script>',
    ).join();
    expect(result.contains('secret'), isFalse);
    expect(result.contains('hidden'), isFalse);
    expect(result, text);
  });
  test(
    'exact 20MiB raw UTF8 budget accepted; stripped payload never expands speech queue',
    () {
      const budget = 20 * 1024 * 1024, tail = '𠮷🙂字';
      const prefix = '<script>', suffix = '</script>';
      final source =
          prefix +
          ('x' * (budget - utf8.encode(prefix + suffix + tail).length)) +
          suffix +
          tail;
      expect(utf8.encode(source).length, budget);
      expect(speechSegments(source), [tail]);
    },
  );
  test('UTF8 byte overflow rejected even when UTF16 stays below budget', () {
    const budget = 20 * 1024 * 1024;
    final source = '字' * (budget ~/ 3 + 1);
    expect(source.length, lessThan(budget));
    expect(utf8.encode(source).length, greaterThan(budget));
    expect(() => speechSegments(source), throwsFormatException);
  });
}
