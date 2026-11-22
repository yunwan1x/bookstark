import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/auth/account_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const en = AppStrings(english: true);
http.Response response(int status, String message) => http.Response(
  jsonEncode({'code': status == 200 ? 0 : status, 'message': message}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response csrf() => http.Response(
  '{"code":0}',
  200,
  headers: {'set-cookie': 'csrf_token=nonce; Path=/'},
);

Future<void> mount(
  WidgetTester t,
  AccountForm form,
  Future<http.Response> Function(http.Request) handler, {
  bool large = false,
  VoidCallback? back,
}) async {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = large ? const Size(640, 1280) : const Size(780, 1688);
  t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: AccountFormPage(
        form: form,
        strings: en,
        server: 'https://books.example/team',
        onBack: back ?? () {},
        onReset: () {},
        clientFactory: (base) =>
            BookstarkClient(base, transport: MockClient(handler)),
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
  await t.pumpAndSettle();
  await t.enterText(find.byKey(Key(key)), value);
}

Future<void> submit(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.byKey(const Key('submit')),
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('submit')));
  await t.pumpAndSettle();
}

TextField field(WidgetTester t, String key) => t.widget<TextField>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
);
Future<void> registerValues(WidgetTester t) async {
  await fill(t, 'account', 'reader');
  await fill(t, 'email', 'reader@example.invalid');
  await fill(t, 'password', 'fixture-password');
  await fill(t, 'confirm', 'fixture-password');
}

Future<void> resetValues(
  WidgetTester t, {
  String password = 'new-fixture-password',
}) async {
  await fill(t, 'token', 't' * 43);
  await fill(t, 'password', password);
  await fill(t, 'confirm', password);
}

Future<http.Response> prepare(http.Request request) async {
  if (request.url.path.endsWith('/csrf-token')) return csrf();
  if (request.url.path.endsWith('/register-config')) {
    return http.Response(
      '{"code":0,"data":{"invite_code_enabled":false}}',
      200,
    );
  }
  throw StateError('Unexpected preparation request');
}

void main() {
  for (final pending in [true, false]) {
    testWidgets(
      'registration outcome is authoritative and success cannot submit again ($pending)',
      (t) async {
        var posts = 0, back = 0;
        await mount(t, AccountForm.register, (request) async {
          if (request.url.path.endsWith('/register')) {
            posts++;
            return response(200, pending ? '注册成功，请等待管理员审批' : '注册成功，请登录');
          }
          return prepare(request);
        }, back: () => back++);
        await registerValues(t);
        await submit(t);
        expect(posts, 1);
        expect(
          find.text(
            en.text(
              pending
                  ? 'authRegistrationPendingBody'
                  : 'authRegistrationApprovedBody',
            ),
          ),
          findsOneWidget,
        );
        await t.scrollUntilVisible(
          find.byKey(const Key('password')),
          -160,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(field(t, 'password').controller!.text, '');
        expect(field(t, 'confirm').controller!.text, '');
        expect(field(t, 'password').readOnly, true);
        await t.scrollUntilVisible(
          find.byKey(const Key('account')),
          -160,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(field(t, 'account').controller!.text, 'reader');
        expect(field(t, 'email').controller!.text, 'reader@example.invalid');
        await submit(t);
        expect(back, 1);
        expect(posts, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'lost reset response preserves inputs and primary action checks sign-in instead of replay',
    (t) async {
      var posts = 0, back = 0;
      await mount(t, AccountForm.reset, (request) async {
        if (request.url.path.endsWith('/csrf-token')) return csrf();
        posts++;
        throw http.ClientException('private response detail');
      }, back: () => back++);
      await resetValues(t);
      await submit(t);
      expect(find.text(en.text('authUnconfirmedTitle')), findsOneWidget);
      expect(find.text('private response detail'), findsNothing);
      expect(posts, 1);
      await t.scrollUntilVisible(
        find.byKey(const Key('token')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(field(t, 'token').controller!.text, 't' * 43);
      expect(field(t, 'password').controller!.text, 'new-fixture-password');
      expect(field(t, 'token').readOnly, true);
      await submit(t);
      expect(back, 1);
      expect(posts, 1);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'CSRF preparation failure permits retry and is not shown as an uncertain reset',
    (t) async {
      var gets = 0, posts = 0;
      await mount(t, AccountForm.reset, (request) async {
        if (request.url.path.endsWith('/csrf-token')) {
          gets++;
          if (gets == 1) {
            throw http.ClientException('private preparation detail');
          }
          return csrf();
        }
        posts++;
        return response(200, '密码已重置，请使用新密码登录');
      });
      await resetValues(t);
      await submit(t);
      expect(find.text(en.text('authConnectionFailedTitle')), findsOneWidget);
      expect(find.text(en.text('authUnconfirmedTitle')), findsNothing);
      expect(posts, 0);
      await submit(t);
      expect(posts, 1);
      expect(find.text(en.text('authResetCompleteTitle')), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'invalid reset receipt keeps editable values and names the link failure',
    (t) async {
      var posts = 0;
      await mount(t, AccountForm.reset, (request) async {
        if (request.url.path.endsWith('/csrf-token')) return csrf();
        posts++;
        return response(400, '重置链接无效或已过期');
      });
      await resetValues(t);
      await submit(t);
      expect(find.text(en.text('authResetInvalidTitle')), findsOneWidget);
      expect(posts, 1);
      await t.scrollUntilVisible(
        find.byKey(const Key('token')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(field(t, 'token').controller!.text, 't' * 43);
      expect(field(t, 'token').readOnly, false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'large English mail failure is accessible and only explicit retry requests again',
    (t) async {
      var posts = 0;
      var available = false;
      await mount(t, AccountForm.forgot, (request) async {
        if (request.url.path.endsWith('/csrf-token')) return csrf();
        posts++;
        return available
            ? response(200, '如果账号存在，重置密码邮件将发送到注册邮箱')
            : response(503, '找回密码服务暂不可用，请联系管理员');
      }, large: true);
      await fill(t, 'identity', 'reader@example.invalid');
      await submit(t);
      await t.scrollUntilVisible(
        find.text(en.text('authMailUnavailableTitle')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text(en.text('authMailUnavailableTitle')), findsOneWidget);
      final semantics = t.ensureSemantics();
      await t.pumpAndSettle();
      final node = t.getSemantics(
        find.text(en.text('authMailUnavailableTitle')),
      );
      expect(node.getSemanticsData().flagsCollection.isTextField, false);
      semantics.dispose();
      expect(posts, 1);
      available = true;
      await submit(t);
      expect(posts, 2);
      await t.scrollUntilVisible(
        find.byKey(const Key('form-success')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('form-success')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('form-success')),
          matching: find.text(en.text('resetNotice')),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('registration pending request disables double submission', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    await mount(t, AccountForm.register, (request) async {
      if (request.url.path.endsWith('/register')) {
        posts++;
        return pending.future;
      }
      return prepare(request);
    });
    await registerValues(t);
    await submit(t);
    expect(posts, 1);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    expect(posts, 1);
    pending.complete(response(200, '注册成功，请登录'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('form-success')), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('UTF8 password limit is checked before any HTTP', (t) async {
    var requests = 0;
    await mount(t, AccountForm.reset, (request) async {
      requests++;
      return csrf();
    });
    await resetValues(t, password: '界' * 25);
    await submit(t);
    expect(find.text(en.text('passwordLong')), findsOneWidget);
    expect(requests, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('full same-prefix reset link submits only its token', (t) async {
    Map<String, dynamic>? sent;
    await mount(t, AccountForm.reset, (request) async {
      if (request.url.path.endsWith('/csrf-token')) return csrf();
      expect(request.url.path, '/team/api/password/reset');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return response(200, '密码已重置，请使用新密码登录');
    });
    await resetValues(t);
    await fill(
      t,
      'token',
      'https://books.example/team/reset-password#token=${'t' * 43}',
    );
    await submit(t);
    expect(sent?['token'], 't' * 43);
    expect(sent?['new_password'], 'new-fixture-password');
    await t.scrollUntilVisible(
      find.byKey(const Key('token')),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(field(t, 'token').controller!.text, '');
    expect(field(t, 'password').controller!.text, '');
    await submit(t);
    expect(sent?['token'], 't' * 43);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'same origin with wrong deployment prefix is rejected before HTTP',
    (t) async {
      var requests = 0;
      await mount(t, AccountForm.reset, (_) async {
        requests++;
        return csrf();
      });
      await resetValues(t);
      await fill(
        t,
        'token',
        'https://books.example/reset-password#token=${'t' * 43}',
      );
      await submit(t);
      expect(find.text(en.text('wrongResetServer')), findsOneWidget);
      expect(requests, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
