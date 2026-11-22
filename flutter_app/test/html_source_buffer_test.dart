import 'package:bookstark_flutter/core/html_source_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'no edit and selection-only values preserve all original newline bytes',
    () {
      const raw =
          '<html>\r\n<p>你好 👩‍💻</p>\n<script>run()</script>\r</html>\r\n';
      final b = HtmlSourceBuffer(raw);
      expect(b.apply(b.text), raw);
      expect(b.source, raw);
    },
  );
  test(
    'single Unicode edit retains preceding and following mixed line endings',
    () {
      final b = HtmlSourceBuffer('one\r\ntwo 😀\nthree\rfour');
      expect(b.apply('one\ntwo 🌍\nthree\nfour'), 'one\r\ntwo 🌍\nthree\rfour');
    },
  );
  test('multiple replacements preserve mixed endings within changed span', () {
    final b = HtmlSourceBuffer('foo\r\nfoo\nfoo\rfoo');
    expect(b.apply(b.text.replaceAll('foo', 'bar')), 'bar\r\nbar\nbar\rbar');
  });
  test(
    'inserted lines use original preferred ending, deletion keeps surrounding bytes',
    () {
      final b = HtmlSourceBuffer('a\r\nb\r\nc');
      expect(b.apply('a\nnew\nb\nc'), 'a\r\nnew\r\nb\r\nc');
      expect(b.apply('a\nb\nc'), 'a\r\nb\r\nc');
    },
  );
  test('empty content and appended final newline are exact', () {
    final b = HtmlSourceBuffer('');
    expect(b.apply('你好\n'), '你好\n');
    expect(b.apply(''), '');
  });
}
