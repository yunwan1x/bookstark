import 'package:bookstark_flutter/core/public_complex_source.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/public_notes/public_notes_feature.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'public_notes_repository_test.dart' as fixture;

void main() {
  testWidgets(
    'production public timeline opens actual native Markdown via only public endpoints',
    (tester) async {
      final requests = <String>[];
      Future<http.Response> handler(http.Request r) async {
        requests.add('${r.method} ${r.url.path}');
        expect(r.method, 'GET');
        expect(r.followRedirects, isFalse);
        if (r.url.path == '/base/notes/public') {
          return http.Response.bytes(
            utf8.encode(fixture.source([fixture.note()])),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        expect(r.url.pathSegments, ['base', 'api', 'shares', 'literal%2F+']);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'data': {
                'share_type': 'blog',
                'share_id': -7,
                'target_id': 7,
                'share_identify': 'literal%2F+',
                'blog_type': 'note',
                'has_password': false,
                'doc_type': 'markdown',
                'title': 'Fresh public title',
                'content': '# Full actual public body',
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      final client = BookstarkClient(
        fixture.server.toString(),
        transport: MockClient(handler),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PublicNotesFeature(
            anonymousClientFactory: (server) => BookstarkClient(
              server.toString(),
              transport: MockClient(handler),
            ),
            dispatchSourceFactory: (current) => AnonymousPublicComplexSource(
              isCurrent: current,
              anonymousTestClient: MockClient((request) async {
                expect(request.headers['cookie'], isNull);
                expect(request.headers['authorization'], isNull);
                return handler(request);
              }),
            ),
            client: client,
            onSpeak: (_, _, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Actual preview'), findsOneWidget);
      await tester.ensureVisible(find.text('打开完整笔记'));
      // The production anonymous source uses real async stream cancellation.
      // Allow that stream to finish on the real event loop; do not replace it
      // with a fake reader or bypass its endpoint/credential assertions.
      await tester.runAsync(() async {
        await tester.tap(find.text('打开完整笔记'));
        for (var tick = 0; tick < 200; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byType(BookstarkMarkdown).evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('分享阅读'), findsOneWidget);
      expect(
        find.byType(BookstarkMarkdown),
        findsOneWidget,
        reason:
            'Anonymous real-loop requests: $requests; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join(' | ')}',
      );
      expect(
        tester.widget<BookstarkMarkdown>(find.byType(BookstarkMarkdown)).data,
        '# Full actual public body',
      );
      expect(
        requests.length,
        3,
      ); // Timeline + anonymous dispatch inspect + actual Markdown load.
      expect(requests.any((path) => path.contains('/api/blogs')), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );
}
