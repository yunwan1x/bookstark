import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool english = false,
    Future<http.Response> Function(http.Request)? respond,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: ConnectionPage(
          strings: AppStrings(english: english),
          onLanguage: () {},
          onLocal: () {},
          onRegister: () {},
          onForgot: () {},
          onLogin: (server, account, password) async {
            final client = BookstarkClient(
              server,
              transport: MockClient(
                respond ??
                    (_) async => http.Response('{"code":0,"data":{}}', 200),
              ),
            );
            try {
              await client.login(account, password);
            } finally {
              client.close();
            }
          },
        ),
      ),
    );
  }

  testWidgets('required fields prevent a network login', (tester) async {
    var requests = 0;
    await mount(
      tester,
      respond: (_) async {
        requests++;
        return http.Response('{}', 200);
      },
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('login')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接并登录'));
    await tester.pump();
    expect(find.text('请填写此项'), findsNWidgets(3));
    expect(requests, 0);
  });

  testWidgets('failed login keeps account and displays actual service error', (
    tester,
  ) async {
    await mount(
      tester,
      respond: (_) async => http.Response(
        '{"code":401,"message":"账号或密码错误"}',
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.enterText(
      find.byKey(const Key('server')),
      'https://books.example',
    );
    await tester.enterText(find.byKey(const Key('account')), 'reader');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.scrollUntilVisible(
      find.byKey(const Key('login')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接并登录'));
    await tester.pumpAndSettle();
    expect(find.text('账号或密码不正确，请检查后重试。'), findsOneWidget);
    expect(find.text('reader'), findsOneWidget);
  });

  testWidgets('English rejected login is not reported as a network failure', (
    tester,
  ) async {
    await mount(
      tester,
      english: true,
      respond: (_) async => http.Response(
        '{"code":401,"message":"账号或密码错误"}',
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.enterText(
      find.byKey(const Key('server')),
      'https://books.example',
    );
    await tester.enterText(find.byKey(const Key('account')), 'reader');
    await tester.enterText(find.byKey(const Key('password')), 'wrong-password');
    await tester.scrollUntilVisible(
      find.byKey(const Key('login')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in was not successful'), findsOneWidget);
    expect(
      find.text('Account or password is incorrect. Check and retry.'),
      findsOneWidget,
    );
    expect(
      find.text('Connection failed. Check your network and server address.'),
      findsNothing,
    );
  });

  testWidgets(
    'pending login disables another submit and password can be revealed',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      await mount(
        tester,
        respond: (_) {
          requests++;
          return response.future;
        },
      );
      await tester.enterText(
        find.byKey(const Key('server')),
        'https://books.example',
      );
      await tester.enterText(find.byKey(const Key('account')), 'reader');
      await tester.enterText(find.byKey(const Key('password')), 'secret');
      await tester.ensureVisible(find.byKey(const Key('password')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        false,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('login')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接并登录'));
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('login')),
      );
      expect(button.onPressed, isNull);
      expect(requests, 1);
      response.complete(http.Response('{"code":0,"data":{}}', 200));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'small screen and English text scaling remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, english: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('login')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
