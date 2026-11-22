import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'support/markdown_creation_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foreground retirement keeps native view alive until the latest snapshot is captured',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final host = MarkdownCreationHost();
      final owner = OwnedPreviewController();
      final entered = Completer<void>(), gate = Completer<void>();
      MethodChannel? channel;
      String? lease, captured;
      bool disposed = false, finished = false;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        if (call.method == 'openPublic') {
          lease = (call.arguments as Map)['lease'] as String;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        final args = call.arguments as Map?;
        if (call.method == 'create') {
          channel = MethodChannel(
            'bookstark/shared_markdown_view/${args!['id']}',
          );
          messenger.setMockMethodCallHandler(channel!, (call) async {
            if (call.method == 'retire') return null;
            final command = call.arguments as Map;
            final name = command['name'] as String;
            if (disposed && name != 'retire') {
              throw PlatformException(code: 'native_view_gone');
            }
            return host.call(
              name,
              (command['arguments'] as List).cast<Object?>(),
            );
          });
          return 99;
        }
        if (call.method == 'dispose') disposed = true;
        if (call.method == 'resize') {
          return {'width': args!['width'], 'height': args['height']};
        }
        return null;
      });
      Future<void> pump() async {
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await pump();
        await tester.pumpWidget(const SizedBox());
        await pump();
        var closed = false;
        HtmlBrowserSession.closeActive().then((_) => closed = true);
        await pump();
        expect(closed, isTrue);
        owner.dispose();
        messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ComplexEditorBrowser(
                document: ComplexEditorDocument.parse(
                  ComplexEditorKind.markdown,
                  '# Initial',
                ),
                publicServer: Uri.parse('https://example.test'),
                sharedMarkdownEditing: true,
                readOnly: false,
                retirementController: owner,
                onReady: (_) async {},
                onState: (_) {},
                onSaveRequested: () async {},
                onReloadRequested: () async {},
                beforeRetire: (transport) async {
                  entered.complete();
                  await gate.future;
                  final snapshot = await transport.capture();
                  captured = snapshot.document.source;
                  await transport.release(snapshot);
                },
              ),
            ),
          ),
        ),
      );
      await pump();
      final ready = Completer<void>();
      messenger.handlePlatformMessage(
        channel!.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('hostReady', {'lease': lease}),
        ),
        (_) => ready.complete(),
      );
      await pump();
      expect(ready.isCompleted, isTrue);
      expect(host.generation, 1);
      host.source = '# Latest unsaved source';
      final closing = owner.retire().then((_) => finished = true);
      await pump();
      expect(entered.isCompleted, isTrue);
      try {
        expect(
          disposed,
          isFalse,
          reason:
              'A slow snapshot must not lose its native view at the next frame',
        );
      } finally {
        gate.complete();
        await pump();
        await closing;
      }
      expect(finished, isTrue);
      expect(captured, '# Latest unsaved source');
      expect(disposed, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
