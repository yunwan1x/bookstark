// Draft only; not formatted/analyzed/run while Root owns Native.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/core/public_complex_source.dart';

final reference = PublicShareReference(
  Uri.parse('https://demo.invalid/mount/'),
  'literal%2F+',
);
Map<String, Object?> detail(
  String kind,
  String source, {
  bool locked = false,
  String? raw,
}) => {
  'share_type': 'blog',
  'share_id': -17,
  'target_id': 17,
  'share_identify': reference.identify,
  'title': 'Actual public content',
  'blog_type': 'note',
  'doc_type': kind,
  'has_password': locked,
  'content': locked ? '' : source,
  'content_url': ?raw,
};
http.Response json(Object data) => http.Response(
  jsonEncode({'code': 0, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  final sources = <ComplexEditorKind, String>{
    ComplexEditorKind.markdown: '\ufeff# Body😀\r\n',
    ComplexEditorKind.html: '\ufeff<p>Body😀</p>\r\n',
    ComplexEditorKind.spreadsheet: SpreadsheetDocument.empty(
      workbookId: 'w',
      sheetId: 's',
    ).source,
    ComplexEditorKind.drawing: ' {"elements":[],"appState":{},"future":true} ',
    ComplexEditorKind.mindmap:
        '{"nodeData":{"id":"root","topic":"Read"},"future":true}',
    ComplexEditorKind.richdoc:
        '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[]},"future":true}',
    ComplexEditorKind.presentation:
        '{"width":1000,"height":562,"slides":[{"id":"s","elements":[]}],"future":true}',
  };
  for (final entry in sources.entries) {
    test(
      'seven typed source kinds exact no account headers ${entry.key.name}',
      () async {
        final requests = <http.Request>[];
        final raw =
            entry.key == ComplexEditorKind.html ||
            entry.key == ComplexEditorKind.richdoc;
        final source = AnonymousPublicComplexSource(
          isCurrent: () => true,
          anonymousTestClient: MockClient((request) async {
            requests.add(request);
            expect(request.url.path.startsWith('/mount/api/shares/'), true);
            expect(request.headers.containsKey('cookie'), false);
            expect(request.headers.containsKey('authorization'), false);
            expect(request.followRedirects, false);
            if (request.url.path.endsWith('/content/raw')) {
              return http.Response.bytes(
                gzip.encode(utf8.encode(entry.value)),
                200,
                headers: {
                  'content-type': entry.key == ComplexEditorKind.html
                      ? 'text/html; charset=utf-8'
                      : 'application/json; charset=utf-8',
                  'content-encoding': 'gzip',
                },
              );
            }
            return json(
              detail(
                entry.key.name,
                raw ? '' : entry.value,
                raw: raw ? reference.rawPath : null,
              ),
            );
          }),
        );
        addTearDown(source.close);
        final content = await source.read(reference);
        expect(content.document.kind, entry.key);
        expect(content.document.source, entry.value);
        expect(requests.length, raw ? 3 : 2);
      },
    );
  }
  test(
    'same root and mounted raw path canonicalize once, not duplicated',
    () async {
      final expected = '/mount${reference.rawPath}';
      final source = AnonymousPublicComplexSource(
        isCurrent: () => true,
        anonymousTestClient: MockClient((request) async {
          expect(request.url.path.contains('/mount/mount/'), false);
          if (request.url.path.endsWith('/content/raw')) {
            return http.Response(
              '<p>ok</p>',
              200,
              headers: {'content-type': 'text/html'},
            );
          }
          return json(detail('html', '', raw: expected));
        }),
      );
      addTearDown(source.close);
      expect((await source.read(reference)).document.source, '<p>ok</p>');
    },
  );
  test(
    'cross-origin/share/chapter absolute raw URLs rejected before fetch',
    () async {
      for (final raw in [
        'https://evil.invalid${reference.rawPath}',
        'https://demo.invalid${reference.rawPath}',
        '/api/shares/other/content/raw',
        '${reference.detailPath}/docs/other/content/raw',
        '${reference.rawPath}?extra=1',
        '${reference.rawPath}#fragment',
      ]) {
        var rawReads = 0;
        final source = AnonymousPublicComplexSource(
          isCurrent: () => true,
          anonymousTestClient: MockClient((request) async {
            if (request.url.path.endsWith('/content/raw')) rawReads++;
            return json(detail('html', '', raw: raw));
          }),
        );
        await expectLater(
          source.read(reference),
          throwsA(isA<PublicComplexReadFailure>()),
        );
        expect(rawReads, 0);
        source.close();
      }
    },
  );
  test(
    'empty HTML/richdoc JSON does not fallback when raw fails or auto-decompressed',
    () async {
      for (final kind in ['html', 'richdoc']) {
        for (final alreadyDecoded in [false, true]) {
          final source = AnonymousPublicComplexSource(
            isCurrent: () => true,
            anonymousTestClient: MockClient((request) async {
              if (request.url.path.endsWith('/content/raw')) {
                return http.Response.bytes(
                  alreadyDecoded
                      ? utf8.encode(kind == 'html' ? '<p>not gzip</p>' : '{}')
                      : [1, 2, 3],
                  alreadyDecoded ? 200 : 503,
                  headers: {
                    'content-type': kind == 'html'
                        ? 'text/html'
                        : 'application/json',
                    'content-encoding': 'gzip',
                  },
                );
              }
              return json(detail(kind, '', raw: reference.rawPath));
            }),
          );
          await expectLater(
            source.read(reference),
            throwsA(isA<PublicComplexReadFailure>()),
          );
          source.close();
        }
      }
    },
  );
  test(
    'gzip expansion over plain bound and CRC/truncated streams rejected',
    () async {
      final good = gzip.encode(utf8.encode('<p>ok</p>'));
      final damaged = List<int>.from(good);
      damaged[good.length - 5] ^= 1;
      for (final bytes in [
        gzip.encode(List<int>.filled(5 * 1024 * 1024 + 1, 65)),
        good.sublist(0, good.length - 4),
        damaged,
      ]) {
        final source = AnonymousPublicComplexSource(
          isCurrent: () => true,
          anonymousTestClient: MockClient((request) async {
            if (request.url.path.endsWith('/content/raw')) {
              return http.Response.bytes(
                bytes,
                200,
                headers: {
                  'content-type': 'text/html',
                  'content-encoding': 'gzip',
                },
              );
            }
            return json(detail('html', '', raw: reference.rawPath));
          }),
        );
        await expectLater(
          source.read(reference),
          throwsA(isA<PublicComplexReadFailure>()),
        );
        source.close();
      }
    },
  );
  test(
    'protected raw password POST is Dart-only and failed unlock never returns body',
    () async {
      const password = '  fixture password  ';
      final source = AnonymousPublicComplexSource(
        isCurrent: () => true,
        anonymousTestClient: MockClient((request) async {
          expect(request.headers.containsKey('cookie'), false);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {'password': password});
            expect(request.url.path.endsWith('/verify-password/raw'), true);
            return http.Response(
              '<p>unlocked</p>',
              200,
              headers: {'content-type': 'text/html'},
            );
          }
          return json(detail('html', '', locked: true));
        }),
      );
      addTearDown(source.close);
      await expectLater(
        source.read(reference),
        throwsA(isA<PublicComplexLocked>()),
      );
      final value = await source.read(reference, password: password);
      expect(value.document.source, '<p>unlocked</p>');
      expect(value.protected, true);
      expect(value.toString().contains(password), false);
    },
  );
  test(
    'shared token remains request-only and cancellation blocks old read',
    () async {
      const token = 'fixture-capability-only';
      final pending = Completer<http.Response>();
      var current = true;
      final source = AnonymousPublicComplexSource(
        isCurrent: () => current,
        anonymousTestClient: MockClient((request) async {
          expect(request.headers.containsKey('cookie'), false);
          if (request.url.path.endsWith('/edit')) {
            expect(request.url.queryParameters, {'token': token});
            return json({
              'editable': true,
              'title': 'Shared',
              'share_type': 'blog',
              'doc_type': 'drawing',
              'has_password': false,
              'content': sources[ComplexEditorKind.drawing],
              'modify_time': '2026-11-11 00:00:00',
            });
          }
          return json(detail('drawing', sources[ComplexEditorKind.drawing]!));
        }),
      );
      final value = await source.read(reference, editToken: token);
      expect(value.reference.canonicalUri.hasQuery, false);
      expect(value.toString().contains(token), false);
      source.close();
      final late = AnonymousPublicComplexSource(
        isCurrent: () => current,
        anonymousTestClient: MockClient((_) => pending.future),
      );
      final result = late.read(reference);
      final check = expectLater(
        result,
        throwsA(isA<PublicComplexReadFailure>()),
      );
      current = false;
      pending.complete(
        json(detail('drawing', sources[ComplexEditorKind.drawing]!)),
      );
      await check;
      late.close();
    },
  );
  test(
    'source-free dispatch accepts PPT above old MD cap without retaining body',
    () async {
      final row = detail('presentation', 'x' * (4 * 1024 * 1024 + 1));
      final source = AnonymousPublicComplexSource(
        isCurrent: () => true,
        anonymousTestClient: MockClient((_) async => json(row)),
      );
      addTearDown(source.close);
      final identity = await source.inspect(reference);
      expect(identity.format, 'presentation');
      expect(identity.content, isEmpty);
    },
  );
  test(
    'chapter membership and exact raw scope checked before source return',
    () async {
      final book = <String, Object?>{
        'share_type': 'book',
        'share_id': 17,
        'target_id': 17,
        'share_identify': reference.identify,
        'title': 'Book',
        'doc_type': '',
        'has_password': false,
        'content': '',
        'doc_tree': [
          {
            'document_id': 21,
            'parent_id': 0,
            'identify': 'chapter-a',
            'document_name': 'Chapter',
            'doc_type': 'html',
            'children': [],
          },
        ],
      };
      for (final wrongRaw in [false, true]) {
        var rawReads = 0;
        final source = AnonymousPublicComplexSource(
          isCurrent: () => true,
          anonymousTestClient: MockClient((r) async {
            if (r.url.path.endsWith('/content/raw')) {
              rawReads++;
              return http.Response(
                '<p>chapter</p>',
                200,
                headers: {'content-type': 'text/html'},
              );
            }
            if (r.url.path.endsWith('/docs/chapter-a')) {
              return json({
                'title': 'Chapter',
                'doc_type': 'html',
                'content': '',
                'content_url':
                    '${reference.chapterPath(wrongRaw ? 'chapter-b' : 'chapter-a')}/content/raw',
              });
            }
            return json(book);
          }),
        );
        if (wrongRaw) {
          await expectLater(
            source.read(reference, chapterIdentify: 'chapter-a'),
            throwsA(isA<PublicComplexReadFailure>()),
          );
          expect(rawReads, 0);
        } else {
          expect(
            (await source.read(
              reference,
              chapterIdentify: 'chapter-a',
            )).document.source,
            '<p>chapter</p>',
          );
          expect(rawReads, 1);
        }
        await expectLater(
          source.read(reference, chapterIdentify: 'not-a-member'),
          throwsA(isA<PublicComplexReadFailure>()),
        );
        source.close();
      }
    },
  );

  test('implicit negative IDs are blog-only, never a book identity', () async {
    final source = AnonymousPublicComplexSource(
      isCurrent: () => true,
      anonymousTestClient: MockClient(
        (_) async => json({
          'share_type': 'book',
          'share_id': -17,
          'target_id': 17,
          'share_identify': reference.identify,
          'title': 'Invalid implicit book',
          'doc_type': '',
          'has_password': false,
          'content': '',
          'doc_tree': [],
        }),
      ),
    );
    addTearDown(source.close);
    await expectLater(
      source.inspect(reference),
      throwsA(isA<PublicComplexReadFailure>()),
    );
  });
  test(
    'invalid isolated surrogate source fails before UTF8 normalization',
    () async {
      for (final locked in [false, true]) {
        final source = AnonymousPublicComplexSource(
          isCurrent: () => true,
          anonymousTestClient: MockClient((r) async {
            if (r.method == 'POST') {
              return json({'content': String.fromCharCode(0xd800)});
            }
            return json(
              detail('markdown', String.fromCharCode(0xd800), locked: locked),
            );
          }),
        );
        await expectLater(
          source.read(reference, password: locked ? 'fixture' : null),
          throwsA(isA<PublicComplexReadFailure>()),
        );
        source.close();
      }
    },
  );
  testWidgets(
    'absolute twenty second budget rejects continuous slow chunks and cancels body',
    (tester) async {
      var cancelled = false;
      final client = _SlowBodyClient(() => cancelled = true);
      final source = AnonymousPublicComplexSource(
        isCurrent: () => true,
        anonymousTestClient: client,
      );
      final check = expectLater(
        source.inspect(reference),
        throwsA(isA<PublicComplexReadFailure>()),
      );
      await tester.pump();
      for (var second = 0; second < 21; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await check;
      expect(cancelled, true);
      expect(client.closed, true);
      source.close();
    },
  );
  testWidgets('retire aborts stalled headers without waiting twenty seconds', (
    tester,
  ) async {
    final client = _NeverHeaderClient();
    final source = AnonymousPublicComplexSource(
      isCurrent: () => true,
      anonymousTestClient: client,
    );
    final check = expectLater(
      source.inspect(reference),
      throwsA(isA<PublicComplexReadFailure>()),
    );
    await tester.pump();
    source.close();
    await tester.pump();
    await check;
    expect(client.closed, true);
  });
}

class _SlowBodyClient extends http.BaseClient {
  _SlowBodyClient(this.onCancelled);
  final void Function() onCancelled;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Timer? tick;
    late StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        tick = Timer.periodic(
          const Duration(seconds: 1),
          (_) => body.add([32]),
        );
      },
      onCancel: () {
        tick?.cancel();
        onCancelled();
      },
    );
    return http.StreamedResponse(
      body.stream,
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class _NeverHeaderClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}
