import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_asset_private_key_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(
    WidgetTester tester,
    ValueChanged<String> apply, {
    VoidCallback? cancel,
    bool english = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetPrivateKeyPage(
          onApply: apply,
          onReturn: cancel ?? () {},
          english: english,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'real multiline editing preserves CR LF Unicode and spaces on explicit apply',
    (tester) async {
      String? result;
      await open(tester, (value) {
        result = value;
      });
      const input = ' owned synthetic first\r\n第二行\n尾部 ';
      final field = find.byKey(const ValueKey('asset-private-key-input'));
      await tester.enterText(field, input);
      await tester.scrollUntilVisible(
        find.text('使用此私钥'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用此私钥'));
      await tester.pump();
      expect(result, input);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls.map((c) => c.method), ['acquire', 'release']);
    },
  );
  testWidgets(
    'background clears secret and requires reentry instead of implicit keep',
    (tester) async {
      var applies = 0;
      await open(tester, (_) {
        applies++;
      });
      final field = find.byKey(const ValueKey('asset-private-key-input'));
      await tester.enterText(field, 'owned transient secret');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('使用此私钥'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用此私钥'));
      await tester.pumpAndSettle();
      expect(applies, 0);
      expect(find.text('请输入完整私钥。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('cancel clears controller and never applies', (tester) async {
    var applies = 0, cancels = 0;
    await open(
      tester,
      (_) {
        applies++;
      },
      cancel: () {
        cancels++;
      },
    );
    final field = find.byKey(const ValueKey('asset-private-key-input'));
    await tester.enterText(field, 'owned transient secret');
    await tester.scrollUntilVisible(
      find.text('取消'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancels, 1);
    expect(applies, 0);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('pending secure-window acquisition exposes no secret input', (
    tester,
  ) async {
    final gate = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'acquire' ? gate.future : true;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetPrivateKeyPage(onApply: (_) {}, onReturn: () {}),
      ),
    );
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['acquire', 'release']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('secure-window refusal blocks secret entry', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method != 'acquire',
    );
    await open(tester, (_) {});
    expect(find.byType(TextField), findsNothing);
    expect(find.text('无法启用安全窗口，不能输入私钥。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('English 320dp at 200 percent is scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
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
        home: AdminAssetPrivateKeyPage(
          english: true,
          onApply: (_) {},
          onReturn: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Use this private key'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
