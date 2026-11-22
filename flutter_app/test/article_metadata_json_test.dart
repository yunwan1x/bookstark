import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/article_metadata_json.dart';
import 'package:bookstark_flutter/core/article_web_scope.dart';

void main() {
  Map<String, Object?> metadata() => {
    'blog_id': 19,
    'member_id': 7,
    'blog_type': 'article',
    'blog_identify': '旅行-19',
  };
  final scope = ArticleWebScope.parse('https://example.test:54321/team/app', 7);
  Future<Map<String, Object?>> parse(String value, [int chunk = 1]) async {
    final bytes = utf8.encode(value);
    return readArticleMetadataJson(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += chunk)
          bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk),
      ]),
    );
  }

  test(
    'UTF8 and escape boundaries preserve identity but discard both bodies',
    () async {
      final body = jsonEncode({
        'code': 0,
        'data': {
          ...metadata(),
          'blog_content': '\ufeff中文\r\n"\\\t\u0000',
          'blog_desc': 'secret',
          'labels': ['a', 'b'],
          'has_password': true,
        },
      });
      for (final chunk in [1, 2, 3, 7, 64, 4096]) {
        final data = (await parse(body, chunk))['data'] as Map;
        expect(data['blog_identify'], '旅行-19');
        expect(data['blog_content'], isNull);
        expect(data['blog_desc'], isNull);
        expect(data['labels'], ['a', 'b']);
      }
    },
  );

  test(
    'large streamed escaped body never consumes retained metadata budget',
    () async {
      Stream<List<int>> input() async* {
        yield utf8.encode('{"code":0,"data":{"blog_content":"');
        final chunk = utf8.encode(r'\u0000中文\"\\\r\n' * 4096);
        for (var i = 0; i < 160; i++) {
          yield chunk;
        }
        yield utf8.encode(
          '","blog_id":19,"member_id":7,'
          '"blog_type":"article","blog_identify":"large"}}',
        );
      }

      final data =
          (await readArticleMetadataJson(
                input(),
                maxMetadataChars: 256,
              ))['data']
              as Map;
      expect(data['blog_content'], isNull);
      expect(data['blog_identify'], 'large');
    },
  );

  test('malformed JSON cannot be hidden in discarded strings', () async {
    for (final text in [
      r'{"blog_content":"\x00"}',
      r'{"blog_content":"\u12x4"}',
      '{"blog_content":"bad\nraw"}',
      r'{"blog_content":"unterminated}',
      '{"x":1,}',
      '{"x":[1,]}',
      '{"x":01}',
      '{"x":truefalse}',
      '{"x" 1}',
      '{"x":{]}',
      '{"x":1}{"x":2}',
      '[1,2]',
      '{"blog_id":1,"blog_\\u0069d":2}',
      '{"blog_content":{}}',
      '{"data":{"x":1,"x":2}}',
    ]) {
      await expectLater(parse(text), throwsFormatException, reason: text);
    }
    await expectLater(
      readArticleMetadataJson(
        Stream.value([123, 34, 120, 34, 58, 34, 255, 34, 125]),
      ),
      throwsFormatException,
    );
  });

  test(
    'input, depth, string and metadata bounds reject with stream cancellation',
    () async {
      var cancelled = false;
      late StreamController<List<int>> controller;
      controller = StreamController(onCancel: () => cancelled = true);
      final result = readArticleMetadataJson(controller.stream, maxBytes: 8);
      controller.add(utf8.encode('{"long":12345}'));
      await expectLater(result, throwsFormatException);
      expect(cancelled, isTrue);
      await controller.close();
      await expectLater(parse('{"x":"${'a' * 8193}"}'), throwsFormatException);
      await expectLater(parse('{"${'a' * 513}":1}'), throwsFormatException);
      await expectLater(
        parse('${'[' * 33}0${']' * 33}'),
        throwsFormatException,
      );
      await expectLater(
        readArticleMetadataJson(
          Stream.value(utf8.encode('{"x":"12345"}')),
          maxMetadataChars: 5,
        ),
        throwsFormatException,
      );
    },
  );

  test('typed editor entry validates account, collection and exact ID', () {
    final uri = scope.editorEntry(metadata(), id: 19);
    expect(
      uri.toString(),
      'https://example.test:54321/team/app/blogs/%E6%97%85%E8%A1%8C-19/edit',
    );
    expect(scope.isInitialEntry(uri), isTrue);
    expect(scope.isInitialEntry(scope.listUri), isTrue);
    for (final patch in [
      {'blog_id': 20},
      {'member_id': 8},
      {'blog_type': 'note'},
      {'blog_identify': ''},
      {'blog_identify': '..'},
      {'blog_identify': 'a/b'},
      {'blog_identify': '%2f'},
      {'blog_identify': 'a\\b'},
      {'blog_identify': '\n'},
      {'blog_identify': 'a' * 257},
      {'blog_identify': 'a?b'},
    ]) {
      expect(
        () => scope.editorEntry({...metadata(), ...patch}, id: 19),
        throwsFormatException,
      );
    }
    for (final url in [
      'https://example.test:54321/blogs/a/edit',
      'https://example.test:54321/team/app/blogs/a/edit?mode=edit',
      'https://example.test:54321/team/app/blogs/a/edit#x',
      'https://example.test:54321/team/app/notes?tab=notes',
      'https://elsewhere.test/team/app/blogs/a/edit',
      'https://example.test:54321/team/app/blogs/%252f/edit',
    ]) {
      expect(scope.isInitialEntry(Uri.parse(url)), isFalse, reason: url);
    }
  });

  test(
    'client uses prefix GET and cookies without following redirects',
    () async {
      final client = BookstarkClient(
        'https://example.test/team',
        transport: MockClient((request) async {
          expect(request.url.path, '/team/api/blogs/19');
          expect(request.method, 'GET');
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], contains('token=synthetic'));
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {...metadata(), 'blog_content': 'x' * (256 * 1024)},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      client.restoreSession({'token': 'synthetic'});
      addTearDown(client.close);
      final result = await client.articleMetadata(19);
      expect(result['blog_content'], isNull);
      expect(scope.editorEntry(result, id: 19).pathSegments.last, 'edit');
    },
  );

  test(
    'client rejects redirects, nonJSON, failed or missing envelope code',
    () async {
      for (final item in [
        (302, 'application/json', '{"code":0,"data":{}}'),
        (200, 'text/html', '{"code":0,"data":{}}'),
        (200, 'application/json', '{"code":403,"data":{}}'),
        (200, 'application/json', '{"data":{}}'),
        (200, 'application/json', '{"code":0,"data":[]}'),
      ]) {
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient(
            (_) async => http.Response(
              item.$3,
              item.$1,
              headers: {'content-type': item.$2},
            ),
          ),
        );
        await expectLater(
          client.articleMetadata(19),
          throwsA(anyOf(isA<FormatException>(), isA<ApiFailure>())),
        );
        client.close();
      }
    },
  );
}
