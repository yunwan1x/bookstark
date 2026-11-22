import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/features/complex_editors/article_metadata_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'metadata preserves comma labels, rejects duplicate and oversized Unicode without truncation',
    (tester) async {
      ArticleMetadata? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ArticleMetadata>(
                    context: context,
                    builder: (_) => ArticleMetadataDialog(
                      title: 'Original',
                      labels: const ['a,b', 'reading'],
                      document: ComplexEditorDocument.parse(
                        ComplexEditorKind.markdown,
                        '# source',
                      ),
                      english: true,
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
      final title = find.byType(TextField).first;
      final label = find.byType(TextField).last;
      final oversized = List.filled(60, '😀').join();
      await tester.enterText(title, oversized);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.widget<TextField>(title).controller!.text, oversized);
      expect(
        find.text('Enter a valid title and shorten oversized title or labels.'),
        findsOneWidget,
      );
      await tester.enterText(title, 'Revised');
      await tester.enterText(label, 'a,b');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(
        find.text(
          'Labels must be unique and within the size and count limits.',
        ),
        findsOneWidget,
      );
      await tester.enterText(label, 'new,label');
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result!.title, 'Revised');
      expect(result!.labels, ['a,b', 'reading', 'new,label']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('label edits preserve the exact existing title', (tester) async {
    ArticleMetadata? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<ArticleMetadata>(
                  context: context,
                  builder: (_) => ArticleMetadataDialog(
                    title: ' Original ',
                    labels: const [],
                    document: ComplexEditorDocument.parse(
                      ComplexEditorKind.markdown,
                      '# source',
                    ),
                    english: true,
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
    await tester.enterText(find.byType(TextField).last, 'comma,label');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.title, ' Original ');
    expect(result!.labels, ['comma,label']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320dp large text with keyboard keeps metadata actions reachable',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ArticleMetadataDialog(
                    title: 'Long readable article title',
                    labels: const ['comma,label', 'reading plan'],
                    document: ComplexEditorDocument.parse(
                      ComplexEditorKind.markdown,
                      '# source',
                    ),
                    english: true,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleMetadataDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
