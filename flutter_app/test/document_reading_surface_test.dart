// Draft widget regressions; not executed. No platform view/Native assertions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/documents_repository.dart';

import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';

import 'package:bookstark_flutter/core/document_route_adapter.dart';
import 'package:bookstark_flutter/features/document_reading_surface.dart';

PreparedDocumentRoute route(String text, {int id = 7, bool unknown = false}) =>
    PreparedDocumentRoute(
      item: DocumentItem(
        id: id,
        bookId: 3,
        name: '原文',
        type: unknown ? 'future' : 'markdown',
        modifiedAt: 't',
      ),
      mode: DocumentReadingMode.boundedOriginal,
      source: text,
      editGate: unknown
          ? DocumentEditGate.unsupportedType
          : DocumentEditGate.markdownTooLarge,
    );

Widget host(Widget body) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(320, 640),
      textScaler: TextScaler.linear(2),
      viewInsets: EdgeInsets.only(bottom: 180),
    ),
    child: Scaffold(body: SizedBox(width: 320, height: 460, child: body)),
  ),
);

void main() {
  testWidgets('large body uses bounded source and restores last part', (
    tester,
  ) async {
    final source = '${'a' * 16384}\ufeff末尾🙂\r\n';
    final chunks = SourceChunks(source);
    var markdownCalls = 0;
    int? excerptId;
    String? excerpt;
    await tester.pumpWidget(
      host(
        DocumentReadingSurface(
          route: route(source),
          initialFraction: 1,
          english: true,
          markdownBody: (_) {
            markdownCalls++;
            return const Text('wrong full renderer');
          },
          onExcerptCurrentPart: (item, text) async {
            excerptId = item.id;
            excerpt = text;
          },
        ),
      ),
    );
    expect(markdownCalls, 0);
    expect(find.text(chunks.at(chunks.length - 1)), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    final action = find.widgetWithText(OutlinedButton, 'Excerpt current part');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    expect(excerptId, 7);
    expect(excerpt, chunks.at(chunks.length - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown source requires explicit view and never receives editor',
    (tester) async {
      await tester.pumpWidget(
        host(
          DocumentReadingSurface(
            route: route('opaque original', unknown: true),
            markdownBody: (_) => const Text('wrong renderer'),
          ),
        ),
      );
      expect(find.text('opaque original'), findsNothing);
      await tester.tap(find.text('查看完整原文（只读）'));
      await tester.pump();
      expect(find.text('opaque original'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'position failure is visible and next change carries source identity',
    (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(
        host(
          DocumentReadingSurface(
            route: route('a' * 12000),
            english: true,
            markdownBody: (_) => const SizedBox(),
            onPartPosition: (item, fraction) async {
              seen.add(item.id);
              expect(fraction, greaterThan(0));
              throw StateError('private storage failure');
            },
          ),
        ),
      );
      final action = find.widgetWithText(OutlinedButton, 'Next part');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(seen, [7]);
      expect(
        find.text('Reading position was not saved. Retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('private storage'), findsNothing);
    },
  );
}
