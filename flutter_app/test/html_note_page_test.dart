import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';

import 'html_notes_save_test.dart' show Server;
import 'html_note_page_fake_surface_test_support.dart';

class Labels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [
    'original',
    '读书',
  ];
}

Future<HtmlEditorController> open(
  WidgetTester tester,
  Server s, {
  bool narrow = false,
  FakeHtmlSurfaceControl? surface,
  HtmlRecoveryVault? recovery,
}) async {
  final c = HtmlEditorController(
    s.repo,
    await s.baseline(),
    recovery: recovery,
  );
  final fakeSurface = surface ?? FakeHtmlSurfaceControl();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => HtmlNotePage(
                  controller: c,
                  labels: Labels(),
                  english: true,
                  fullPreviewBuilder: (_, source) => const ColoredBox(
                    color: Colors.white,
                    child: Text('HTML browser fixture'),
                  ),
                  sourceSurfaceBuilder: fakeHtmlSourceSurface(fakeSurface),
                ),
              ),
            ),
            child: const Text('Open HTML'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open HTML'));
  await tester.pumpAndSettle();
  return c;
}

Future<void> source(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Source'));
  await tester.tap(find.text('Source'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('html-title')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  testWidgets(
    'HTML page saves title with the exact source snapshot supplied by the WebView transport',
    (tester) async {
      final s = Server();
      s.source = '<script>window.x="你好";</script>\r\n';
      final original = s.source;
      final c = await open(tester, s);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Updated through page',
      );
      await tester.pump();
      expect(c.canSave, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(s.row['blog_title'], 'Updated through page');
      expect(s.source, original);
      expect(s.labels, ['original']);
      expect(s.contentWrites, 1);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );
  testWidgets(
    'unknown receipt disables resubmit and explicit verify observes server without another PUT',
    (tester) async {
      final s = Server();
      s.loseContent = true;
      final c = await open(tester, s);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Unknown page save',
      );
      await tester.pump();
      expect(c.canSave, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.contentUnknown);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      await tester.ensureVisible(find.text('Verify server'));
      await tester.tap(find.text('Verify server'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.observed);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      expect(
        find.text('Server content verified; some receipts missing'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );
  testWidgets(
    'conflict cards preserve input and require review with zero automatic writes',
    (tester) async {
      final s = Server();
      final c = await open(tester, s);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'My unsaved title',
      );
      s.row['version'] = 10;
      s.source = '<p>Server changed</p>';
      await tester.pump();
      expect(c.canSave, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.conflict);
      expect(find.text('Your changes'), findsOneWidget);
      expect(find.text('Server version'), findsOneWidget);
      expect(c.draft.title, 'My unsaved title');
      expect(s.contentWrites, 0);
      await tester.ensureVisible(find.text('Continue after review'));
      await tester.tap(find.text('Continue after review'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.editing);
      expect(c.draft.title, 'My unsaved title');
      expect(s.contentWrites, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'source save stays disabled until the matching editor generation is ready',
    (tester) async {
      final s = Server();
      final control = FakeHtmlSurfaceControl(autoReady: false);
      final c = await open(tester, s, surface: control);
      await source(tester);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(c.canSave, isFalse);
      expect(s.contentWrites, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'a changed WebView source is checkpointed and saved from the protocol snapshot',
    (tester) async {
      final s = Server();
      final control = FakeHtmlSurfaceControl();
      final c = await open(tester, s, surface: control);
      await source(tester);
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      const changed =
          '<!doctype html><p>changed through fake transport</p>\r\n';
      expect(c.draft.source, changed);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(s.source, changed);
      expect(s.contentWrites, 1);
      expect(find.text('Saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'one dirty revision checkpoints once and storage failure waits for explicit retry',
    (tester) async {
      final s = Server();
      final control = FakeHtmlSurfaceControl();
      final failedVault = HtmlRecoveryVault(
        server: Uri.parse('https://books.example'),
        memberId: 3,
        collection: 'note',
        readValue: (_) async => null,
        writeValue: (_, _) async =>
            throw StateError('injected recovery write failure'),
        deleteValue: (_) async {},
      );
      await open(tester, s, surface: control, recovery: failedVault);
      await source(tester);
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(control.snapshotBegins, 1);
      expect(
        find.text('Draft storage failed. Retry before switching.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(control.snapshotBegins, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'pending source generation remains CodeMirror locked instead of preview mode',
    (tester) async {
      final s = Server()..loseContent = true;
      final control = FakeHtmlSurfaceControl();
      final c = await open(tester, s, surface: control);
      await source(tester);
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, HtmlEditorPhase.contentUnknown);
      expect(control.loadedReadOnly, isFalse);
      expect(control.inputLocked, isTrue);
      expect(s.contentWrites, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'discard invalidates coordinator before retiring without a second snapshot',
    (tester) async {
      final s = Server();
      final control = FakeHtmlSurfaceControl();
      await open(tester, s, surface: control);
      await source(tester);
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final beforeLeave = control.snapshotBegins;
      expect(beforeLeave, greaterThan(0));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(control.snapshotBegins, beforeLeave + 1); // leave gate only
      expect(control.retireCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'preview to source reopens a fresh lease after retiring the prior source',
    (tester) async {
      final s = Server();
      final control = FakeHtmlSurfaceControl();
      await open(tester, s, surface: control);
      await source(tester);
      expect(control.sessionOpens, 1);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(control.retireCalls, 1);
      expect(control.sessionOpens, 2);
      expect(control.loadedReadOnly, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );

  testWidgets(
    'English320dp double text keeps WebView source and actions scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = Server();
      await open(tester, s, narrow: true);
      await source(tester);
      expect(find.byKey(const ValueKey('html-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );
}
