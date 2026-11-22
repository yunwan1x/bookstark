import 'package:bookstark_flutter/widgets/background_surface.dart';
import 'package:bookstark_flutter/features/profile/background_page.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/features/profile/account_security_page.dart';
import 'package:bookstark_flutter/features/profile/reminder_page.dart';
import 'package:bookstark_flutter/main.dart';

class Server {
  Future<http.Response?> Function(http.Request)? extra;
  String email = 'old@example.test', home = 'home';
  int writes = 0, passwordWrites = 0, logins = 0, reminderWrites = 0;
  Map<String, Object?> reminder = {
    'enabled': false,
    'send_time': '09:00',
    'remind_before_days': 1,
    'include_overdue': true,
  };
  String password = 'old-password';
  Map<String, Object?>? background;
  bool validLogin = false;
  String? restoredCookie;
  final paths = <String>[];
  http.Response data(Map<String, Object?> row) => http.Response.bytes(
    utf8.encode(jsonEncode({'code': 0, 'data': row})),
    200,
    headers: {'content-type': 'application/json'},
  );
  BookstarkClient client(String base) => BookstarkClient(
    base,
    transport: MockClient((r) async {
      paths.add('${r.method} ${r.url.path}');
      final additional = await extra?.call(r);
      if (additional != null) {
        return additional;
      }
      if (r.url.path == '/api/profile/background') {
        if (background == null) {
          return http.Response(
            '{"code":404}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.method == 'PUT') {
          final text = utf8.decode(r.bodyBytes, allowMalformed: true);
          String field(String name) => RegExp(
            'name="$name"\\r\\n\\r\\n([^\\r]+)',
          ).firstMatch(text)!.group(1)!;
          background = {
            'mode': field('mode'),
            'animated': field('animated') == 'true',
            'fade': int.parse(field('fade')),
            'image_hash': '',
          };
        }
        return data(background!);
      }
      if (r.url.path == '/api/profile/task-reminder') {
        if (r.method == 'PUT') {
          reminderWrites++;
          reminder = Map<String, Object?>.from(jsonDecode(r.body) as Map);
          return http.Response(
            '{"code":0,"message":"saved"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return data({
          ...reminder,
          'email': email,
          'available': true,
          'last_processed_date': '',
        });
      }
      if (r.url.path == '/api/password') {
        passwordWrites++;
        final row = jsonDecode(r.body) as Map;
        if (row['old_password'] != password) {
          return http.Response('{"message":"wrong"}', 400);
        }
        password = row['new_password'] as String;
        return http.Response(
          '{"code":0,"message":"changed"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.url.path == '/api/login') {
        logins++;
        final row = jsonDecode(r.body) as Map;
        validLogin =
            row['account'] == 'root-profile-fixture' &&
            row['password'] == password;
        return http.Response(
          '{"code":0,"message":"signed in"}',
          validLogin ? 200 : 401,
          headers: {
            'content-type': 'application/json',
            'set-cookie': 'token=new-verified-session; Path=/; HttpOnly',
          },
        );
      }

      if (r.url.path == '/api/home') {
        restoredCookie = r.headers['cookie'];
        return data({
          'recent': [],
          'sections': [],
          'activity': <String, int>{},
          'layout': null,
        });
      }
      if (r.url.path == '/api/profile') {
        if (r.method == 'PUT') {
          writes++;
          final body = jsonDecode(r.body) as Map;
          email = body['email'] as String;
          home = body['default_home'] as String;
          return http.Response(
            '{"code":0,"message":"updated"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return data({
          'member_id': 7,
          'account': 'root-profile-fixture',
          'email': email,
          'role': 1,
          'default_home': home,
        });
      }
      if (r.url.path == '/api/blogs') {
        return data({'data': [], 'total': 0});
      }
      throw StateError('Unexpected profile root request');
    }),
  );
}

void seed() {
  FlutterSecureStorage.setMockInitialValues({
    'bookstark.flutter.language': 'zh',
    'bookstark.flutter.session': jsonEncode({
      'server': 'https://example.test',
      'cookies': {'token': 'fixture-session', 'csrf_token': 'csrf'},
    }),
  });
}

Future<void> click(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real root opens profile, saves actual fields, persists language, restores default module then logs out',
    (tester) async {
      seed();
      final server = Server();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(server.writes, 0);
      await click(tester, find.text('编辑资料'));
      await tester.enterText(
        find.byType(TextFormField),
        'root-new@example.test',
      );
      await click(tester, find.text('笔记'));
      await click(tester, find.text('保存资料'));
      expect(server.writes, 1);
      expect(server.home, 'notes');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await click(tester, find.text('应用语言'));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('App language'), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(
          key: 'bookstark.flutter.language',
        ),
        'en',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      expect(find.text('App language'), findsOneWidget);
      expect(find.text('Email  root-new@example.test'), findsOneWidget);
      await click(tester, find.text('Leave server space'));
      await click(tester, find.text('Leave server'));
      expect(find.byType(ConnectionPage), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(
          key: 'bookstark.flutter.session',
        ),
        isNull,
      );
      expect(server.writes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'profile bottom navigation returns through real root and opens actual notes repository',
    (tester) async {
      seed();
      final server = Server();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('知识'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotesPage), findsOneWidget);
      expect(server.paths, contains('GET /api/blogs'));
      expect(server.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'actual root security adopts and securely saves fresh verified cookie across restart',
    (tester) async {
      seed();
      final server = Server();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('账户安全'));
      expect(find.byType(AccountSecurityPage), findsOneWidget);
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(
          fields.at(i),
          i == 0 ? 'old-password' : ' new 密码 ',
        );
      }
      await click(tester, find.widgetWithText(FilledButton, '修改登录密码'));
      expect(find.text('登录密码修改已核对，当前会话已保存。'), findsOneWidget);
      expect(server.passwordWrites, 1);
      expect(server.logins, 1);
      expect(server.validLogin, isTrue);
      final stored =
          jsonDecode(
                (await const FlutterSecureStorage().read(
                  key: 'bookstark.flutter.session',
                ))!,
              )
              as Map;
      expect((stored['cookies'] as Map)['token'], 'new-verified-session');
      expect(stored.toString(), isNot(contains('new 密码')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      expect(server.restoredCookie, contains('token=new-verified-session'));
      expect(server.passwordWrites, 1);
      expect(server.logins, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'root reminder entry saves real repository then returns from actual profile email editor and reloads recipient',
    (tester) async {
      seed();
      final server = Server();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('邮件提醒'));
      expect(find.byType(ReminderPage), findsOneWidget);
      await click(tester, find.byTooltip('增加提前天数'));
      await click(tester, find.text('保存提醒设置'));
      expect(server.reminderWrites, 1);
      expect(server.reminder['remind_before_days'], 2);
      await click(tester, find.text('修改邮箱'));
      await tester.enterText(
        find.byType(TextFormField),
        'reminder-new@example.invalid',
      );
      await click(tester, find.text('保存资料'));
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderPage), findsOneWidget);
      expect(find.text('接收邮箱: reminder-new@example.invalid'), findsOneWidget);
      expect(
        server.paths.where((p) => p.endsWith('/task-reminder/test')),
        isEmpty,
      );
      expect(server.writes, 1);
      expect(server.reminderWrites, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account background restores from server, applies only confirmed save and clears on logout',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      seed();
      final server = Server()
        ..background = {
          'mode': 'dynamic',
          'animated': true,
          'fade': 65,
          'image_hash': '',
        };
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      expect(find.byType(AccountBackgroundScope), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ??
            Theme.of(
              tester.element(find.byType(Scaffold).first),
            ).scaffoldBackgroundColor,
        Colors.transparent,
      );
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('外观与背景'));
      expect(find.byType(BackgroundPage), findsOneWidget);
      await click(tester, find.text('纯色'));
      expect(server.background!['mode'], 'dynamic');
      await click(tester, find.text('保存背景设置'));
      expect(server.background!['mode'], 'solid');
      expect(find.text('实际背景设置已核对。'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await click(tester, find.text('退出服务器空间'));
      await click(tester, find.text('确认退出'));
      expect(find.byType(AccountBackgroundScope), findsNothing);
      expect(find.byType(ConnectionPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
