import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_asset_secret_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secret_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(
    WidgetTester tester,
    Future<AdminAssetSecretLease> Function() reveal, {
    VoidCallback? hide,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetSecretPage(
          title: '查看凭据',
          details: const [('名称', 'owned credential')],
          onReveal: reveal,
          onHide: hide ?? () {},
          onReturn: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('显示秘密'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示秘密'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('opening is masked and makes no secret read until explicit tap', (
    tester,
  ) async {
    var reads = 0;
    final lease = AdminAssetSecretLease(
      'owned temporary secret',
      () => true,
      (_) {},
    );
    await open(tester, () async {
      reads++;
      return lease;
    });
    expect(reads, 0);
    expect(find.text('owned temporary secret'), findsNothing);
    await reveal(tester);
    expect(reads, 1);
    expect(find.text('owned temporary secret'), findsOneWidget);
    await close(tester);
    expect(lease.value, isNull);
  });
  testWidgets('background hides actual visible content and closes lease', (
    tester,
  ) async {
    final lease = AdminAssetSecretLease(
      'owned temporary secret',
      () => true,
      (_) {},
    );
    await open(tester, () async => lease);
    await reveal(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('owned temporary secret'), findsNothing);
    expect(lease.value, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('asset-revealed-secret')), findsNothing);
    await close(tester);
  });
  testWidgets('60 second expiry hides without repeating reveal', (
    tester,
  ) async {
    var reads = 0;
    final lease = AdminAssetSecretLease(
      'owned temporary secret',
      () => true,
      (_) {},
    );
    await open(tester, () async {
      reads++;
      return lease;
    });
    await reveal(tester);
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(lease.value, isNull);
    expect(reads, 1);
    expect(find.text('owned temporary secret'), findsNothing);
    await close(tester);
  });
  testWidgets(
    'late read after background closes incoming lease instead of showing it',
    (tester) async {
      final result = Completer<AdminAssetSecretLease>();
      await open(tester, () => result.future);
      await tester.scrollUntilVisible(
        find.text('显示秘密'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示秘密'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final lease = AdminAssetSecretLease(
        'owned late secret',
        () => true,
        (_) {},
      );
      result.complete(lease);
      await tester.pump();
      expect(lease.value, isNull);
      expect(find.text('owned late secret'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await close(tester);
    },
  );
  testWidgets('secure window refusal never allows a secret request', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method != 'acquire',
    );
    var reads = 0;
    await open(tester, () async {
      reads++;
      return AdminAssetSecretLease('owned secret', () => true, (_) {});
    });
    await tester.scrollUntilVisible(
      find.text('显示秘密'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '显示秘密'))
          .onPressed,
      isNull,
    );
    expect(reads, 0);
    await close(tester);
  });
}
