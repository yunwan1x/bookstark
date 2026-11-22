import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[], views = <MethodChannel>[];
  int? id;
  final document = ComplexEditorDocument.parse(
    ComplexEditorKind.drawing,
    '{"elements":[]}',
  );
  setUp(() {
    calls.clear();
    views.clear();
    id = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map?;
      if (call.method == 'create') {
        id = args!['id'] as int;
        final channel = MethodChannel('bookstark/complex_editor_view/$id');
        views.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        return 99;
      }
      if (call.method == 'resize') {
        return {'width': args!['width'], 'height': args['height']};
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in views) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  Future<void> mount(
    WidgetTester tester,
    OwnedPreviewController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ComplexEditorBrowser(
              document: document,
              retirementController: controller,
            ),
          ),
        ),
      ),
    );
    for (var n = 0; n < 10; n++) {
      await tester.pump();
    }
    expect(id, isNotNull);
  }

  Future<void> clear(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await HtmlBrowserSession.closeActive();
  }

  testWidgets('complex owner waits native lease close before retiring body', (
    tester,
  ) async {
    final controller = OwnedPreviewController(), gate = Completer<void>();
    await mount(tester, controller);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
          calls.add(call);
          if (call.method == 'close') await gate.future;
          return null;
        });
    var done = false;
    final closed = controller.retire()..then((_) => done = true);
    await tester.pumpAndSettle();
    expect(done, isFalse);
    expect(find.text('重新加载'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    await closed;
    expect(done, isTrue);
    await clear(tester);
    controller.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('complex old owner cannot close a fresh successor', (
    tester,
  ) async {
    final first = OwnedPreviewController(), next = OwnedPreviewController();
    await mount(tester, first);
    await mount(tester, next);
    expect(first.retired, isTrue);
    expect(next.retired, isFalse);
    final lease = calls
        .lastWhere((c) => c.method == 'openLocal')
        .arguments['lease'];
    await first.retire();
    expect(
      calls.where((c) => c.method == 'close' && c.arguments['lease'] == lease),
      isEmpty,
    );
    await next.retire();
    await clear(tester);
    first.dispose();
    next.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('complex dispose retires owner without setState after removal', (
    tester,
  ) async {
    final controller = OwnedPreviewController();
    await mount(tester, controller);
    await clear(tester);
    await controller.retire();
    expect(controller.retired, isTrue);
    controller.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
