import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_page.dart';
import 'admin_remote_dav_models_test.dart' show davServer;

class _OwnedWindow implements AdminAssetWindowGuard {
  int acquired = 0, closed = 0;
  @override
  Future<void> acquire() async {
    acquired++;
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late int writes, builtin, reads;
  late _OwnedWindow window;
  late Map<String, dynamic> server;
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  setUp(() {
    window = _OwnedWindow();
    writes = 0;
    builtin = 0;
    reads = 0;
    server = davServer();
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/profile')) {
          return json({'member_id': 1, 'account': 'owned-owner', 'role': 0});
        }
        if (request.url.path.endsWith('/credentials')) {
          return json([
            {
              'id': 7,
              'name': 'Owned password',
              'username': 'fixture',
              'auth_type': 'password',
              'credential_hint': 'hidden',
              'created_by': 1,
              'create_time': '2026-11-08T00:00:00.000000001Z',
              'modify_time': '2026-11-08T00:00:00.000000002Z',
            },
          ]);
        }
        if (request.method == 'GET' && request.url.path.endsWith('/files')) {
          return json({'items': [], 'limit': 1000, 'truncated': false});
        }
        if (request.method == 'GET') {
          reads++;
          return json([
            {'id': 'local', 'built_in': true, 'name': 'BookStark 内置 WebDAV'},
            server,
          ]);
        }
        writes++;
        expect(request.headers['x-csrf-token'], 'owned-dav-csrf');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'name',
          'url',
          'root_path',
          'credential_id',
        });
        server = {...server, ...body};
        return json(server);
      }),
    );
    client.restoreSession({
      'token': 'owned-dav-token',
      'csrf_token': 'owned-dav-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
  });
  tearDown(() {
    scope.dispose();
    client.close();
  });
  Future<void> show(WidgetTester tester, {bool large = false}) async {
    final oldHitTestGuard = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = oldHitTestGuard,
    );
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!,
        ),
        home: AdminDavPage(
          scope: scope,
          secureWindowFactory: () => window,
          onReturn: () {},
          onBuiltin: () => builtin++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'editing a stored credential URL requires an explicit replacement',
    (tester) async {
      server['url'] = 'https://user:secret@dav.invalid/prefix?ak=hidden';
      await show(tester);
      expect(find.textContaining('secret'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('编辑').last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, '编辑');
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'WebDAV URL'),
      );
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('原地址中的认证参数已隐藏'), findsOneWidget);
      await tap(tester, '下一步');
      expect(writes, 0);
      expect(find.textContaining('请检查名称'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'catalog enters DAV files with the provided guard and retires it on return',
    (tester) async {
      await show(tester);
      await tap(tester, '浏览文件');
      expect(find.text('WebDAV 文件'), findsOneWidget);
      expect(find.text('目录为空'), findsOneWidget);
      expect(window.acquired, 1);
      await tester.tap(find.byTooltip('返回').last);
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 连接'), findsOneWidget);
      expect(window.closed, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'builtin opens its own management callback without remote mutation',
    (tester) async {
      await show(tester);
      await tap(tester, '管理内置 WebDAV');
      expect(builtin, 1);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new connection requires explicit metadata review before dispatch',
    (tester) async {
      await show(tester);
      await tap(tester, '添加连接');
      expect(find.text('连接设置'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '连接名称'),
        'Reviewed DAV',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'WebDAV URL'),
        'https://dav.invalid/prefix',
      );
      await tap(tester, 'Owned password');
      await tap(tester, '下一步');
      expect(find.text('核对连接操作'), findsOneWidget);
      expect(writes, 0);
      await tap(tester, '确认操作');
      expect(writes, 1);
      expect(find.text('WebDAV 连接'), findsOneWidget);
      expect(find.text('已收到服务器确认'), findsOneWidget);
      expect(server['name'], 'Reviewed DAV');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'background clears form and never submits or automatically rereads',
    (tester) async {
      await show(tester);
      await tap(tester, '添加连接');
      await tester.enterText(
        find.widgetWithText(TextField, '连接名称'),
        'owned discarded draft',
      );
      final before = reads;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.every((field) => field.controller!.text.isEmpty), true);
      expect(writes, 0);
      expect(reads, before);
      expect(find.text('切到后台后已清除表单，请返回重新打开。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow large-font catalog and form remain scrollable without overflow',
    (tester) async {
      await show(tester, large: true);
      expect(tester.takeException(), isNull);
      await tap(tester, '添加连接');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Owned password');
      expect(tester.takeException(), isNull);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
