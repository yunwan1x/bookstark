import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_page.dart';
import 'admin_terminal_page_test.dart' as f;
import 'admin_terminal_access_test.dart' as fixture;

class Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

class Parent extends StatefulWidget {
  const Parent({super.key, required this.navigator, required this.routes});
  final GlobalKey<NavigatorState> navigator;
  final Routes routes;
  @override
  State<Parent> createState() => ParentState();
}

class ParentState extends State<Parent> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    for (final route in widget.routes.routes.skip(1).toList().reversed) {
      if (route.isActive) widget.navigator.currentState!.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: widget.navigator,
    observers: [widget.routes],
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Owned root retained')),
    ),
  );
}

void main() {
  for (final parentFirst in [true, false]) {
    testWidgets(
      'container dialog and parent background retirement preserve nested root parentFirst=$parentFirst',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final client = BookstarkClient(
          'https://owned.invalid',
          transport: MockClient((request) async {
            final Object data = request.url.path.endsWith('/profile')
                ? {'member_id': 1, 'account': 'owned-owner', 'role': 0}
                : request.url.path.endsWith('/settings')
                ? {
                    'terminal_idle_timeout_seconds': 1800,
                    'terminal_scrollback_lines': 1000,
                    'credential_secret': '',
                  }
                : [fixture.host()];
            return http.Response(
              jsonEncode({'code': 0, 'data': data}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        client.restoreSession({'token': 'owned-test-token'});
        final scope = AdminAssetsScope(
          client,
          const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
        );
        final secure = f.Secure(), wire = f.Wire();
        final key = GlobalKey<NavigatorState>(), routes = Routes();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          scope.dispose();
          client.close();
          await wire.frames.close();
          debugDefaultTargetPlatformOverride = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async => call.method == 'Clipboard.getData'
                  ? {'text': 'owned-dialog-paste'}
                  : null,
            );
        await tester.pumpWidget(
          MaterialApp(
            home: Parent(navigator: key, routes: routes),
          ),
        );
        await tester.pumpAndSettle();
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => AdminTerminalPage(
              scope: scope,
              host: AdminAssetHostMetadata.parse(fixture.host()),
              containerId: List.filled(64, 'a').join(),
              containerName: 'owned-container',
              secureWindow: secure,
              onReturn: () {},
              transportFactory: () => wire,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接终端'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接终端'));
        await tester.pumpAndSettle();
        expect(find.text('已连接'), findsOneWidget);
        await tester.tap(find.text('粘贴'));
        await tester.pumpAndSettle();
        expect(find.text('owned-dialog-paste'), findsOneWidget);
        if (!parentFirst) {
          final parent = tester.state<ParentState>(find.byType(Parent));
          tester.binding.removeObserver(parent);
          tester.binding.addObserver(parent);
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Owned root retained'), findsOneWidget);
        expect(find.text('owned-dialog-paste'), findsNothing);
        expect(wire.aborts, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
