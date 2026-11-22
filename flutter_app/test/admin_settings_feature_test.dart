import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_ai_settings_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const owner = AdminPrincipal(memberId: 41, account: 'admin-fixture', role: 0);

class Fixture {
  int role = 0;
  final paths = <String>[];
  late final client = BookstarkClient(
    'https://example.invalid/mount',
    transport: MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      Object? data;
      if (request.url.path.endsWith('/api/profile')) {
        data = {
          'member_id': 41,
          'account': 'admin-fixture',
          'role': role,
          'email': 'admin@example.invalid',
          'default_home': 'home',
        };
      } else if (request.url.path.endsWith('/api/admin/settings')) {
        data = [
          for (final entry in {
            'ai_enabled': '1',
            'ai_provider': 'openai',
            'ai_base_url': 'https://ai.example.invalid/v1',
            'ai_api_key': 'fixture-secret',
            'ai_model': 'fixture-model',
            'ai_temperature': '0.7',
            'ai_max_tokens': '2048',
          }.entries)
            {
              'key': entry.key,
              'value': entry.value,
              'description': '',
              'update_time': '',
            },
        ];
      } else if (request.url.path.endsWith(
        '/api/labels/recommendation-settings',
      )) {
        data = {
          'strategy': 'recent',
          'manual_labels': <String>[],
          'page_size': 10,
        };
      } else {
        throw StateError('Unexpected fixture endpoint');
      }
      return http.Response(
        jsonEncode({'code': 0, 'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  )..restoreSession({'token': 'fixture-token'});
}

class PushObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  testWidgets(
    'settings owns nested leave dialogs and clears all fields on scope close',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = Fixture();
      final scope = AdminSettingsScope(fixture.client, owner);
      final observer = PushObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: AdminSettingsFeature(scope: scope, onReturn: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final ai = find.text('AI 模型与提示词');
      await tester.scrollUntilVisible(
        ai,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(ai);
      await tester.pumpAndSettle();
      expect(find.byType(AdminAiSettingsPage), findsOneWidget);
      final model = find.byKey(const ValueKey('ai_model'));
      await tester.ensureVisible(model);
      await tester.enterText(model, 'changed-model');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('离开 AI 配置？'), findsOneWidget);
      expect(
        observer.pushes,
        1,
      ); // Dialog belongs to the nested settings navigator.
      scope.close();
      await tester.pumpAndSettle();
      expect(find.text('离开 AI 配置？'), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('管理员会话已结束，请返回后重新进入。'), findsOneWidget);
      expect(fixture.paths.every((path) => path.startsWith('GET ')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    },
  );
  testWidgets('demoted owner cannot enable settings links or read settings', (
    tester,
  ) async {
    final fixture = Fixture()..role = 1;
    final scope = AdminSettingsScope(fixture.client, owner);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSettingsFeature(scope: scope, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('管理员身份或会话已变化，请重新进入。'), findsOneWidget);
    final tile = find.ancestor(
      of: find.text('通用设置'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(tile).onTap, isNull);
    expect(
      fixture.paths.where((path) => path.endsWith('/api/admin/settings')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
  });
  testWidgets(
    'all settings routes are reached through real navigation without mutations',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = Fixture();
      final scope = AdminSettingsScope(fixture.client, owner);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsFeature(scope: scope, onReturn: () {}),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> open(String label) async {
        final target = find.text(label);
        await tester.scrollUntilVisible(
          target.hitTestable(),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(target.hitTestable());
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }

      await open('通用设置');
      await open('分页与列表');
      expect(find.byKey(const ValueKey('page_size_books')), findsOneWidget);
      await back();
      await back();
      await open('内容与上传');
      await open('标签推荐');
      expect(
        find.byKey(const ValueKey('tag_recommend_page_size')),
        findsOneWidget,
      );
      await back();
      await open('公开页面标签');
      expect(find.text('明确替换为新的自动模式草稿'), findsOneWidget);
      await back();
      await back();
      await open('访问与注册');
      expect(find.byKey(const ValueKey('invite_code')), findsOneWidget);
      await open('协作信令');
      expect(
        find.byKey(const ValueKey('webrtc_signaling_default_url')),
        findsOneWidget,
      );
      await back();
      await back();
      await open('AI 模型与提示词');
      await open('系统提示词');
      expect(find.text('Markdown'), findsOneWidget);
      await back();
      await open('编辑动作');
      expect(find.text('选中文本'), findsOneWidget);
      await back();
      await back();
      await open('邮件服务');
      await open('SMTP 连接');
      expect(find.byKey(const ValueKey('smtp_host')), findsOneWidget);
      await back();
      await back();
      await open('WebDAV 服务');
      expect(
        find.byKey(const ValueKey('webdav_file_max_bytes')),
        findsOneWidget,
      );
      await back();
      await open('终端策略');
      expect(
        find.byKey(const ValueKey('asset_terminal_idle_timeout_seconds')),
        findsOneWidget,
      );
      await back();
      expect(fixture.paths.every((path) => path.startsWith('GET ')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    },
  );

  test('scope rejects a replaced session and disposes owned form', () {
    final fixture = Fixture();
    final scope = AdminSettingsScope(fixture.client, owner);
    final notifier = scope.own(_Owned());
    fixture.client.restoreSession({'token': 'replacement-token'});
    expect(scope.guard(), isFalse);
    expect(notifier.wasDisposed, isTrue);
    expect(scope.closed, isTrue);
    scope.dispose();
  });
}

class _Owned extends ChangeNotifier {
  bool wasDisposed = false;
  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}
