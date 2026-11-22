import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/features/books/document_reader_page.dart';
import 'package:bookstark_flutter/features/document_reading_surface.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import '../tool/fixtures/books.dart';

class BoundedFixture extends DocumentsFixture
    implements BoundedDocumentsReader {
  BoundedFixture(this.source, {this.kind = 'markdown', this.actualBook = 1});
  final String source, kind;
  final int actualBook;
  int boundedCalls = 0, legacyCalls = 0;
  Completer<void>? held;
  @override
  Future<DocumentItem> read(int id) async {
    legacyCalls++;
    throw StateError('Bounded UI must not call legacy read');
  }

  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) async {
    boundedCalls++;
    await held?.future;
    final item = DocumentItem(
      id: id,
      bookId: actualBook,
      name: 'Owned chapter',
      type: kind,
      markdown: kind == 'html' ? '' : source,
      modifiedAt: '2026-11-11T10:00:00',
    );
    return TypedDocumentRead(
      item: item,
      source: source,
      byteLength: utf8.encode(source).length,
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  BoundedFixture docs, {
  Future<void> Function(BuildContext, DocumentItem)? onEdit,
  bool Function()? current,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DocumentReaderPage(
        bookId: 1,
        documentId: 2,
        books: BooksFixture(),
        documents: docs,
        boundedReader: docs,
        onEditComplex: onEdit,
        isCurrentScope: current,
        english: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> linuxHostBody(Future<void> Function() body) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

void main() {
  // These tests assert Dart routing/identity only. No Android native view is
  // registered; unsupported host must settle rather than pretend engine ready.

  testWidgets(
    'real reader uses bounded source and ordinary Markdown edit path',
    (tester) async {
      await linuxHostBody(() async {
        final docs = BoundedFixture('# Native Markdown');
        await mount(tester, docs);
        expect(docs.legacyCalls, 0);
        expect(docs.boundedCalls, 1);
        expect(find.textContaining('Native Markdown'), findsWidgets);
        expect(find.byType(DocumentReadingSurface), findsNothing);
      });
    },
  );
  testWidgets(
    'HTML raw source is used despite metadata empty markdown; writer is explicit',
    (tester) async {
      await linuxHostBody(() async {
        final docs = BoundedFixture('<p>Exact original</p>', kind: 'html');
        var edits = 0;
        await mount(
          tester,
          docs,
          onEdit: (context, item) async {
            edits++;
            expect(item.type, 'html');
            expect(item.id, 2);
          },
        );
        expect(find.byType(DocumentReadingSurface), findsOneWidget);
        final browser = tester.widget<ComplexEditorBrowser>(
          find.byType(ComplexEditorBrowser),
        );
        expect(browser.document.source, '<p>Exact original</p>');
        expect(browser.readOnly, true);
        expect(edits, 0);
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(edits, 1);
        expect(docs.legacyCalls, 0);
      });
    },
  );
  testWidgets(
    '500001 byte MD stays bounded segmented and cannot edit; 320/200 percent keyboard',
    (tester) async {
      await linuxHostBody(() async {
        final docs = BoundedFixture(List.filled(500001, 'x').join());
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: DocumentReaderPage(
              bookId: 1,
              documentId: 2,
              books: BooksFixture(),
              documents: docs,
              boundedReader: docs,
              english: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DocumentReadingSurface), findsOneWidget);
        final edit = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Edit'),
        );
        expect(edit.onPressed, isNull);
        expect(find.text('Next part'), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(docs.legacyCalls, 0);
      });
    },
  );
  testWidgets(
    'cross-book bounded response rejected before source reaches surface',
    (tester) async {
      await linuxHostBody(() async {
        final docs = BoundedFixture('DO NOT SHOW', actualBook: 99);
        await mount(tester, docs);
        expect(find.textContaining('DO NOT SHOW'), findsNothing);
        expect(find.byType(DocumentReadingSurface), findsNothing);
        expect(docs.legacyCalls, 0);
      });
    },
  );
  testWidgets('scope retired during bounded read never publishes late source', (
    tester,
  ) async {
    await linuxHostBody(() async {
      var current = true;
      final docs = BoundedFixture('OLD OWNER SECRET')..held = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentReaderPage(
            bookId: 1,
            documentId: 2,
            books: BooksFixture(),
            documents: docs,
            boundedReader: docs,
            isCurrentScope: () => current,
          ),
        ),
      );
      await tester.pump();
      current = false;
      docs.held!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('OLD OWNER SECRET'), findsNothing);
      expect(find.byType(DocumentReadingSurface), findsNothing);
      expect(docs.legacyCalls, 0);
    });
  });
}
