import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'package:bookstark_flutter/features/html/html_version_view.dart';
import 'package:bookstark_flutter/features/html/html_source_editor.dart';
import 'package:bookstark_flutter/features/html/html_recovery_review.dart';
import 'package:bookstark_flutter/features/html/open_html_note.dart';
import 'html_notes_save_test.dart' show Server;
import 'html_editor_recovery_test.dart' show Memory;
import 'html_note_page_fake_surface_test_support.dart';

class Host {
  final navigator = GlobalKey<NavigatorState>();
  int browsers = 0;
  final errors = <Object>[];
  final surface = FakeHtmlSurfaceControl();
  Future<void> mount(
    WidgetTester tester,
    Server server,
    Memory memory, {
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await openHtmlNote(
                    context,
                    client: server.client,
                    id: 7,
                    collection: 'note',
                    english: true,
                    recoveryVault: memory.vault(),
                    fullPreviewBuilder: (_, source) {
                      browsers++;
                      return const Text('Full browser fixture');
                    },
                    sourceSurfaceBuilder: fakeHtmlSourceSurface(surface),
                    readOnlySourceSurfaceBuilder: fakeReadOnlyHtmlCodeSurface(),
                  );
                } catch (error) {
                  errors.add(error);
                }
              },
              child: const Text('Open HTML'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open HTML'));
    bool ready() =>
        errors.isNotEmpty ||
        find.byType(HtmlNotePage).evaluate().isNotEmpty ||
        find.byType(HtmlRecoveryReviewPage).evaluate().isNotEmpty ||
        find.byType(AlertDialog).evaluate().isNotEmpty;
    // The initial bounded HTTP/body stream has real event-loop work as well as
    // frames. pumpAndSettle alone can stop before the first route is mounted.
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(
      ready(),
      isTrue,
      reason:
          'Actual HTML opener must mount editor/review/dialog or report its error',
    );
    if (errors.isNotEmpty) {
      debugPrint('html_recovery_fixture_open_error:${errors.last.runtimeType}');
    }
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester, Server s) async {
    await tester.pumpWidget(const SizedBox());
    s.repo.dispose();
    s.client.close();
  }
}

Future<void> htmlReady(
  WidgetTester tester,
  Host host,
  bool Function() ready, {
  bool reportedError = false,
}) async {
  for (var i = 0; i < 100 && !ready() && host.errors.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  if (!reportedError) expect(host.errors, isEmpty);
  expect(ready(), isTrue, reason: 'Real restored HTML route must be ready');
  await tester.pumpAndSettle();
}

Future<void> source(WidgetTester tester, {bool pageSurface = true}) async {
  expect(
    find.byType(pageSurface ? HtmlNotePage : HtmlVersionViewPage),
    findsOneWidget,
  );
  expect(find.text('Source'), findsOneWidget);
  await tester.ensureVisible(find.text('Source'));
  await tester.tap(find.text('Source'));
  if (pageSurface) {
    for (
      var i = 0;
      i < 40 && find.byType(FakeHtmlSourceSurface).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }
  await tester.pumpAndSettle();
}

Future<void> unlock(WidgetTester tester, Host host) async {
  await tester.enterText(
    find.byKey(const Key('note-password')),
    ' raw password ',
  );
  await tester.tap(find.text('Unlock'));
  await htmlReady(tester, host,
    () => find.byType(HtmlRecoveryReviewPage).evaluate().isNotEmpty);

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  testWidgets(
    'duplicate opener cannot overwrite draft and ownership ends on actual disposal',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      await h.mount(tester, s, m);
      await h.open(tester);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Draft owned by first page',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final record = Map<String, String>.from(m.values);
      final duplicate = openHtmlNote(
        h.navigator.currentContext!,
        client: s.client,
        id: 7,
        collection: 'note',
        english: true,
        recoveryVault: m.vault(),
      );
      final duplicateOpened = await duplicate;
      await tester.pumpAndSettle();
      expect(duplicateOpened, false);
      expect(
        find.text('This HTML note is already open. Return to its editor.'),
        findsOneWidget,
      );
      expect(m.values, record);
      expect(find.byType(HtmlNotePage), findsOneWidget);
      expect(s.contentWrites, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await h.mount(tester, s, m);
      await h.open(tester);
      expect(find.text('Unsaved HTML draft found'), findsOneWidget);
      await tester.tap(find.text('Restore draft'));
      await htmlReady(
        tester,
        h,
        () => find.byType(HtmlNotePage).evaluate().isNotEmpty,
      );
      expect(find.byType(HtmlNotePage), findsOneWidget);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );

  testWidgets(
    'conflict snapshot reveals complete server source and literal labels without writes',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      final baseline = await s.baseline();
      await m.vault().write(
        HtmlRecoveryRecord.capture(baseline, s.edit(), pending: false),
      );
      s.source =
          '<p>${List.filled(700, 'x').join()}</p>\r\n<!-- server difference beyond excerpt -->';
      s.labels = ['one,literal,label'];
      s.row['version'] = 8;
      await h.mount(tester, s, m);
      await h.open(tester);
      await tester.tap(find.text('Restore draft'));
      await htmlReady(
        tester,
        h,
        () => find.text('Server content changed').evaluate().isNotEmpty,
      );
      expect(find.text('Server content changed'), findsOneWidget);
      await tester.ensureVisible(find.text('Server version'));
      await tester.tap(find.text('Server version'));
      await tester.pumpAndSettle();
      expect(find.byType(HtmlVersionViewPage), findsOneWidget);
      expect(find.text('one,literal,label'), findsOneWidget);
      expect(find.text('Read only'), findsOneWidget);
      await source(tester, pageSurface: false);
      final editor = tester.widget<HtmlSourceEditor>(
        find.byType(HtmlSourceEditor),
      );
      expect(editor.readOnly, isTrue);
      expect(editor.source, s.source);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Server content changed'), findsOneWidget);
      expect((await m.vault().read(7))!.pending, false);
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect(h.browsers, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );

  for (final dismissWithBack in [false, true]) {
    testWidgets(
      'leave sheet dismissal checkpoints immediate edits (back: $dismissWithBack)',
      (tester) async {
        final s = Server(), m = Memory(), h = Host();
        await h.mount(tester, s, m);
        await h.open(tester);
        await source(tester);
        await tester.enterText(
          find.byKey(const ValueKey('html-title')),
          'Immediate draft before leave',
        );
        await tester.pump();
        expect(m.values, isEmpty);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          (await m.vault().read(7))!.edit!.title,
          'Immediate draft before leave',
        );
        if (dismissWithBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Keep editing'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(HtmlNotePage), findsOneWidget);
        expect(
          (await m.vault().read(7))!.edit!.title,
          'Immediate draft before leave',
        );
        expect(s.contentWrites, 0);
        expect(s.labelWrites, 0);
        expect(h.errors, isEmpty);
        await h.close(tester, s);
      },
    );
  }

  testWidgets(
    'real HTML opener keeps changed draft on leave and restores it without server writes',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      await h.mount(tester, s, m);
      await h.open(tester);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Draft kept across pages',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep draft and leave'));
      await tester.pumpAndSettle();
      expect((await m.vault().read(7))!.edit!.title, 'Draft kept across pages');
      await h.open(tester);
      expect(find.text('Unsaved HTML draft found'), findsOneWidget);
      await tester.tap(find.text('Restore draft'));
      await htmlReady(
        tester,
        h,
        () => find.byType(HtmlNotePage).evaluate().isNotEmpty,
      );
      await source(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('html-title')))
            .controller!
            .text,
        'Draft kept across pages',
      );
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'undo to clean then immediate back removes prior draft instead of resurrecting it',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      final baseline = await s.baseline();
      await h.mount(tester, s, m);
      await h.open(tester);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Temporary title',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(await m.vault().read(7), isNotNull);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        baseline.metadata.title,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(m.values, isEmpty);
      expect(s.contentWrites, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'restored unknown commit never instantiates script browser before read-only verification and label recovery',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      c.dispose();
      expect(s.contentWrites, 1);
      await h.mount(tester, s, m);
      await h.open(tester);
      expect(find.text('Content save result unknown'), findsOneWidget);
      expect(h.browsers, 0);
      await tester.ensureVisible(find.text('Verify server'));
      await tester.tap(find.text('Verify server'));
      await htmlReady(tester, h,
        () => find.text('Continue labels').evaluate().isNotEmpty);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      expect(h.browsers, 0);
      await tester.ensureVisible(find.text('Continue labels'));
      await tester.tap(find.text('Continue labels'));
      await htmlReady(tester, h, () => h.browsers > 0 && m.values.isEmpty);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      expect(m.values, isEmpty);
      expect(h.browsers, greaterThan(0));
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'protected pending review keeps digest on cancel and requires explicit adoption without replay',
    (tester) async {
      final s = Server(protected: true), m = Memory(), h = Host();
      final baseline = await s.baseline();
      await m.vault().write(
        HtmlRecoveryRecord.capture(baseline, s.edit(), pending: true),
      );
      await h.mount(tester, s, m);
      await h.open(tester);
      await unlock(tester, h);
      expect(find.byType(HtmlRecoveryReviewPage), findsOneWidget);
      expect(h.browsers, 0);
      await tester.tap(find.text('Adopt current version and start editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep reviewing'));
      await tester.pumpAndSettle();
      expect(m.values, isNotEmpty);
      await tester.tap(find.text('Adopt current version and start editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adopt current version'));
      await htmlReady(tester, h,
        () => find.byType(HtmlNotePage).evaluate().isNotEmpty);
      expect(find.byType(HtmlNotePage), findsOneWidget);
      expect(m.values, isEmpty);
      expect(h.browsers, greaterThan(0));
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'server changing after protected review prevents adopting unseen data and retains intent',
    (tester) async {
      final s = Server(protected: true), m = Memory(), h = Host();
      await m.vault().write(
        HtmlRecoveryRecord.capture(await s.baseline(), s.edit(), pending: true),
      );
      await h.mount(tester, s, m);
      await h.open(tester);
      await unlock(tester, h);
      await tester.tap(find.text('Adopt current version and start editing'));
      await tester.pumpAndSettle();
      s.source = '<p>New unseen content</p>';
      s.row['version'] = (s.row['version'] as int) + 1;
      await tester.tap(find.text('Adopt current version'));
      await htmlReady(tester, h, () => h.errors.isNotEmpty,
        reportedError: true);
      expect(find.byType(HtmlNotePage), findsNothing);
      expect(m.values, isNotEmpty);
      expect(h.errors, hasLength(1));
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect(h.browsers, 0);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'English320dp double text protected review stays scrollable and source is read-only',
    (tester) async {
      final s = Server(protected: true), m = Memory(), h = Host();
      await m.vault().write(
        HtmlRecoveryRecord.capture(await s.baseline(), s.edit(), pending: true),
      );
      await h.mount(tester, s, m, small: true);
      await h.open(tester);
      await unlock(tester, h);
      expect(find.byType(HtmlRecoveryReviewPage), findsOneWidget);
      await tester.ensureVisible(find.text('Source'));
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.browsers, 0);
      expect(s.contentWrites, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'corrupt recovery is retained until explicit deletion, cancellation opens no editor',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      await m.vault().write(
        HtmlRecoveryRecord.capture(
          await s.baseline(),
          s.edit(),
          pending: false,
        ),
      );
      m.values[m.values.keys.single] = 'invalid json';
      await h.mount(tester, s, m);
      await h.open(tester);
      expect(find.text('Recovery record could not be read'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(m.values.values.single, 'invalid json');
      expect(find.byType(HtmlNotePage), findsNothing);
      expect(h.browsers, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'failed device checkpoint keeps page and edits until storage retry succeeds',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      await h.mount(tester, s, m);
      await h.open(tester);
      await source(tester);
      m.failWrite = true;
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Keep despite storage failure',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(HtmlNotePage), findsOneWidget);
      expect(
        find.text(
          'The recovery record could not be updated. Retry before leaving.',
        ),
        findsOneWidget,
      );
      expect(s.contentWrites, 0);
      m.failWrite = false;
      await tester.ensureVisible(find.text('Retry device storage'));
      await tester.tap(find.text('Retry device storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep draft and leave'));
      await tester.pumpAndSettle();
      expect(
        (await m.vault().read(7))!.edit!.title,
        'Keep despite storage failure',
      );
      expect(find.byType(HtmlNotePage), findsNothing);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
  testWidgets(
    'pending recovery can leave durably and reopening still forbids automatic replay',
    (tester) async {
      final s = Server(), m = Memory(), h = Host();
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      c.dispose();
      await h.mount(tester, s, m);
      await h.open(tester);
      await tester.ensureVisible(find.text('Keep recovery record and leave'));
      await tester.tap(find.text('Keep recovery record and leave'));
      await tester.pumpAndSettle();
      expect((await m.vault().read(7))!.pending, true);
      expect(find.byType(HtmlNotePage), findsNothing);
      expect(s.contentWrites, 1);
      await h.open(tester);
      expect(find.text('Content save result unknown'), findsOneWidget);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      expect(h.browsers, 0);
      expect(h.errors, isEmpty);
      await h.close(tester, s);
    },
  );
}
