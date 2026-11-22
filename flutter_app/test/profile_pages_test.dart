import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/profile/profile_edit_page.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'profile_edit_controller_test.dart' as fixture;

Future<void> click(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'profile hub reads actual fields and explicit edit saves only after user action',
    (tester) async {
      final repo = fixture.Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            repository: repo,
            server: Uri.parse('https://example.test/base'),
            onLanguage: (_) async {},
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      expect(find.text('邮箱  old@example.test'), findsOneWidget);
      expect(find.text('账户安全'), findsNothing);
      await click(tester, find.text('编辑资料'));
      await tester.enterText(find.byType(TextFormField), ' new@example.test ');
      await click(tester, find.text('保存资料'));
      expect(repo.writes, 1);
      expect(find.text('资料保存已核对'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('邮箱  new@example.test'), findsOneWidget);
    },
  );
  testWidgets(
    'typing during save is retained and remains unsaved after earlier receipt',
    (tester) async {
      final repo = fixture.Repo()..wait = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(repository: repo, profile: fixture.member()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'first@example.test');
      await tester.ensureVisible(find.text('保存资料'));
      await tester.tap(find.text('保存资料'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'later@example.test');
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'later@example.test',
      );
      expect(find.text('有未保存修改'), findsOneWidget);
      expect(find.text('上次提交已核对，当前输入尚未保存。'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown result can be checked without resending and keeps later local inputs',
    (tester) async {
      final repo = fixture.Repo()..lose = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(repository: repo, profile: fixture.member()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'first@example.test');
      await click(tester, find.text('保存资料'));
      expect(repo.writes, 1);
      await tester.enterText(find.byType(TextFormField), 'later@example.test');
      await click(tester, find.text('只读核对提交结果'));
      expect(repo.writes, 1);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'later@example.test',
      );
      expect(find.text('有未保存修改'), findsOneWidget);
    },
  );
  testWidgets(
    'conflict shows observed remote fields and adopting them needs explicit confirmation',
    (tester) async {
      final repo = fixture.Repo()
        ..current = fixture.member(email: 'remote@example.test');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditPage(repository: repo, profile: fixture.member()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'mine@example.test');
      await click(tester, find.text('保存资料'));
      expect(repo.writes, 0);
      await click(tester, find.text('采用服务器资料'));
      await click(tester, find.text('取消'));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'mine@example.test',
      );
      await click(tester, find.text('采用服务器资料'));
      await click(tester, find.text('采用服务器资料').last);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'remote@example.test',
      );
      expect(repo.writes, 0);
    },
  );
  testWidgets(
    'English 320dp200 keyboard profile editor and conflict confirmation fit by scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = fixture.Repo()
        ..current = fixture.member(email: 'remote@example.test');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 240),
            ),
            child: child!,
          ),
          home: ProfileEditPage(
            repository: repo,
            profile: fixture.member(),
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'mine@example.test');
      await click(tester, find.text('Save profile'));
      await click(tester, find.text('Keep mine and recheck'));
      expect(tester.takeException(), isNull);
      await click(tester, find.text('Cancel'));
      expect(tester.takeException(), isNull);
      expect(repo.writes, 0);
    },
  );
  testWidgets(
    'logout cancellation and navigation are explicit and never save profile fields',
    (tester) async {
      var logouts = 0;
      final routes = <String>[], repo = fixture.Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            repository: repo,
            server: Uri.parse('https://example.test'),
            onLanguage: (_) async {},
            onLogout: () async {
              logouts++;
            },
            onNavigate: routes.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await click(tester, find.text('退出服务器空间'));
      await click(tester, find.text('取消'));
      expect(logouts, 0);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('文件'),
        ),
      );
      await tester.pumpAndSettle();
      expect(routes, ['files']);
      expect(repo.writes, 0);
    },
  );
}
