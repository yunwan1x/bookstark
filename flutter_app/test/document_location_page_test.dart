import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/features/public_feed/document_location_page.dart';
import '../tool/fixtures/books.dart';

class ReadOnlyDocuments extends DocumentsFixture {
  int writes = 0, trees = 0;
  @override
  Future<List<DocumentNode>> tree(int bookId) {
    trees++;
    return super.tree(bookId);
  }

  @override
  Future<DocumentItem> create(
    int bookId,
    String name, {
    int parentId = 0,
  }) async {
    writes++;
    throw StateError('Selector must never create');
  }
}

class LateDocuments extends ReadOnlyDocuments {
  final first = Completer<List<DocumentNode>>();
  @override
  Future<List<DocumentNode>> tree(int bookId) =>
      bookId == 1 ? first.future : super.tree(bookId);
}

void main() {
  testWidgets('late tree from previous book cannot restore its parent IDs', (
    tester,
  ) async {
    final books = BooksFixture(), docs = LateDocuments();
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentLocationPage(
          books: books,
          documents: docs,
          initialBook: books.records[1],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '阅读的方法'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('写作与思考'));
    await tester.pumpAndSettle();
    docs.first.complete([const DocumentNode(id: 99, name: 'Stale parent')]);
    await tester.pumpAndSettle();
    expect(find.text('Stale parent'), findsNothing);
    expect(find.text('写作与思考'), findsOneWidget);
    expect(find.text('当前选择：书籍根目录'), findsOneWidget);
  });
  testWidgets(
    'English location fits 320dp with 200 percent text and nested breadcrumbs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final books = BooksFixture(), docs = ReadOnlyDocuments();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DocumentLocationPage(
            books: books,
            documents: docs,
            initialBook: books.records[1],
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ListTile, '第一章：建立阅读习惯'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ListTile, '第一章：建立阅读习惯'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Up one level'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Choose this location'), findsOneWidget);
    },
  );
  testWidgets(
    'nested location returns actual IDs only after a fresh membership read',
    (tester) async {
      final books = BooksFixture(), docs = ReadOnlyDocuments();
      DocumentLocation? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<DocumentLocation>(
                    MaterialPageRoute(
                      builder: (_) => DocumentLocationPage(
                        books: books,
                        documents: docs,
                        initialBook: books.records[1],
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
      await tester.tap(find.widgetWithText(ListTile, '第一章：建立阅读习惯'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '选择适合自己的书'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择此位置'));
      await tester.pumpAndSettle();
      expect(result?.book.id, 1);
      expect(result?.parentId, 2);
      expect(result?.parentName, '选择适合自己的书');
      expect(docs.trees, 2);
      expect(docs.writes, 0);
    },
  );
  testWidgets(
    'deleted parent never returns stale ID and requires explicit new selection',
    (tester) async {
      final books = BooksFixture(), docs = ReadOnlyDocuments();
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentLocationPage(
            books: books,
            documents: docs,
            initialBook: books.records[1],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '第一章：建立阅读习惯'));
      await tester.pumpAndSettle();
      docs.records.remove(1);
      await tester.tap(find.text('选择此位置'));
      await tester.pumpAndSettle();
      expect(find.textContaining('所选父目录已删除'), findsOneWidget);
      expect(find.text('选择文档位置'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('当前选择：书籍根目录'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('当前选择：书籍根目录'), findsOneWidget);
      expect(docs.writes, 0);
    },
  );
  testWidgets(
    'book picker exposes pagination and changing book clears prior parent',
    (tester) async {
      final books = BooksFixture(), docs = ReadOnlyDocuments();
      for (var id = 4; id <= 25; id++) {
        books.records[id] = BookItem(id: id, name: 'Actual book $id');
      }
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentLocationPage(
            books: books,
            documents: docs,
            initialBook: books.records[1],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '第一章：建立阅读习惯'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '阅读的方法'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('加载更多'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Actual book 20'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Actual book 20'));
      await tester.pumpAndSettle();
      expect(find.text('Actual book 20'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('当前选择：书籍根目录'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('当前选择：书籍根目录'), findsOneWidget);
      expect(find.text('返回上一级'), findsNothing);
      expect(docs.writes, 0);
    },
  );
}
