import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_html_resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/public_shares/public_html_browser_preview.dart';

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
        expect(params.keys.toSet(), {'lease', 'source', 'server', 'english'});
        final channel = MethodChannel('bookstark/public_html_preview/$id');
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
    PublicHtmlResources Function(Uri)? resourceFactory,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: PublicHtmlBrowserPreview(
              source: '<p>public fixture</p>',
              server: Uri.parse('https://example.test'),
              resourceFactory:
                  resourceFactory ??
                  (server) => PublicHtmlResources(
                    server,
                    transport: MockClient(
                      (_) async => http.Response(
                        'body{}',
                        200,
                        headers: {'content-type': 'text/css'},
                      ),
                    ),
                  ),
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
        .lastWhere((call) => call.method == 'openPublic')
        .arguments['lease'];
    final codec = const StandardMethodCodec();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'bookstark/public_html_preview/$id',
      codec.encodeMethodCall(
        MethodCall('externalLink', {'lease': lease, 'url': uri}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Completer<dynamic> resource(String url, {String? lease}) {
    final reply = Completer<dynamic>();
    final current = sessionCalls
        .lastWhere((call) => call.method == 'openPublic')
        .arguments['lease'];
    const codec = StandardMethodCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'bookstark/public_html_preview/$id',
          codec.encodeMethodCall(
            MethodCall('resource', {'lease': lease ?? current, 'url': url}),
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
    'public resource channel checks lease and scope before returning anonymous bytes',
    (tester) async {
      var calls = 0, sentCredentials = false;
      await mount(
        tester,
        resourceFactory: (server) => PublicHtmlResources(
          server,
          transport: MockClient((request) async {
            calls++;
            sentCredentials =
                request.headers.containsKey('cookie') ||
                request.headers.containsKey('authorization') ||
                request.headers.containsKey('x-csrf-token');
            return http.Response(
              'body{}',
              200,
              headers: {'content-type': 'text/css'},
            );
          }),
        ),
      );
      expect((sessionCalls.single.arguments as Map).keys.toSet(), {'lease'});
      final stale = resource(
        'https://example.test/static/a.css',
        lease: 'wrong',
      );
      await tester.pumpAndSettle();
      expect(await stale.future, isNull);
      expect(calls, 0);
      final approved = resource('https://example.test/static/a.css');
      await tester.pumpAndSettle();
      final value = await approved.future as Map;
      expect(value['mime'], 'text/css');
      expect(calls, 1);
      expect(sentCredentials, isFalse);
      final denied = resource('https://example.test/api/profile');
      await tester.pumpAndSettle();
      expect(await denied.future, isNull);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'public background drops an in-flight native resource reply instead of publishing late bytes',
    (tester) async {
      final response = Completer<http.StreamedResponse>();
      await mount(
        tester,
        resourceFactory: (server) => PublicHtmlResources(
          server,
          transport: MockClient.streaming((_, _) => response.future),
        ),
      );
      final pending = resource('https://example.test/static/a.css');
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      await drainSessions(tester);
      response.complete(
        http.StreamedResponse(
          Stream.value([1, 2, 3]),
          200,
          headers: {'content-type': 'text/css'},
        ),
      );
      await tester.pumpAndSettle();
      expect(await pending.future, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PlatformViewLink), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
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
          sessionCalls.where((call) => call.method == 'openPublic'),
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
        sessionCalls.where((call) => call.method == 'openPublic'),
        hasLength(1),
      );
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(
        sessionCalls.where((call) => call.method == 'openPublic'),
        hasLength(2),
      );
      expect(
        sessionCalls
            .lastWhere((call) => call.method == 'openPublic')
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
            if (call.method == 'openPublic') {
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
              child: PublicHtmlBrowserPreview(
                source: '<p>opening fixture</p>',
                server: Uri.parse('https://example.test'),
                resourceFactory: (server) => PublicHtmlResources(
                  server,
                  transport: MockClient(
                    (_) async => http.Response(
                      'body{}',
                      200,
                      headers: {'content-type': 'text/css'},
                    ),
                  ),
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
        sessionCalls.where((call) => call.method == 'openPublic'),
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
        sessionCalls.where((call) => call.method == 'openPublic'),
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
