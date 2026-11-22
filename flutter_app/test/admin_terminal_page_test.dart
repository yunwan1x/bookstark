import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_page.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'admin_terminal_access_test.dart' as fixtures;

class Secure implements AdminAssetWindowGuard {
  int acquisitions = 0, releases = 0;
  Completer<void>? gate;
  @override
  Future<void> acquire() async {
    acquisitions++;
    if (gate != null) await gate!.future;
  }

  @override
  Future<void> close() async {
    releases++;
  }
}

class Wire implements TerminalTransport {
  final frames = StreamController<Object?>();
  final sent = <Map<String, dynamic>>[];
  int aborts = 0;
  @override
  Future<Stream<Object?>> connect(Uri endpoint, String token) async {
    scheduleMicrotask(() => frames.add('{"type":"ready","data":"connected"}'));
    return frames.stream;
  }

  @override
  void send(String frame) {
    sent.add(jsonDecode(frame) as Map<String, dynamic>);
  }

  @override
  void abort() {
    aborts++;
  }
}

void main() {
  late BookstarkClient client;
  late AdminAssetsScope scope;
  late Secure secure;
  late List<Wire> wires;
  late int reads, returns;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    wires = [];
    reads = 0;
    returns = 0;
    secure = Secure();
    client = BookstarkClient(
      'https://owned.invalid',
      transport: MockClient((request) async {
        reads++;
        final Object data = request.url.path.endsWith('/profile')
            ? {'member_id': 1, 'account': 'owned-owner', 'role': 0}
            : request.url.path.endsWith('/settings')
            ? {
                'terminal_idle_timeout_seconds': 1800,
                'terminal_scrollback_lines': 1000,
                'credential_secret': '',
              }
            : [fixtures.host()];
        return http.Response(
          jsonEncode({'code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client.restoreSession({'token': 'owned-test-token'});
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
  });
  tearDown(() async {
    scope.dispose();
    client.close();
    for (final wire in wires) {
      await wire.frames.close();
    }
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  Future<void> show(
    WidgetTester tester, {
    double scale = 1,
    bool english = false,
    bool container = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AdminTerminalPage(
          scope: scope,
          host: AdminAssetHostMetadata.parse(fixtures.host()),
          secureWindow: secure,
          containerId: container ? List.filled(64, "a").join() : null,
          containerName: container ? "owned-container" : null,
          english: english,
          onReturn: () => returns++,
          transportFactory: () {
            final wire = Wire();
            wires.add(wire);
            return wire;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.text('连接终端'));
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  }

  for (final english in [false, true]) {
    testWidgets(
      'container idle 320dp200% retains target and visible panel english=$english',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await show(tester, container: true, english: english, scale: 2);
        expect(
          find.byKey(const ValueKey('docker-terminal-target')),
          findsOneWidget,
        );
        final panel = tester.getRect(
          find.byKey(const ValueKey('docker-terminal-idle-panel')),
        );
        expect(panel.height, greaterThanOrEqualTo(120));
        expect(panel.bottom, lessThanOrEqualTo(740));
        expect(reads, 0);
        expect(wires, isEmpty);
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }

  testWidgets(
    'container idle requires explicit full review before any connection',
    (tester) async {
      await show(tester, container: true);
      expect(find.text('尚未连接'), findsOneWidget);
      expect(reads, 0);
      expect(wires, isEmpty);
      await tester.tap(find.text('连接终端'));
      await tester.pumpAndSettle();
      expect(find.text('尚未连接'), findsNothing);
      expect(find.textContaining(List.filled(64, 'a').join()), findsOneWidget);
      expect(reads, 0);
      expect(wires, isEmpty);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('尚未连接'), findsOneWidget);
      expect(returns, 0);
      await close(tester);
    },
  );

  testWidgets(
    'container background discards review without reconnecting on resume',
    (tester) async {
      await show(tester, container: true);
      await tester.tap(find.text('连接终端'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('尚未连接'), findsOneWidget);
      expect(reads, 0);
      expect(wires, isEmpty);
      await close(tester);
    },
  );

  testWidgets(
    'review has no API/SSH; secure acquisition precedes enabled connect',
    (tester) async {
      secure.gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminTerminalPage(
            scope: scope,
            host: AdminAssetHostMetadata.parse(fixtures.host()),
            secureWindow: secure,
            onReturn: () {},
          ),
        ),
      );
      await tester.pump();
      expect(reads, 0);
      expect(wires, isEmpty);
      expect(find.text('连接终端'), findsNothing);
      secure.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('连接终端'), findsOneWidget);
      expect(reads, 0);
      await close(tester);
      expect(secure.releases, 1);
    },
  );
  for (final english in [false, true]) {
    testWidgets(
      '320dp 200% review remains scrollable with reachable connect en=$english',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await show(tester, scale: 2, english: english);
        expect(tester.takeException(), isNull);
        final button = find.text(english ? 'Connect terminal' : '连接终端');
        expect(button, findsOneWidget);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(900));
        expect(reads, 0);
        await close(tester);
      },
    );
  }
  testWidgets(
    'close confirmation cancellation keeps session; confirmed return closes once',
    (tester) async {
      await show(tester);
      await connect(tester);
      final wire = wires.single;
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(wire.aborts, 0);
      await tester.tap(find.text('继续会话'));
      await tester.pumpAndSettle();
      expect(wire.sent, isEmpty);
      expect(returns, 0);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '断开'));
      await tester.pumpAndSettle();
      expect(wire.sent, [
        {'type': 'close'},
      ]);
      expect(wire.aborts, 1);
      expect(returns, 1);
      await close(tester);
    },
  );
  testWidgets(
    'paste is previewed; cancel sends nothing; confirm preserves exact CRLF once',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'printf owned\r\n中文😀'};
            }
            return null;
          });
      await show(tester);
      await connect(tester);
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      expect(wires.single.sent, isEmpty);
      expect(find.text('printf owned\r\n中文😀'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(wires.single.sent, isEmpty);
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送一次'));
      await tester.pumpAndSettle();
      expect(wires.single.sent, [
        {'type': 'input', 'data': 'printf owned\r\n中文😀'},
      ]);
      await close(tester);
    },
  );
  testWidgets(
    'background closes root paste dialog, clears preview and retires transport',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'owned-private-paste'};
            }
            return null;
          });
      await show(tester);
      await connect(tester);
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('owned-private-paste'), findsNothing);
      expect(wires.single.sent, isEmpty);
      expect(wires.single.aborts, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('重新连接'), findsOneWidget);
      await close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'landscape 200% session retains accessible controls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(780, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, scale: 2);
      await connect(tester);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
