// Draft only: no toolchain/device execution.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/bookmark_favicon_store.dart';

Uint8List png() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDZYAAAAASUVORK5CYII=',
);
void main() {
  test(
    'explicit URLs only; LAN allowed; credential bookmark body untouched',
    () {
      for (final url in [
        '',
        '/favicon.ico',
        'data:image/png;base64,xx',
        'https://user:secret@example.invalid/icon.png',
        'https://example.invalid/x#fragment',
      ]) {
        expect(explicitBookmarkFavicon(url), isNull);
      }
      expect(
        explicitBookmarkFavicon('http://192.168.200.2:8080/icon.png'),
        isNotNull,
      );
      const item = BookmarkItem(
        title: 'Old',
        url: 'https://user:secret@old.invalid/page',
        favicon: '',
      );
      expect(item.url, 'https://user:secret@old.invalid/page');
      expect(item.favicon, isEmpty);
    },
  );
  test(
    'anonymous headers no redirects; dedup and memory cache no derived URL',
    () async {
      var requests = 0;
      final store = BookmarkFaviconStore(
        anonymousTestFactory: () => MockClient((r) async {
          requests++;
          expect(
            r.url.toString(),
            'https://icons.invalid/icon.png?signature=opaque',
          );
          expect(r.followRedirects, false);
          for (final h in [
            'cookie',
            'authorization',
            'x-csrf-token',
            'referer',
          ]) {
            expect(r.headers.containsKey(h), false);
          }
          return http.Response.bytes(
            png(),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final a = store.read('https://icons.invalid/icon.png?signature=opaque');
      final b = store.read('https://icons.invalid/icon.png?signature=opaque');
      expect(await a, isNotNull);
      expect(await b, isNotNull);
      expect(
        await store.read('https://icons.invalid/icon.png?signature=opaque'),
        isNotNull,
      );
      expect(requests, 1);
      expect(await store.read(''), isNull);
      expect(requests, 1);
      store.retire();
      expect(await store.read('https://icons.invalid/icon.png'), isNull);
    },
  );
  test(
    'bad media redirects encoding byte and dimension bounds stable fallback',
    () async {
      final huge = png();
      ByteData.sublistView(huge).setUint32(16, 513);
      final variants = [
        http.Response.bytes(
          png(),
          302,
          headers: {
            'content-type': 'image/png',
            'location': 'https://other.invalid',
          },
        ),
        http.Response(
          '<svg/>',
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
        http.Response.bytes(
          png(),
          200,
          headers: {'content-type': 'image/png', 'content-encoding': 'gzip'},
        ),
        http.Response.bytes(
          List.filled(256 * 1024 + 1, 0),
          200,
          headers: {'content-type': 'image/png'},
        ),
        http.Response.bytes(huge, 200, headers: {'content-type': 'image/png'}),
        http.Response.bytes(
          [0, 1, 2],
          200,
          headers: {'content-type': 'image/png'},
        ),
      ];
      for (final response in variants) {
        var count = 0;
        final store = BookmarkFaviconStore(
          anonymousTestFactory: () => MockClient((_) async {
            count++;
            return response;
          }),
        );
        expect(await store.read('https://icon.invalid/a'), isNull);
        expect(await store.read('https://icon.invalid/a'), isNull);
        expect(count, 1);
        store.retire();
      }
    },
  );
  test('ICO embedded PNG only; truncated directory fails', () {
    final frame = png(), ico = Uint8List(22 + png().length), d = ByteData(22);
    d.setUint16(2, 1, Endian.little);
    d.setUint16(4, 1, Endian.little);
    d.setUint32(14, frame.length, Endian.little);
    d.setUint32(18, 22, Endian.little);
    ico.setAll(0, d.buffer.asUint8List());
    ico.setAll(22, frame);
    expect(boundedBookmarkRaster(ico), frame);
    expect(
      () => boundedBookmarkRaster(Uint8List.fromList([0, 0, 1, 0, 1, 0])),
      throwsFormatException,
    );
  });
  test(
    'two active, bounded pending, retire settles queued and active jobs',
    () async {
      var active = 0, peak = 0;
      final store = BookmarkFaviconStore(
        anonymousTestFactory: () => _HeadersNeverClient(
          () {
            active++;
            if (active > peak) peak = active;
          },
          () {
            active--;
          },
        ),
      );
      final work = [
        for (var i = 0; i < 70; i++)
          store.read('http://192.168.200.2/icon$i.png'),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(peak, 2);
      store.retire();
      expect((await Future.wait(work)).every((v) => v == null), true);
    },
  );
  test('LRU cache entries bounded to32', () async {
    var count = 0;
    final store = BookmarkFaviconStore(
      anonymousTestFactory: () => MockClient((_) async {
        count++;
        return http.Response.bytes(
          png(),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    for (var i = 0; i < 33; i++) {
      await store.read('https://icon.invalid/$i');
    }
    await store.read('https://icon.invalid/32');
    expect(count, 33);
    await store.read('https://icon.invalid/0');
    expect(count, 34);
    store.retire();
  });
  testWidgets('slow continual body chunks cannot extend absolute8s budget', (
    tester,
  ) async {
    var cancelled = false, aborted = false, settled = false;
    Uint8List? value;
    final client = _SlowIconClient(
      () => cancelled = true,
      () => aborted = true,
    );
    final store = BookmarkFaviconStore(anonymousTestFactory: () => client);
    try {
      final result = store.read('https://icon.invalid/slow');
      result.then((data) {
        value = data;
        settled = true;
      });
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        settled,
        isFalse,
      ); // Chunks keep arriving; no EOF or early rejection.
      await tester.pump(const Duration(seconds: 1));
      // Assert settlement BEFORE awaiting the result: regressions fail now rather
      // than suspending a fake-clock widget test until its ten-minute timeout.
      expect(
        settled,
        isTrue,
        reason: 'Absolute8s deadline includes continual body chunks',
      );
      expect(value, isNull);
      expect(cancelled, isTrue);
      expect(aborted, isTrue);
      expect(
        client.cancelAcknowledged,
        isFalse,
        reason: 'Result cannot wait for provider cancellation ACK',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(settled, isTrue);
    } finally {
      store.retire();
      client.releaseCancellation();
      await tester
          .pump(); // Drain only this fixture; no timer/server is retained.
    }
  });
}

class _HeadersNeverClient extends http.BaseClient {
  _HeadersNeverClient(this.started, this.ended);
  final void Function() started, ended;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    started();
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() {
    if (!closed) {
      closed = true;
      ended();
    }
  }
}

class _SlowIconClient extends http.BaseClient {
  _SlowIconClient(this.cancelled, this.aborted);
  final void Function() cancelled, aborted;
  final _cancelAck = Completer<void>();
  Timer? _timer;
  bool get cancelAcknowledged => _cancelAck.isCompleted;
  void releaseCancellation() {
    _timer?.cancel();
    if (!_cancelAck.isCompleted) _cancelAck.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.followRedirects, isFalse);
    for (final h in ['cookie', 'authorization', 'x-csrf-token', 'referer']) {
      expect(request.headers.containsKey(h), isFalse);
    }
    expect(request, isA<http.AbortableRequest>());
    (request as http.AbortableRequest).abortTrigger!.then((_) => aborted());
    final controller = StreamController<List<int>>(
      onCancel: () {
        _timer?.cancel();
        cancelled();
        return _cancelAck.future;
      },
    );
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => controller.add([0]),
    );
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: {'content-type': 'image/png'},
    );
  }

  // A real IO close aborts its socket. This synthetic provider deliberately
  // withholds stream cancel ACK to verify callers still meet their own deadline.
  @override
  void close() {}
}
