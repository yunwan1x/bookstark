import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_article_draft_archive.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_draft_archive_page.dart';

LocalArchivedArticle archive() {
  final namespace = jsonEncode(['local', 'article']);
  final key =
      LocalArticleDraftReceipt.keyPrefix +
      base64Url.encode(utf8.encode(jsonEncode([namespace, 17])));
  return LocalArchivedArticle(
    LocalArticleDraftReceiptScope.parse(key, {'local'}),
    LocalArticleDraftReceipt(
      digest: 'a' * 64,
      disposition: LocalArticleDraftDisposition.skipped,
      ciphertextSHA256: 'b' * 64,
    ),
    ComplexNoteEdit(
      title: 'Old reading plan',
      document: ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        '# old source',
      ),
      labels: const ['old'],
    ),
  );
}

void main() {
  // UI-only tests deliberately use an unavailable browser platform. Actual
  // WebView rendering/accessibility and native close barriers have separate tests.
  testWidgets(
    'old-draft restore requires confirmation and retires the readonly owner before approval',
    (tester) async {
      final value = archive();
      LocalArticleDraftRestoreApproval? result;
      var prepared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<LocalArticleDraftRestoreApproval>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocalArticleDraftArchivePage(
                        archive: value,
                        english: true,
                        prepareRestore: () async {
                          final body = tester.widget<ComplexEditorBrowser>(
                            find.byType(ComplexEditorBrowser),
                          );
                          expect(body.readOnly, isTrue);
                          expect(body.retirementController!.retired, isTrue);
                          prepared++;
                          return LocalArticleDraftRestoreApproval.fromArchive(
                            value,
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final body = tester.widget<ComplexEditorBrowser>(
        find.byType(ComplexEditorBrowser),
      );
      expect(body.readOnly, isTrue);
      expect(body.document.source, '# old source');
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.text('Restore old draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(prepared, 0);
      expect(body.retirementController!.retired, isFalse);
      await tester.tap(find.text('Restore old draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue restore'));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(result!.id, 17);
      expect(result!.digest, value.receipt.digest);
      expect(find.byType(LocalArticleDraftArchivePage), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'space change while confirming cannot prepare an old-draft restore',
    (tester) async {
      var current = true, prepared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalArticleDraftArchivePage(
            archive: archive(),
            english: true,
            isCurrentScope: () => current,
            prepareRestore: () async {
              prepared++;
              return LocalArticleDraftRestoreApproval.fromArchive(archive());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore old draft'));
      await tester.pumpAndSettle();
      current = false;
      await tester.tap(find.text('Continue restore'));
      await tester.pumpAndSettle();
      expect(prepared, 0);
      expect(find.byType(ComplexEditorBrowser), findsNothing);
      expect(find.textContaining('Records are retained'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'unavailable target keeps the archive readonly and return reachable at 320dp 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LocalArticleDraftArchivePage(archive: archive(), english: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Restore old draft'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Return to draft list'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Return to draft list'));
      await tester.pumpAndSettle();
      expect(find.text('Return to draft list').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
