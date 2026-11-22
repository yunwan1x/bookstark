import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';

void main() {
  const codec = StandardMethodCodec();
  const original = '\ufeff中文😀\r\nline two\nlast\r\n';
  test(
    'Actual standard codec consumes raw leading BOM but envelope retains exact source',
    () {
      final rawReply = codec.decodeEnvelope(
        codec.encodeSuccessEnvelope(original),
      );
      expect(rawReply, original.substring(1));
      final wrapped = jsonEncode({'content': original});
      final reply =
          codec.decodeEnvelope(codec.encodeSuccessEnvelope(wrapped)) as String;
      expect(adminFileDecodeEditorSnapshot(reply), original);
      expect(
        utf8.encode(adminFileDecodeEditorSnapshot(reply)),
        utf8.encode(original),
      );
    },
  );
  test(
    'No-BOM source and mixed endings are unchanged through actual codec',
    () {
      for (final source in [
        '',
        '中文😀\r\na\nb\r',
        'no newline',
        '\ufeff\ufefftwo',
      ]) {
        final reply =
            codec.decodeEnvelope(
                  codec.encodeSuccessEnvelope(jsonEncode({'content': source})),
                )
                as String;
        expect(adminFileDecodeEditorSnapshot(reply), source);
      }
    },
  );
  test('Malformed or invalid editor snapshots fail closed', () {
    for (final value in [
      'raw',
      'null',
      '{}',
      '{"content":4}',
      '{"content":"x","extra":1}',
      jsonEncode({'content': 'a\u0000b'}),
    ]) {
      expect(() => adminFileDecodeEditorSnapshot(value), throwsFormatException);
    }
  });
}
