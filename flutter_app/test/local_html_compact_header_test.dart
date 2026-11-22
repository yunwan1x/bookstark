import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'html_notes_save_test.dart' show Server;
import 'html_note_page_test.dart' show Labels;
import 'html_note_page_fake_surface_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  Future<void> mount(
    WidgetTester tester,
    Server server, {
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final c = HtmlEditorController(server.repo, await server.baseline());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: HtmlNotePage(
          controller: c,
          labels: Labels(),
          local: true,
          localInteractiveAvailable: true,
          english: true,
          fullPreviewBuilder: (_, source) =>
              const Center(child: Text('Local interactive body')),
          sourceSurfaceBuilder: fakeHtmlSourceSurface(FakeHtmlSurfaceControl()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local preview moves saved state into app bar and More opens original source editor',
    (tester) async {
      final server = Server();
      await mount(tester, server);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Saved')),
        findsOneWidget,
      );
      expect(find.text('Local space'), findsOneWidget);
      expect(
        find.text(
          'Saved on this device. Lightweight preview does not run scripts.',
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit source'));
      await tester.pumpAndSettle();
      expect(find.byType(FakeHtmlSourceSurface), findsOneWidget);
      expect(find.byKey(const ValueKey('html-title')), findsOneWidget);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      server.client.close();
    },
  );
  testWidgets(
    'local compact header and interactive mode stay readable at320dp doubled text',
    (tester) async {
      final server = Server();
      await mount(tester, server, small: true);
      final interactive = find.text('Interactive preview');
      await tester.ensureVisible(interactive);
      await tester.tap(interactive);
      await tester.pumpAndSettle();
      expect(find.text('Local interactive body'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      server.client.close();
    },
  );
}
