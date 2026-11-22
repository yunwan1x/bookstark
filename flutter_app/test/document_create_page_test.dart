import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/document_creation.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/features/public_feed/document_create_page.dart';
import 'package:bookstark_flutter/features/public_feed/document_location_page.dart';
import '../tool/fixtures/books.dart';

class CreatePageDocs extends DocumentsFixture {
  int creates = 0;
  Object? failure;
  @override
  Future<DocumentItem> create(
    int bookId,
    String name, {
    int parentId = 0,
  }) async {
    creates++;
    if (failure != null) throw failure!;
    return super.create(bookId, name, parentId: parentId);
  }
}

void main() {
  testWidgets(
    'failed draft storage allows explicit exit without trapping navigation or creating',
    (tester) async {
      final books = BooksFixture(), docs = CreatePageDocs();
      final controller = DocumentCreationController(
        books: books,
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'failure',
          readValue: (_) async => null,
          writeValue: (_, value) async {
            throw StateError('secure storage failed');
          },
          deleteValue: (_) async {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentCreatePage(
                      controller: controller,
                      initialLocation: DocumentLocation(
                        book: books.records[1]!,
                        parentId: 0,
                        parentName: 'Root',
                      ),
                      onOpenEditor: (_, item) async {},
                      onReviewBook: (_, id) async {},
                    ),
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
      await tester.enterText(find.byType(TextField), 'Unsaved input');
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('草稿未确认保存'), findsOneWidget);
      expect(docs.creates, 0);
      await tester.tap(find.text('仍然退出'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentCreatePage), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(docs.creates, 0);
    },
  );

  testWidgets(
    'known receipt remains available when editor opening fails and retry never creates again',
    (tester) async {
      final books = BooksFixture(), docs = CreatePageDocs();
      final values = <String, String>{};
      var opens = 0;
      final controller = DocumentCreationController(
        books: books,
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'local',
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCreatePage(
            controller: controller,
            initialLocation: DocumentLocation(
              book: books.records[1]!,
              parentId: 1,
              parentName: 'Actual parent',
            ),
            onOpenEditor: (_, item) async {
              opens++;
              throw StateError('editor failed');
            },
            onReviewBook: (_, id) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Actual created name');
      await tester.tap(find.text('创建并编辑'));
      await tester.pumpAndSettle();
      expect(docs.creates, 1);
      expect(opens, 1);
      expect(find.textContaining('已创建文档 ID：'), findsOneWidget);
      await tester.tap(find.text('打开已创建文档'));
      await tester.pumpAndSettle();
      expect(docs.creates, 1);
      expect(opens, 2);
      expect(controller.draft?.phase, DocumentCreationPhase.acknowledged);
    },
  );
  testWidgets(
    'unknown create stays read only after rebuilding from secure state',
    (tester) async {
      final books = BooksFixture(),
          docs = CreatePageDocs()..failure = TimeoutException('lost reply');
      final values = <String, String>{};
      DocumentCreationController controller() => DocumentCreationController(
        books: books,
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'member',
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        ),
      );
      Widget app(DocumentCreationController session) => MaterialApp(
        key: UniqueKey(),
        home: DocumentCreatePage(
          controller: session,
          initialLocation: DocumentLocation(
            book: books.records[1]!,
            parentId: 0,
            parentName: 'Root',
          ),
          onOpenEditor: (_, item) async {
            throw StateError('must not open');
          },
          onReviewBook: (_, id) async {},
        ),
      );
      await tester.pumpWidget(app(controller()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pending exact name');
      await tester.tap(find.text('创建并编辑'));
      await tester.pumpAndSettle();
      expect(docs.creates, 1);
      expect(find.text('创建结果待核对'), findsOneWidget);
      final restored = controller();
      await tester.pumpWidget(app(restored));
      await tester.pumpAndSettle();
      expect(find.text('创建结果待核对'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, true);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '创建并编辑'))
            .onPressed,
        isNull,
      );
      expect(restored.draft?.name, 'Pending exact name');
      expect(docs.creates, 1);
    },
  );
  testWidgets(
    'English create form supports small text scaling with keyboard inset',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final books = BooksFixture(), docs = CreatePageDocs();
      final controller = DocumentCreationController(
        books: books,
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'small',
          readValue: (_) async => null,
          writeValue: (_, value) async {},
          deleteValue: (_) async {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 220),
            ),
            child: child!,
          ),
          home: DocumentCreatePage(
            controller: controller,
            initialLocation: DocumentLocation(
              book: books.records[1]!,
              parentId: 0,
              parentName: 'Root',
            ),
            english: true,
            onOpenEditor: (_, item) async {},
            onReviewBook: (_, id) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create and edit'), findsOneWidget);
      expect(docs.creates, 0);
    },
  );
}
