import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_markdown_resources.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LocalAttachments files;
  late _HeldResources resources;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  final fileID = List.filled(32, 'a').join();
  String? lease;
  MethodChannel? channel;
  setUp(() async {
    files = LocalAttachments(Directory('/unused-local-channel-fixture'));
    resources = _HeldResources(files, png);
    lease = null;
    channel = null;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      if (call.method == 'openLocal') lease = call.arguments['lease'] as String;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map?;
      if (call.method == 'create') {
        expect(args!['viewType'], 'bookstark/local_markdown_view');
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        expect(params.keys.toSet(), {'lease'});
        expect(params['lease'], lease);
        channel = MethodChannel('bookstark/local_markdown_view/${args['id']}');
        messenger.setMockMethodCallHandler(channel!, (_) async => null);
        return 99;
      }
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ComplexEditorBrowser(
              document: ComplexEditorDocument.parse(
                ComplexEditorKind.markdown,
                '# Local fixture',
              ),
              localImageAttachments: files,
              localResourceFactory: (_) => resources,
            ),
          ),
        ),
      ),
    );
    for (var n = 0; n < 16; n++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(channel, isNotNull);
  }

  Future<Object?> request(String url, {String? requestLease}) {
    final result = Completer<Object?>();
    const codec = StandardMethodCodec();
    unawaited(
      messenger.handlePlatformMessage(
        channel!.name,
        codec.encodeMethodCall(
          MethodCall('localImageResource', {
            'lease': requestLease ?? lease,
            'url': url,
          }),
        ),
        (data) {
          try {
            result.complete(data == null ? null : codec.decodeEnvelope(data));
          } catch (error, stack) {
            result.completeError(error, stack);
          }
        },
      ),
    );
    return result.future;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await HtmlBrowserSession.closeActive();
    await tester.pump();
  }

  testWidgets(
    'local image factory receives only lease and rejects foreign lease/network input',
    (tester) async {
      await mount(tester);
      final url = 'bookstark-attachment:///$fileID/fixture.png';
      expect(await request(url, requestLease: 'old-lease'), isNull);
      expect(resources.reads, 0);
      final value = await request(url) as Map;
      expect(value['mime'], 'image/png');
      expect(value['bytes'], png);
      expect(resources.reads, 1);
      expect(await request('https://example.test/account-image'), isNull);
      expect(resources.reads, 1);
      await close(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('late image result cannot leave a retired local view', (
    tester,
  ) async {
    resources.hold = Completer<Uint8List>();
    await mount(tester);
    final pending = request('bookstark-attachment:///$fileID/fixture.png');
    for (var n = 0; n < 20 && !resources.started.isCompleted; n++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(resources.started.isCompleted, isTrue);
    await close(tester);
    resources.hold!.complete(png);
    var returned = false;
    Object? response;
    unawaited(
      pending.then((value) {
        response = value;
        returned = true;
      }),
    );
    for (var n = 0; n < 20 && !returned; n++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(returned, isTrue);
    expect(response, isNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

class _HeldResources extends LocalMarkdownResources {
  _HeldResources(super.attachments, this.bytes);
  final Uint8List bytes;
  Completer<Uint8List>? hold;
  final started = Completer<void>();
  int reads = 0;
  @override
  Future<LocalMarkdownImage> read(Uri uri) async {
    LocalMarkdownResources.identity(uri);
    reads++;
    if (!started.isCompleted) started.complete();
    final data = hold == null ? bytes : await hold!.future;
    return LocalMarkdownImage(data, 'image/png', 1);
  }
}
