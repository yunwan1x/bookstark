import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/features/sharing/share_settings_page.dart';
import 'package:bookstark_flutter/features/sharing/content_password_page.dart';
import 'share_settings_controller_test.dart' as sharing;
import 'content_password_controller_test.dart' as passwords;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

OwnerShareTarget target() => OwnerShareTarget(
  kind: PublicShareKind.blog,
  id: 7,
  title: 'Actual owner note',
);
void main() {
  testWidgets(
    'sharing never publishes on opening or cancellation; explicit receipt separates clipboard capabilities',
    (tester) async {
      final repo = sharing.Repo();
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ShareSettingsPage(target: target(), repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tap(tester, find.text('公开并获取链接'));
      await tap(tester, find.text('取消'));
      expect(repo.writes, 0);
      await tap(tester, find.text('公开并获取链接'));
      await tap(tester, find.text('确认公开并获取'));
      expect(repo.writes, 1);
      await tap(tester, find.text('复制链接'));
      expect(copied, 'https://example.test/shares/actual');
      expect(find.textContaining(repo.token), findsNothing);
      await tap(tester, find.text('复制编辑链接'));
      expect(Uri.parse(copied!).queryParameters['token'], repo.token);
      expect(find.textContaining(repo.token), findsNothing);
    },
  );
  testWidgets(
    'unknown reset hides old token controls, status check does not resend mutation',
    (tester) async {
      final repo = sharing.Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: ShareSettingsPage(target: target(), repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('公开并获取链接'));
      await tap(tester, find.text('确认公开并获取'));
      repo.lose = true;
      await tap(tester, find.text('重置编辑链接'));
      await tap(tester, find.text('确认'));
      expect(repo.writes, 2);
      expect(find.text('复制编辑链接'), findsNothing);
      await tap(tester, find.text('核对发布状态'));
      expect(repo.writes, 2);
      expect(find.textContaining('编辑令牌仍待核对'), findsOneWidget);
      expect(find.text('重置编辑链接'), findsNothing);
    },
  );
  testWidgets(
    'English 320dp 200 percent whole publication dialog scrolls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ShareSettingsPage(
            target: target(),
            repository: sharing.Repo(),
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Publish and obtain links'));
      expect(find.text('Publish and obtain links?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Cancel'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('whole book never offers editing or password controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShareSettingsPage(
          target: OwnerShareTarget(
            kind: PublicShareKind.book,
            id: 9,
            title: 'Book',
          ),
          repository: sharing.Repo(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('管理内容密码'), findsNothing);
    expect(find.text('书籍整本不支持编辑链接。'), findsOneWidget);
  });
  testWidgets(
    'setting password preserves spaces, clears all fields and verifies actual candidate',
    (tester) async {
      final repo = passwords.Repo();
      await tester.pumpWidget(
        MaterialApp(home: ContentPasswordPage(id: 7, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), ' new raw ');
      await tester.enterText(find.byType(TextFormField).at(1), ' new raw ');
      await tap(tester, find.text('设置密码'));
      expect(repo.password, ' new raw ');
      expect(repo.writes, 1);
      expect(repo.verifies, 1);
      expect(find.text('密码更改已核对。'), findsOneWidget);
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
    },
  );
  testWidgets(
    'lost password write disables new mutation and verifies result by read only action',
    (tester) async {
      final repo = passwords.Repo()..lost = true;
      await tester.pumpWidget(
        MaterialApp(home: ContentPasswordPage(id: 7, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'candidate');
      await tester.enterText(find.byType(TextFormField).at(1), 'candidate');
      await tap(tester, find.text('设置密码'));
      expect(repo.writes, 1);
      expect(find.byType(TextFormField), findsNothing);
      await tap(tester, find.text('只读核对更改结果'));
      expect(repo.writes, 1);
      expect(find.textContaining('上次写回执仍未知'), findsOneWidget);
    },
  );
  testWidgets(
    'removal requires current password and explicit confirmation without changing public settings',
    (tester) async {
      final repo = passwords.Repo()..password = 'old';
      await tester.pumpWidget(
        MaterialApp(home: ContentPasswordPage(id: 7, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'old');
      await tap(tester, find.text('验证并移除密码'));
      await tap(tester, find.text('取消'));
      expect(repo.writes, 0);
      await tap(tester, find.text('验证并移除密码'));
      await tap(tester, find.text('验证并移除'));
      expect(repo.writes, 1);
      expect(repo.password, isNull);
      expect(find.text('密码更改已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'English small password keyboard and confirmation do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = passwords.Repo()..password = 'old';
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 250),
            ),
            child: child!,
          ),
          home: ContentPasswordPage(id: 7, repository: repo, english: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'old');
      await tap(tester, find.text('Verify and remove password'));
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Cancel'));
      expect(tester.takeException(), isNull);
      expect(repo.writes, 0);
    },
  );
}
