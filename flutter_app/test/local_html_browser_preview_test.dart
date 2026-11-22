import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_html_preview_document.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/html/local_html_browser_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sessionCalls = <MethodCall>[];
  final viewChannels = <MethodChannel>[];
  int? id;
  setUp(() {
    sessionCalls.clear();
    viewChannels.clear();
    id = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      sessionCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map?;
      if (call.method == 'create') {
        id = args!['id'] as int;
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        expect(params.keys.toSet(), {
          'lease',
          'source',
          'resources',
          'english',
          'scriptsEnabled',
          'dynamicRaster',
        });
        final channel = MethodChannel('bookstark/local_html_preview/$id');
        viewChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        return 99;
      }
      if (call.method == 'resize') {
        return {'width': args!['width'], 'height': args['height']};
      }
      return null;
    });
  });
  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in viewChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  Future<void> drainSessions(WidgetTester tester) async {
    var completed = false;
    HtmlBrowserSession.closeActive().then((_) => completed = true);
    for (var i = 0; i < 30 && !completed; i++) {
      await tester.pump();
    }
    expect(
      completed,
      isTrue,
      reason: 'Wait for the close result before removing the native mock',
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    OwnedPreviewController? controller,
    String source = '<p>local fixture</p>',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: LocalHtmlBrowserPreview(
              document: LocalHtmlPreviewDocument(source, []),
              retirementController: controller,
            ),
          ),
        ),
      ),
    );
    try {
      await tester.pumpAndSettle();
    } catch (_) {
      debugPrint(
        'Preview mount diagnostics: methods=${sessionCalls.map((call) => call.method).toList()}, viewCreated=${id != null}, nativeChannels=${viewChannels.length}',
      );
      rethrow;
    }
    expect(id, isNotNull);
  }

  Future<void> link(WidgetTester tester, String uri) async {
    final lease = sessionCalls
        .lastWhere((call) => call.method == 'openLocal')
        .arguments['lease'];
    final codec = const StandardMethodCodec();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'bookstark/local_html_preview/$id',
      codec.encodeMethodCall(
        MethodCall('externalLink', {'lease': lease, 'url': uri}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountRaster(
    WidgetTester tester, {
    required Future<LocalHtmlRasterResponse?> Function(String) loader,
    required bool Function() current,
    bool scripts = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: LocalHtmlBrowserPreview(
              document: LocalHtmlPreviewDocument(
                '<img src="/upload-files/p.png">',
                const [],
                scriptsEnabled: scripts,
              ),
              rasterLoader: loader,
              rasterScopeKey: 'owned-generation/source/note/revision',
              isRasterCurrent: current,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Completer<dynamic> raster(String url, {String? lease}) {
    final reply = Completer<dynamic>();
    final current = sessionCalls
        .lastWhere((call) => call.method == 'openLocal')
        .arguments['lease'];
    const codec = StandardMethodCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'bookstark/local_html_preview/$id',
          codec.encodeMethodCall(
            MethodCall('raster', {'lease': lease ?? current, 'url': url}),
          ),
          (data) {
            try {
              reply.complete(codec.decodeEnvelope(data!));
            } catch (error, stack) {
              reply.completeError(error, stack);
            }
          },
        );
    return reply;
  }

  testWidgets(
    'owned retirement waits native close and cannot reload the old body',
    (tester) async {
      final controller = OwnedPreviewController(), gate = Completer<void>();
      await mount(tester, controller: controller);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        sessionCalls.add(call);
        if (call.method == 'close') await gate.future;
        return null;
      });
      var done = false;
      final closed = controller.retire()..then((_) => done = true);
      await tester.pumpAndSettle();
      expect(done, isFalse);
      expect(controller.retired, isTrue);
      expect(find.text('重新加载'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      await closed;
      expect(done, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      controller.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('retiring old owned preview cannot close its successor lease', (
    tester,
  ) async {
    final controller = OwnedPreviewController();
    await mount(tester, controller: controller);
    final successor = await HtmlBrowserSession.openLocal(retire: () async {});
    expect(controller.retired, isTrue);
    await controller.retire();
    expect(
      sessionCalls.where(
        (c) => c.method == 'close' && c.arguments['lease'] == successor.lease,
      ),
      isEmpty,
    );
    await successor.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await drainSessions(tester);
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets(
    'owned close during native opening waits and prevents late platform creation',
    (tester) async {
      final controller = OwnedPreviewController(),
          entered = Completer<void>(),
          release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
            sessionCalls.add(call);
            if (call.method == 'openLocal') {
              entered.complete();
              await release.future;
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalHtmlBrowserPreview(
              document: LocalHtmlPreviewDocument('<p>pending</p>', []),
              retirementController: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(entered.isCompleted, isTrue);
      var done = false;
      final closed = controller.retire()..then((_) => done = true);
      await tester.pump();
      expect(done, isFalse);
      expect(id, isNull);
      release.complete();
      await tester.pumpAndSettle();
      await closed;
      expect(done, isTrue);
      expect(id, isNull);
      expect(sessionCalls.where((c) => c.method == 'close'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      controller.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'new controller creates fresh preview while old controller remains retired',
    (tester) async {
      final first = OwnedPreviewController(), second = OwnedPreviewController();
      await mount(tester, controller: first);
      await mount(tester, controller: second);
      expect(first.retired, isTrue);
      expect(second.retired, isFalse);
      expect(sessionCalls.where((c) => c.method == 'openLocal'), hasLength(2));
      final current = sessionCalls
          .lastWhere((c) => c.method == 'openLocal')
          .arguments['lease'];
      await first.retire();
      expect(
        sessionCalls.where(
          (c) => c.method == 'close' && c.arguments['lease'] == current,
        ),
        isEmpty,
      );
      await second.retire();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      first.dispose();
      second.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'changed controlled body retires instead of silently reusing its lease',
    (tester) async {
      final controller = OwnedPreviewController();
      await mount(tester, controller: controller);
      await mount(tester, controller: controller, source: '<p>replacement</p>');
      expect(controller.retired, isTrue);
      expect(sessionCalls.where((c) => c.method == 'openLocal'), hasLength(1));
      expect(find.byType(PlatformViewLink), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      controller.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'passive raster callback requires current lease and local upload route',
    (tester) async {
      var reads = 0;
      await mountRaster(
        tester,
        current: () => true,
        loader: (_) async {
          reads++;
          return LocalHtmlRasterResponse(
            mime: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          );
        },
      );
      expect(id, isNotNull);
      for (final request in [
        raster('/upload-files/p.png', lease: 'wrong'),
        raster('https://foreign.test/upload-files/p.png'),
        raster('/static/script.js'),
      ]) {
        await tester.pumpAndSettle();
        expect(await request.future, isNull);
      }
      expect(reads, 0);
      final accepted = raster('/upload-files/p.png');
      await tester.pumpAndSettle();
      expect((await accepted.future as Map)['mime'], 'image/png');
      expect(reads, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('content closing while raster is pending drops the result', (
    tester,
  ) async {
    var current = true;
    final response = Completer<LocalHtmlRasterResponse?>();
    await mountRaster(
      tester,
      current: () => current,
      loader: (_) => response.future,
    );
    final pending = raster('/upload-files/p.png');
    await tester.pump();
    current = false;
    response.complete(
      LocalHtmlRasterResponse(
        mime: 'image/png',
        bytes: Uint8List.fromList([1]),
      ),
    );
    await tester.pumpAndSettle();
    expect(await pending.future, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await drainSessions(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('dynamic raster never opens a script-enabled native view', (
    tester,
  ) async {
    await mountRaster(
      tester,
      current: () => true,
      scripts: true,
      loader: (_) async => null,
    );
    expect(id, isNull);
    expect(sessionCalls.where((call) => call.method == 'openLocal'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await drainSessions(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets(
    'external link cancellation leaves local preview active and file URLs are ignored',
    (tester) async {
      await mount(tester);
      await link(tester, 'file:///private/ignored');
      expect(find.byType(AlertDialog), findsNothing);
      await link(tester, 'https://example.org/path');
      expect(find.text('打开外部链接？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sessionCalls.where((call) => call.method == 'close'), isEmpty);
      expect(find.byType(PlatformViewLink), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(
        sessionCalls.where((call) => call.method == 'close'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'confirmed external launch retires before browser even without lifecycle events',
    (tester) async {
      var launched = false, closedBeforeLaunch = false;
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      const linuxLauncher = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.url_launcher_linux.UrlLauncherApi.launchUrl',
        StandardMessageCodec(),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      void recordLaunch() {
        closedBeforeLaunch =
            sessionCalls.where((call) => call.method == 'close').length == 1;
        launched = true;
      }

      messenger.setMockMethodCallHandler(launcher, (call) async {
        recordLaunch();
        return true;
      });
      messenger.setMockDecodedMessageHandler<Object?>(linuxLauncher, (
        message,
      ) async {
        recordLaunch();
        return <Object?>[null];
      });
      try {
        await mount(tester);
        await link(tester, 'https://example.org/confirmed');
        await tester.tap(find.text('打开浏览器'));
        await tester.pumpAndSettle();
        expect(launched, isTrue);
        expect(
          closedBeforeLaunch,
          isTrue,
          reason:
              'Retire before handoff without waiting for lifecycle delivery',
        );
        expect(find.byType(PlatformViewLink), findsNothing);
        expect(find.text('交互预览已关闭或暂不可用。'), findsOneWidget);
        await tester.tap(find.text('重新加载'));
        await tester.pumpAndSettle();
        expect(
          sessionCalls.where((call) => call.method == 'openLocal'),
          hasLength(2),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await drainSessions(tester);
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(launcher, null);
        messenger.setMockDecodedMessageHandler<Object?>(linuxLauncher, null);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'background retirement stops runtime and resuming requires explicit reload with a fresh lease',
    (tester) async {
      await mount(tester);
      final first = sessionCalls.single.arguments['lease'];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(
        sessionCalls.where((call) => call.method == 'close'),
        hasLength(1),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PlatformViewLink), findsNothing);
      expect(
        sessionCalls.where((call) => call.method == 'openLocal'),
        hasLength(1),
      );
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(
        sessionCalls.where((call) => call.method == 'openLocal'),
        hasLength(2),
      );
      expect(
        sessionCalls
            .lastWhere((call) => call.method == 'openLocal')
            .arguments['lease'],
        isNot(first),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'background during native opening cancels that lease and requires explicit reload',
    (tester) async {
      final entered = Completer<void>(), release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
            sessionCalls.add(call);
            if (call.method == 'openLocal') {
              if (!entered.isCompleted) entered.complete();
              await release.future;
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: LocalHtmlBrowserPreview(
                document: LocalHtmlPreviewDocument(
                  '<p>opening fixture</p>',
                  [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(entered.isCompleted, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      release.complete();
      await drainSessions(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PlatformViewLink), findsNothing);
      expect(
        sessionCalls.where((call) => call.method == 'openLocal'),
        hasLength(1),
      );
      expect(
        sessionCalls.where((call) => call.method == 'close'),
        hasLength(1),
      );
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformViewLink), findsOneWidget);
      expect(
        sessionCalls.where((call) => call.method == 'openLocal'),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
