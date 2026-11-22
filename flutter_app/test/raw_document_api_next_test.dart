import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

class RawTransport extends http.BaseClient {
  RawTransport(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closed = true;
  }
}

BookstarkClient api(RawTransport raw) => BookstarkClient(
  'https://example.test/mount',
  transport: MockClient((_) async => http.Response('{}', 200)),
  rawDocumentTransport: raw,
)..restoreSession({'token': 'same', 'csrf_token': 'old'});
Uri endpoint([String suffix = '']) =>
    Uri.parse('https://example.test/mount/api/docs/17$suffix');
void main() {
  test(
    'raw request preserves wire bytes, prefix, cookie, GET and no redirects',
    () async {
      final raw = RawTransport((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(request.url, endpoint('/content/raw'));
        expect(request.headers['cookie'], contains('token=same'));
        return http.StreamedResponse(
          Stream.value([31, 139, 8, 0]),
          200,
          headers: {'content-encoding': 'gzip'},
          request: request,
        );
      });
      final client = api(raw);
      final response = await client.rawDocumentGet(
        endpoint('/content/raw'),
        maxWireBytes: 16,
        abortTrigger: Completer<void>().future,
      );
      expect(await response.stream.expand((bytes) => bytes).toList(), [
        31,
        139,
        8,
        0,
      ]);
      client.close();
      expect(
        raw.closed,
        isFalse,
      ); // externally injected raw client remains borrowed
    },
  );

  test(
    'same token but replaced csrf session aborts header wait and ignores late cookies',
    () async {
      final late = Completer<http.StreamedResponse>();
      final raw = RawTransport((_) => late.future);
      final client = api(raw);
      final pending = client.rawDocumentGet(
        endpoint(),
        maxWireBytes: 16,
        abortTrigger: Completer<void>().future,
      );
      await Future<void>.delayed(Duration.zero);
      client.restoreSession({'token': 'same', 'csrf_token': 'new'});
      await expectLater(pending, throwsA(isA<ApiFailure>()));
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      late.complete(
        http.StreamedResponse(
          body.stream,
          401,
          headers: {'set-cookie': 'token=stale; Path=/'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(client.exportSession(), {'token': 'same', 'csrf_token': 'new'});
      client.close();
      await body.close();
    },
  );
  test(
    'body stream is retired before an old chunk reaches a replaced session',
    () async {
      final body = StreamController<List<int>>();
      final raw = RawTransport(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      final client = api(raw);
      final response = await client.rawDocumentGet(
        endpoint(),
        maxWireBytes: 16,
        abortTrigger: Completer<void>().future,
      );
      final pending = response.stream.toList();
      await Future<void>.delayed(Duration.zero);
      client.restoreSession({'token': 'same', 'csrf_token': 'new'});
      await expectLater(pending, throwsA(isA<ApiFailure>()));
      client.close();
      await body.close();
    },
  );
  test(
    'invalid endpoint and redirect are rejected without consuming an error body',
    () async {
      var calls = 0, cancelled = false;
      final raw = RawTransport((_) async {
        calls++;
        return http.StreamedResponse(
          StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          ).stream,
          302,
          headers: {'location': 'https://foreign.test'},
        );
      });
      final client = api(raw);
      for (final bad in [
        Uri.parse('https://foreign.test/mount/api/docs/17'),
        Uri.parse('https://example.test/api/docs/17'),
        Uri.parse('https://example.test/mount/api/docs/0'),
        Uri.parse('https://example.test/mount/api/docs/17?token=x'),
      ]) {
        await expectLater(
          client.rawDocumentGet(
            bad,
            maxWireBytes: 16,
            abortTrigger: Completer<void>().future,
          ),
          throwsFormatException,
        );
      }
      expect(calls, 0);
      await expectLater(
        client.rawDocumentGet(
          endpoint(),
          maxWireBytes: 16,
          abortTrigger: Completer<void>().future,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(cancelled, isTrue);
      client.close();
    },
  );
  test('wire counter rejects the actual over-limit stream', () async {
    final raw = RawTransport(
      (_) async => http.StreamedResponse(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        200,
      ),
    );
    final client = api(raw);
    final response = await client.rawDocumentGet(
      endpoint(),
      maxWireBytes: 3,
      abortTrigger: Completer<void>().future,
    );
    await expectLater(response.stream.toList(), throwsA(isA<ApiFailure>()));
    client.close();
  });
}
