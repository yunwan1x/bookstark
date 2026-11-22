import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/auth/account_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> mount(
    WidgetTester t,
    AccountForm form,
    Future<http.Response> Function(http.Request) respond,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: AccountFormPage(
          form: form,
          strings: const AppStrings(),
          server: 'https://books.example',
          onBack: () {},
          onReset: () {},
          clientFactory: (server) =>
              BookstarkClient(server, transport: MockClient(respond)),
        ),
      ),
    );
  }

  Future<void> fill(WidgetTester t, String key, String value) async {
    await t.scrollUntilVisible(
      find.byKey(Key(key)),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await t.enterText(find.byKey(Key(key)), value);
  }

  Future<void> submit(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.byKey(const Key('submit')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('submit')));
    await t.pumpAndSettle();
  }

  testWidgets('registration mismatch is rejected before any network request', (
    t,
  ) async {
    var requests = 0;
    await mount(t, AccountForm.register, (_) async {
      requests++;
      return http.Response('{}', 200);
    });
    await fill(t, 'account', 'reader');
    await fill(t, 'email', 'reader@example.com');
    await fill(t, 'password', 'secret-one');
    await fill(t, 'confirm', 'secret-two');
    await submit(t);
    expect(find.text('两次密码不一致'), findsOneWidget);
    expect(requests, 0);
  });
  testWidgets(
    'forgot password sends identity and shows non-enumerating success',
    (t) async {
      Map<String, dynamic>? sent;
      await mount(t, AccountForm.forgot, (request) async {
        if (request.url.path == '/api/csrf-token') {
          return http.Response(
            '{"csrf_token":"nonce"}',
            200,
            headers: {'set-cookie': 'csrf_token=nonce; Path=/'},
          );
        }
        expect(request.url.path, '/api/password/forgot');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"code":0,"message":"如果账号存在，重置密码邮件将发送到注册邮箱"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await fill(t, 'identity', 'reader@example.com');
      await submit(t);
      expect(sent, {'identity': 'reader@example.com'});
      expect(find.byKey(const Key('form-success')), findsOneWidget);
    },
  );
  testWidgets('reset refuses a link belonging to another server before HTTP', (
    t,
  ) async {
    var requests = 0;
    await mount(t, AccountForm.reset, (_) async {
      requests++;
      return http.Response('{}', 200);
    });
    await fill(t, 'token', 'https://other.example/reset-password#token=secret');
    await fill(t, 'password', 'new-secret');
    await fill(t, 'confirm', 'new-secret');
    await submit(t);
    expect(requests, 0);
    expect(find.text('重置链接与服务器地址不匹配'), findsOneWidget);
  });
}
