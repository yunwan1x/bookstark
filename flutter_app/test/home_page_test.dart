import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'current Go article and note recent types use typed blog IDs, never URL hints',
    (tester) async {
      final routes = <String>[];
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (_) async => http.Response(
            '{"code":0,"recent":['
            '{"type":"article","id":19,"title":"Go article","url":"https://other.test/steal"},'
            '{"type":"note","id":20,"title":"Go note","url":"javascript:alert(1)"}]}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: HomePage(
            strings: const AppStrings(),
            load: () => client.get('/api/home'),
            onLanguage: () {},
            onNavigate: routes.add,
            local: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['Go article', 'Go note']) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(routes, ['blog/19', 'blog/20']);
      expect(find.text('还没有最近记录'), findsNothing);
    },
  );

  testWidgets(
    'legacy local blog, book and document recent routes remain compatible',
    (tester) async {
      final routes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: HomePage(
            strings: const AppStrings(),
            load: () async => {
              'recent': [
                {'type': 'blog', 'id': 9, 'title': 'Legacy blog'},
                {'type': 'book', 'id': 10, 'title': 'Recent book'},
                {'type': 'document', 'id': 11, 'title': 'Recent document'},
              ],
            },
            onLanguage: () {},
            onNavigate: routes.add,
            local: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['Legacy blog', 'Recent book', 'Recent document']) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(routes, ['blog/9', 'book/10', 'document/11']);
    },
  );

  testWidgets('invalid recent identities never create actionable cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: HomePage(
          strings: const AppStrings(),
          load: () async => {
            'recent': [
              {'type': 'article', 'id': 0, 'title': 'bad-zero'},
              {'type': 'note', 'id': -1, 'title': 'bad-negative'},
              {'type': 'article', 'id': '19', 'title': 'bad-string'},
              {'type': 'unknown', 'id': 1, 'title': 'bad-type'},
            ],
          },
          onLanguage: () {},
          onNavigate: (_) => throw StateError('No invalid route'),
          local: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有最近记录'), findsOneWidget);
    expect(find.textContaining('bad-'), findsNothing);
  });

  testWidgets('home shows empty actual response and retries a failed load', (
    tester,
  ) async {
    var requests = 0;
    final client = BookstarkClient(
      'https://books.example',
      transport: MockClient((r) async {
        requests++;
        if (requests == 1) {
          return http.Response('{"code":503,"message":"unavailable"}', 503);
        }
        return http.Response('{"code":0,"recent":[],"sections":[]}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: HomePage(
          strings: const AppStrings(),
          load: () => client.get('/api/home'),
          local: false,
          onLanguage: () {},
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有最近记录'), findsOneWidget);
    expect(requests, 2);
    expect(find.text('阅读笔记'), findsNothing);
    client.close();
  });
  testWidgets(
    'English home shortcuts remain readable and tasks actionable on narrow large-text screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final routes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 200),
            ),
            child: child!,
          ),
          home: HomePage(
            strings: const AppStrings(english: true),
            load: () async => {'recent': []},
            local: false,
            onLanguage: () {},
            onNavigate: routes.add,
            canNavigate: (route) =>
                ['home', 'notes', 'articles', 'tasks'].contains(route),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Tasks'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(routes, ['tasks']);
    },
  );
}
