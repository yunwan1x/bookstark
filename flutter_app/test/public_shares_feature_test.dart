import 'support/shared_capability_http_fixture.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/public_shares/public_shares_feature.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_page.dart';

const feed = '''
<nav class="public-nav"><a href="/shares?type=article" aria-current="page">Article</a></nav>
<form id="publicSearch"><input name="type" value="article"><input name="sort" value="latest"><input name="label" value=""><input name="keyword" value=""></form>
<aside class="public-categories"><a href="/shares?type=article&amp;sort=latest&amp;page=1" aria-current="page"><span>All</span></a></aside>
<div class="public-feed-tabs"><a href="/shares?type=article&amp;sort=latest" aria-current="page">Latest</a></div>
<section class="public-feed"><div class="public-items-article">
<article class="public-entry" data-share-identify="editor"><h2><a>Actual share</a></h2><span class="public-content-type">Markdown</span><p class="public-excerpt">Actual excerpt</p><div class="public-meta"><span>Actual author</span></div></article>
</div></section><nav class="public-pagination"><span>1</span></nav>
''';
http.Response json(Map<String, Object?> value) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': value})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  testWidgets(
    'production public feed opens reader then explicit editing link and saves without any owner endpoint',
    (tester) async {
      final wire = SharedCapabilityHttpFixture(
        server: Uri.parse('https://example.test'),
        identify: 'editor',
        tokenChar: 'e',
        source: '# Seed',
        title: 'Actual share',
      )..targetId = 7;
      final token = wire.token, requests = wire.requests;
      Future<http.Response> handler(http.Request request) async {
        expect(request.headers['authorization'], isNull);
        expect(request.headers['cookie'], isNull);
        if (request.url.path == '/shares') {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(
            feed,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return wire.handle(request);
      }

      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (_) async => throw StateError('Account transport forbidden'),
        ),
      );
      client.restoreSession({
        'token': 'root-account-never-copy',
        'csrf_token': 'root-csrf',
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PublicSharesFeature(
            client: client,
            anonymousClientFactory: (server) => BookstarkClient(
              server.toString(),
              transport: MockClient(handler),
            ),
            dispatchSourceFactory: wire.probe,
            sharedCapabilityFactory: wire.capability,
            english: true,
            onCreate: () async {},
            onSpeak: (_, _, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Actual share'));
      await tester.tap(find.text('Actual share'));
      await tester.pumpAndSettle();
      expect(find.text('Shared reading'), findsOneWidget);
      expect(wire.puts, 0);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use editing link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'https://example.test/shares/editor?token=$token',
      );
      await tester.ensureVisible(find.text('Verify and open'));
      // Keep real anonymous inspect/CAS-source streams outside fake async.
      await tester.runAsync(() async {
        await tester.tap(find.text('Verify and open'));
        for (var tick = 0; tick < 200; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byType(ShareEditPage).evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(
        find.byType(ShareEditPage),
        findsOneWidget,
        reason:
            'Anonymous real-loop requests: $requests; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join(' | ')}',
      );
      await tester.enterText(
        find.byKey(const ValueKey('shared-markdown-input')),
        '# Actual token edit',
      );
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Save'));
        for (var tick = 0; tick < 200; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('Save confirmed').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(wire.puts, 1);
      expect(wire.source, '# Actual token edit');
      expect(
        requests.where(
          (value) =>
              value.contains('/api/blogs') || value.contains('/api/docs'),
        ),
        isEmpty,
      );
      expect(requests.where((value) => value.startsWith('PUT')), [
        'PUT /api/shares/editor/edit/cas',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
