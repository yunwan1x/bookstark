import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/speech_stream.dart';
import 'package:bookstark_flutter/core/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'speech respects paragraph boundaries and decodes readable entities',
    () {
      expect(speechSegments('第一段。\n\n第二段。'), ['第一段。', '第二段。']);
      expect(speechSegments('A &amp; B').single, 'A & B');
    },
  );
  test('speech audio is delivered before done and transport EOF', () async {
    final input = StreamController<List<int>>();
    final output = StreamIterator(decodeSpeechAudio(input.stream));
    final first = output.moveNext();
    input.add(utf8.encode('{"event":"audio","data":"AQID"}\n'));
    expect(await first, isTrue);
    expect(output.current, [1, 2, 3]);
    // Synthesis is still open: no done frame was sent or buffered first.
    final end = output.moveNext();
    input.add(utf8.encode('{"event":"done","bytes":3}\n'));
    await input.close();
    expect(await end, isFalse);
    await output.cancel();
  });
  test(
    'speech NDJSON handles arbitrary byte splits CRLF and blank lines',
    () async {
      final bytes = utf8.encode(
        '\r\n{"event":"audio","data":"AQID"}\r\n{"event":"audio","data":"BAU="}\n{"event":"done","bytes":5}',
      );
      final result = await decodeSpeechAudio(
        Stream.fromIterable(bytes.map((byte) => [byte])),
      ).toList();
      expect(result, [
        [1, 2, 3],
        [4, 5],
      ]);
    },
  );
  test(
    'speech completion, errors, unknown frames and bounds are enforced',
    () async {
      for (final text in [
        '{"event":"audio","data":"AQID"}\n',
        '{"event":"done","bytes":0}\n',
        '{"event":"audio","data":"AQID"}\n{"event":"done","bytes":2}\n',
        '{"event":"audio","data":"AQID"}\n{"event":"done","bytes":3.0}\n',
        '{"event":"audio","data":"AQID"}\n{"event":"done","bytes":3}\n{"event":"done","bytes":3}\n',
        '{"event":"audio","data":"***"}\n',
        '{"event":"audio","data":""}\n',
        '{"event":"unexpected"}\n',
        '${jsonEncode({'event': 'audio', 'data': base64Encode(List.filled(16385, 0))})}\n',
      ]) {
        await expectLater(
          decodeSpeechAudio(Stream.value(utf8.encode(text))).toList(),
          throwsFormatException,
        );
      }
      await expectLater(
        decodeSpeechAudio(
          Stream.value(utf8.encode('{"event":"error"}\n')),
        ).toList(),
        throwsStateError,
      );
      await expectLater(
        decodeSpeechAudio(
          Stream.value(List.filled(2 * 1024 * 1024 + 1, 65)),
        ).toList(),
        throwsFormatException,
      );
    },
  );
  test(
    'speech extraction skips code images HTML scripts URLs and respects Unicode boundaries',
    () {
      final segments = speechSegments(
        '# 标题\n\n正文 **保留** [链接名称](https://example.test) ![图片](https://example.test/p.png)\n\n```dart\nsecret_code();\n```\n\n<script>secret_script()</script>\n\n- 第二段',
      );
      final text = segments.join('\n');
      expect(text, contains('链接名称'));
      expect(text, contains('第二段'));
      for (final excluded in [
        'secret_code',
        'secret_script',
        'https://',
        '图片',
      ]) {
        expect(text, isNot(contains(excluded)));
      }
      final emoji = List.filled(450, '📖').join();
      final split = speechSegments(emoji);
      expect(split.map((part) => part.runes.length), [200, 200, 50]);
      expect(split.join(), emoji);
      expect(() => speechSegments('```\ncode\n```'), throwsFormatException);
      final beyondOldLimit = List.filled(20001, '字').join();
      final complete = speechSegments(beyondOldLimit);
      expect(complete.join(), beyondOldLimit);
      expect(complete.every((part) => part.runes.length <= 200), isTrue);
    },
  );
}
