import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/server_events.dart';

void main() {
  test(
    'SSE reconstructs Chinese UTF8 split at every byte with CRLF and multiline data',
    () async {
      final bytes = utf8.encode(
        '\uFEFF: comment\r\nevent: delta\r\ndata: {"text":\r\ndata: "中文"}\r\n\r\nevent: done\ndata: {"code":0}\n\n',
      );
      final events = await decodeServerEvents(
        Stream.fromIterable(bytes.map((byte) => [byte])),
      ).toList();
      expect(events.map((event) => event.type), ['delta', 'done']);
      expect(jsonDecode(events.first.data), {'text': '中文'});
      expect(jsonDecode(events.last.data), {'code': 0});
    },
  );
  test(
    'partial EOF is not dispatched and limits reject unbounded events',
    () async {
      final partial = await decodeServerEvents(
        Stream.value(utf8.encode('event: done\ndata: {"code":0}')),
      ).toList();
      expect(partial, isEmpty);
      await expectLater(
        decodeServerEvents(
          Stream.value(utf8.encode('data: too long\n\n')),
          maxEventBytes: 5,
        ).toList(),
        throwsFormatException,
      );
      await expectLater(
        decodeServerEvents(
          Stream.value(List.filled(20, 65)),
          maxTotalBytes: 10,
        ).toList(),
        throwsFormatException,
      );
    },
  );
  test('cancelling event subscription cancels source stream', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final events = decodeServerEvents(source.stream).take(1).toList();
    source.add(utf8.encode('event: delta\ndata: first\n\n'));
    expect((await events).single.data, 'first');
    expect(cancelled, isTrue);
    await source.close();
  });
}
