import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_html_resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';

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
        expect(params.keys.toSet(), {'lease', 'server'});
        final channel = MethodChannel('bookstark/public_markdown_view/$id');
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
    void Function(int, int)? onStatus,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ComplexEditorBrowser(
              document: ComplexEditorDocument.parse(
                ComplexEditorKind.markdown,
                '# Public fixture',
              ),
              onPublicResourceStatus: onStatus,
              publicServer: Uri.parse('https://example.test'),
              publicResourceFactory:
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
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
    } catch (_) {
      debugPrint(
        'Preview mount diagnostics: methods=${sessionCalls.map((call) => call.method).toList()}, viewCreated=${id != null}, nativeChannels=${viewChannels.length}',
      );
      rethrow;
    }
    expect(id, isNotNull);
  }

  Completer<dynamic> resource(String url, {String? lease}) {
    final reply = Completer<dynamic>();
    final current = sessionCalls
        .lastWhere((call) => call.method == 'openPublic')
        .arguments['lease'];
    const codec = StandardMethodCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'bookstark/public_markdown_view/$id',
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
      expect(
        (sessionCalls.singleWhere((c) => c.method == 'openPublic').arguments
                as Map)
            .keys
            .toSet(),
        {'lease'},
      );
      final stale = resource(
        'https://example.test/static/a.css',
        lease: 'wrong',
      );
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      expect(await stale.future, isNull);
      expect(calls, 0);
      final approved = resource('https://example.test/static/a.css');
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      final value = await approved.future as Map;
      expect(value['mime'], 'text/css');
      expect(calls, 1);
      expect(sentCredentials, isFalse);
      final denied = resource('https://example.test/api/profile');
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      expect(await denied.future, isNull);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
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
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      await drainSessions(tester);
      response.complete(
        http.StreamedResponse(
          Stream.value([1, 2, 3]),
          200,
          headers: {'content-type': 'text/css'},
        ),
      );
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      expect(await pending.future, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      expect(find.byType(PlatformViewLink), findsNothing);
      await tester.pumpWidget(const SizedBox());
      for (var tick = 0; tick < 12; tick++) {
        await tester.pump();
      }
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'public image failure is lease scoped and reported once without a resource URL',
    (tester) async {
      final failures = <int>[];
      await mount(tester, onStatus: (_, failed) => failures.add(failed));
      final lease = sessionCalls
          .lastWhere((c) => c.method == 'openPublic')
          .arguments['lease'];
      Future<void> report(String value) async {
        const codec = StandardMethodCodec();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'bookstark/public_markdown_view/$id',
          codec.encodeMethodCall(
            MethodCall('publicImageFailure', {'lease': value}),
          ),
          (_) {},
        );
        for (var tick = 0; tick < 12; tick++) {
          await tester.pump();
        }
      }

      await report('stale');
      expect(failures, isEmpty);
      await report(lease as String);
      await report(lease);
      expect(failures, [1]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await drainSessions(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
