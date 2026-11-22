import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'html_notes_save_test.dart' show Server;
import 'html_note_page_test.dart' show open, source;
import 'html_note_page_fake_surface_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  testWidgets(
    'clean Back freezes title during gated vault flush and pops without applying late input',
    (tester) async {
      final s = Server();
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      final vault = HtmlRecoveryVault(
        server: Uri.parse('https://books.example'),
        memberId: 3,
        collection: 'note',
        readValue: (_) async => null,
        writeValue: (_, _) async {},
        deleteValue: (_) async {
          if (!deleteStarted.isCompleted) deleteStarted.complete();
          await releaseDelete.future;
        },
      );
      final c = await open(tester, s, recovery: vault);
      final originalTitle = c.draft.title;
      await source(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.runAsync(
        () => deleteStarted.future.timeout(const Duration(seconds: 5)),
      );
      await tester.pump();
      final titleFinder = find.byKey(const ValueKey('html-title'));
      expect(tester.widget<TextField>(titleFinder).readOnly, isTrue);
      await tester.enterText(titleFinder, 'Rejected during leave');
      await tester.pump();
      expect(c.draft.title, originalTitle);
      expect(
        tester.widget<TextField>(titleFinder).controller!.text,
        originalTitle,
      );
      releaseDelete.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open HTML'), findsOneWidget);
      expect(s.row['blog_title'], originalTitle);
      expect(s.contentWrites, 0);
      s.client.close();
    },
  );

  testWidgets(
    'cancel dirty Back releases leave gate and preserves editable draft',
    (tester) async {
      final s = Server();
      final c = await open(tester, s);
      await source(tester);
      await tester.enterText(
        find.byKey(const ValueKey('html-title')),
        'Keep this draft',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(c.draft.title, 'Keep this draft');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('html-title')),
      );
      expect(field.readOnly, isFalse);
      expect(field.controller!.text, 'Keep this draft');
      await tester.pumpWidget(const SizedBox.shrink());
      s.client.close();
    },
  );
}
