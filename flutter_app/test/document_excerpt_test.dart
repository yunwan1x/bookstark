import 'dart:convert';
import 'package:bookstark_flutter/core/document_excerpt.dart';
import 'package:bookstark_flutter/core/reading_position_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'excerpt preserves literal selection and UTF8 title bound with safe source URL prefix',
    () {
      final note = documentExcerpt(
        quote: '中文 [文本](链接)\n**不是新语法** 📖',
        name: List.filled(90, '📖').join(),
        path: '书籍 / 父章节',
        bookIdentify: 'book/with space',
        documentId: 2,
        server: Uri.parse('https://example.test/prefix'),
      );
      expect(note.id, isNull);
      expect(utf8.encode(note.title).length, lessThanOrEqualTo(200));
      expect(note.content, contains('> 中文 \\[文本\\]\\(链接\\)'));
      expect(note.content, contains('> \\*\\*不是新语法\\*\\* 📖'));
      final link = note.content.substring(
        note.content.indexOf('(<') + 2,
        note.content.indexOf('>)'),
      );
      final uri = Uri.parse(link);
      expect(uri.pathSegments, ['prefix', 'books', 'book/with space', 'edit']);
      expect(uri.queryParameters, {'doc': '2'});
      expect(
        () => documentExcerpt(
          quote: '',
          name: '文档',
          path: '书',
          bookIdentify: 'b',
          documentId: 1,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'reading position storage isolates user/document and rejects corrupt fractions',
    () async {
      final data = <String, String>{};
      ReadingPositionVault vault(String space) => ReadingPositionVault(
        namespace: space,
        readValue: (key) async => data[key],
        writeValue: (key, value) async {
          data[key] = value;
        },
        deleteValue: (key) async {
          data.remove(key);
        },
      );
      await vault('user1').write(2, const ReadingPosition(0.6, '2026-11-04'));
      expect((await vault('user1').read(2))!.fraction, 0.6);
      expect(await vault('user2').read(2), isNull);
      expect(await vault('user1').read(3), isNull);
      data[data.keys.single] = '{"version":1,"fraction":1.1,"modified_at":""}';
      await expectLater(vault('user1').read(2), throwsFormatException);
      expect(
        () => vault('user1').write(2, const ReadingPosition(double.nan, '')),
        throwsFormatException,
      );
    },
  );
}
