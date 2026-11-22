import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/document_editor_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/books/books_feature.dart';
import 'package:bookstark_flutter/features/books/chapters_page.dart';
import 'package:bookstark_flutter/features/books/document_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/books.dart';

class FailingDocuments extends DocumentsFixture {
  bool failContent = true;
  @override
  Future<void> saveMarkdown(int id, String markdown) async {
    if (failContent) throw StateError('正文暂时未保存');
    await super.saveMarkdown(id, markdown);
  }
}

Future<void> mount(
  WidgetTester tester,
  Widget page, {
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(english ? 2 : 1)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'document editor adapter retries same document after title-only success',
    () async {
      final docs = FailingDocuments();
      final repo = DocumentEditorRepository(docs, 1);
      final original = await repo.read(2);
      final changed = original.copyWith(title: '已改名', content: '新正文');
      await expectLater(
        repo.save(changed),
        throwsA(
          isA<NoteSaveFailure>().having(
            (error) => error.savedId,
            'saved ID',
            2,
          ),
        ),
      );
      expect(docs.records[2]!.name, '已改名');
      expect(docs.records[2]!.markdown, DocumentsFixture.body);
      docs.failContent = false;
      expect(await repo.save(changed), 2);
      expect(docs.records.length, 7);
      expect(docs.records[2]!.markdown, '新正文');
      await expectLater(
        DocumentEditorRepository(docs, 99).save(changed),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'books open actual chapters, reader, shared editor and re-read saved Markdown',
    (tester) async {
      final books = BooksFixture(), docs = DocumentsFixture();
      await mount(
        tester,
        BooksFeature(books: books, documents: docs, labels: LabelsFixture()),
      );
      await tester.tap(find.text('阅读的方法'));
      await tester.pumpAndSettle();
      expect(find.text('7篇文档'), findsOneWidget);
      await tester.tap(find.byTooltip('展开或收起').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择适合自己的书'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('编辑文档'), findsOneWidget);
      expect(find.text('添加标签'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '原生文档标题');
      await tester.enterText(find.byType(TextField).last, '# 保存后阅读\n\n- 真实内容');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(docs.records[2]!.markdown, '# 保存后阅读\n\n- 真实内容');
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      expect(find.text('原生文档标题'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      await tester.tap(find.text('下一篇'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('每天二十分钟')),
        findsOneWidget,
      );
      await tester.tap(find.text('上一篇'));
      await tester.pumpAndSettle();
      expect(find.text('原生文档标题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chapter search keeps ancestors and parent deletion refuses before API call',
    (tester) async {
      final books = BooksFixture(), docs = DocumentsFixture();
      await mount(
        tester,
        ChaptersPage(
          bookId: 1,
          books: books,
          documents: docs,
          onOpen: (_, _) async {},
          onSettings: (_, _) async {},
        ),
      );
      await tester.enterText(find.byType(TextField), '每天');
      await tester.pumpAndSettle();
      expect(find.text('第一章：建立阅读习惯'), findsOneWidget);
      expect(find.text('每天二十分钟'), findsOneWidget);
      expect(find.text('第二章：把知识用起来'), findsNothing);
      await tester.tap(find.byTooltip('文档菜单').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('章节包含子文档'), findsOneWidget);
      expect(docs.removes, 0);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建文档'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '新建真实ID');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(docs.records[8]!.name, '新建真实ID');
      expect(docs.records[8]!.bookId, 1);
    },
  );
  testWidgets(
    'reader rejects wrong-book navigation while retaining current document',
    (tester) async {
      final docs = DocumentsFixture();
      docs.records[3] = const DocumentItem(id: 3, bookId: 99, name: '其他书籍');
      // The fixture derives navigation from its own book, so explicitly return
      // an inconsistent server navigation ID for this contract failure scenario.
      final adapter = WrongNavigationDocuments(docs);
      await mount(
        tester,
        DocumentReaderPage(
          bookId: 1,
          documentId: 2,
          books: BooksFixture(),
          documents: adapter,
        ),
      );
      await tester.tap(find.text('下一篇'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Navigation document belongs'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('选择适合自己的书'),
        ),
        findsOneWidget,
      );
      expect(find.text('其他书籍'), findsNothing);
    },
  );
  testWidgets(
    'English chapter tree and native reader fit 320dp at double text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final books = BooksFixture(), docs = DocumentsFixture();
      await mount(
        tester,
        BooksFeature(
          books: books,
          documents: docs,
          labels: LabelsFixture(),
          english: true,
        ),
        english: true,
      );
      await tester.tap(find.text('阅读的方法'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章：建立阅读习惯'));
      await tester.pumpAndSettle();
      expect(find.text('Previous'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class WrongNavigationDocuments extends DocumentsFixture {
  WrongNavigationDocuments(this.source);
  final DocumentsFixture source;
  @override
  Future<DocumentItem> read(int id) async {
    final item = await source.read(id);
    return DocumentItem(
      id: item.id,
      bookId: item.bookId,
      name: item.name,
      markdown: item.markdown,
      parentId: item.parentId,
      nextId: id == 2 ? 3 : item.nextId,
    );
  }
}
