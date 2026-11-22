// Scratch tests for the future07 patch. Not run against frozen C source.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/note_list_metadata_json.dart';

Stream<List<int>> chunks(String text, {int size = 1}) async* {
  final bytes = utf8.encode(text);
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

String envelope(List<Object?> rows) => jsonEncode({
  'code': 0,
  'data': rows,
  'total': rows.length,
  'page': 1,
  'page_size': 20,
  'total_pages': 1,
});
Map<String, Object?> row({String preview = 'short'}) => {
  'blog_id': 7,
  'blog_title': 'title😀',
  'content_preview': preview,
  'has_password': false,
  'is_pinned': 1,
  'visibility': 0,
  'editor_type': 'markdown',
  'labels': [' old ', 'literal,comma'],
  'modify_time': '2026-11-11',
};
void main() {
  test(
    'original complete envelope and metadata survive bytewise UTF8 chunks',
    () async {
      final expected = jsonDecode(envelope([row()]));
      expect(
        await readNotesListMetadataJson(chunks(envelope([row()]))),
        expected,
      );
    },
  );
  test(
    'large bodies discarded and only512 Unicode scalars of preview retained',
    () async {
      final source = row(preview: '\ufeff${'😀' * 700}${'正文' * 100000}')
        ..['blog_content'] = 'x' * (3 * 1024 * 1024)
        ..['blog_desc'] = 'y' * (1024 * 1024);
      final projected = await readNotesListMetadataJson(
        chunks(envelope([source]), size: 8192),
      );
      final actual = (projected['data'] as List).single as Map;
      expect(actual['blog_content'], isNull);
      expect(actual['blog_desc'], isNull);
      expect(actual['content_preview'], '\ufeff${'😀' * 511}');
      expect((actual['content_preview'] as String).runes.length, 512);
      expect(jsonEncode(projected).length, lessThan(10000));
    },
  );
  test(
    'escaped surrogate pairs and BOM retain complete scalar at truncation edge',
    () async {
      const raw =
          r'{"code":0,"data":[{"content_preview":"\uFEFF\uD83D\uDE00\uD83D\uDE00","blog_id":1}],"total":1}';
      final result = await readNotesListMetadataJson(
        chunks(raw),
        maxPreviewRunes: 2,
      );
      expect(
        ((result['data'] as List).single as Map)['content_preview'],
        '\ufeff😀',
      );
    },
  );
  test(
    'zero-length preview does not bypass validation of its suffix',
    () async {
      final result = await readNotesListMetadataJson(
        chunks(envelope([row(preview: '😀' * 600)])),
        maxPreviewRunes: 0,
      );
      expect(((result['data'] as List).single as Map)['content_preview'], '');
      await expectLater(
        readNotesListMetadataJson(
          chunks(r'{"content_preview":"ok\uD800"}'),
          maxPreviewRunes: 0,
        ),
        throwsFormatException,
      );
    },
  );
  for (final raw in [
    r'{"content_preview":"valid prefix\x"}',
    r'{"content_preview":"valid prefix\uD800"}',
    r'{"content_preview":"valid prefix\uDC00"}',
    r'{"content_preview":"valid prefix\uD800\u0061"}',
    r'{"blog_content":"discarded\uD800"}',
    r'{"blog_desc":"discarded\q"}',
    '{"blog_content":"actual\ncontrol"}',
    '{"content_preview":"unterminated',
  ]) {
    test('invalid discarded/truncated tail is rejected: $raw', () async {
      await expectLater(
        readNotesListMetadataJson(chunks(raw), maxPreviewRunes: 1),
        throwsFormatException,
      );
    });
  }
  test('invalid trailing UTF8 is not ignored after retained prefix', () async {
    final bytes = [
      ...utf8.encode('{"content_preview":"prefix'),
      0xff,
      ...utf8.encode('"}'),
    ];
    await expectLater(
      readNotesListMetadataJson(
        Stream.fromIterable(bytes.map((b) => [b])),
        maxPreviewRunes: 1,
      ),
      throwsFormatException,
    );
  });
  for (final raw in [
    r'{"code":0,"data":[],"data":[]}',
    r'{"data":[{"blog_id":1,"\u0062log_id":2}]}',
    r'{"data":[{"content_preview":"first","content_preview":"second"}]}',
    r'{"data":[{"blog_content":"one","blog_content":"two"}]}',
  ]) {
    test(
      'duplicate decoded keys fail at every retained object: $raw',
      () async {
        await expectLater(
          readNotesListMetadataJson(chunks(raw)),
          throwsFormatException,
        );
      },
    );
  }
  for (final raw in [
    '{"data":[1,]}',
    '{"data":[],}',
    '{"data":[]}{"other":1}',
    '[]',
    'null',
    '{"blog_content":{}}',
    '{"blog_content":1}',
    '{"blog_desc":false}',
  ]) {
    test('malformed grammar or non-string body is rejected: $raw', () async {
      await expectLater(
        readNotesListMetadataJson(chunks(raw)),
        throwsFormatException,
      );
    });
  }
  test(
    'null body and empty API data remain metadata and are not invented as rows',
    () async {
      final expected = {
        'code': 0,
        'data': null,
        'total': 0,
        'blog_content': null,
      };
      expect(
        await readNotesListMetadataJson(chunks(jsonEncode(expected))),
        expected,
      );
    },
  );
  test(
    'byte, metadata, key, field, item and nesting bounds all fail closed',
    () async {
      await expectLater(
        readNotesListMetadataJson(chunks(envelope([row()])), maxBytes: 10),
        throwsFormatException,
      );
      await expectLater(
        readNotesListMetadataJson(
          chunks(envelope([row()])),
          maxMetadataChars: 20,
        ),
        throwsFormatException,
      );
      await expectLater(
        readNotesListMetadataJson(chunks('{"${'k' * 513}":0}')),
        throwsFormatException,
      );
      await expectLater(
        readNotesListMetadataJson(
          chunks(envelope([row()..['blog_title'] = 'x' * 8193])),
        ),
        throwsFormatException,
      );
      await expectLater(
        readNotesListMetadataJson(
          chunks(envelope([row(), row()])),
          maxItems: 1,
        ),
        throwsFormatException,
      );
      await expectLater(
        readNotesListMetadataJson(
          chunks('{"data":[{"nested":{"deep":[]}}]}'),
          maxDepth: 3,
        ),
        throwsFormatException,
      );
    },
  );
  for (final raw in [
    '{"blog_id":9007199254740992}',
    '{"blog_id":1e20}',
    '{"blog_id":1.00000000000000000001}',
    '{"total":2e0}',
    '{"price":1e999}',
  ]) {
    test('numbers cannot become rounded resource identities: $raw', () async {
      await expectLater(
        readNotesListMetadataJson(chunks(raw)),
        throwsFormatException,
      );
    });
  }
  test(
    'stream errors propagate and never return the already retained prefix',
    () async {
      final failure = StateError('owned fixture stream failure');
      Stream<List<int>> broken() async* {
        yield utf8.encode('{"code":0,"data":[]');
        throw failure;
      }

      await expectLater(
        readNotesListMetadataJson(broken()),
        throwsA(same(failure)),
      );
    },
  );
}
