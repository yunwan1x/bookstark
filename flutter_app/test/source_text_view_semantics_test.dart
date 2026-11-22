import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';
import 'package:bookstark_flutter/features/complex_editors/source_text_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'decorated chunks expose separate headings and bounded body nodes',
    (tester) async {
      final source = List<String>.generate(
        80,
        (index) => 'chunk-$index ${'😀中' * 1100}',
      ).join('\n');
      final totalChunks = SourceChunks(source).length;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SourceTextView(source: source, decorated: true)),
        ),
      );

      final headingLabel = '原文 · 第 1 / $totalChunks 段';
      final headings = find.text(headingLabel);
      expect(headings, findsOneWidget);
      final headingData = tester.getSemantics(headings).getSemanticsData();
      expect(headingData.label, headingLabel);
      expect(headingData.flagsCollection.isHeader, isTrue);

      final bodies = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(bodies, isNotEmpty);
      expect(bodies.length, lessThan(10));
      expect(bodies.every((body) => body.data!.length <= 4096), isTrue);
      expect(bodies.first.data, startsWith('chunk-0 '));
      expect(bodies.first.data, contains('😀中'));
      expect(find.text('原文 · 第 $totalChunks / $totalChunks 段'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('plain recovery chunks do not add decorated section headings', (
    tester,
  ) async {
    final source = List<String>.generate(
      80,
      (index) => 'plain-$index ${'正文😀' * 1100}',
    ).join('\n');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourceTextView(source: source)),
      ),
    );

    final chunks = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    expect(chunks, isNotEmpty);
    expect(chunks.length, lessThan(10));
    expect(chunks.every((chunk) => chunk.data!.length <= 4096), isTrue);
    expect(chunks.first.data, startsWith('plain-0 '));
    expect(find.textContaining('原文 · 第'), findsNothing);
    expect(find.textContaining('Source · part'), findsNothing);
    semantics.dispose();
  });
}
