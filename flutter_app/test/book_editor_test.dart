import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/features/books/book_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestBooks implements BooksRepository {
  final calls = <BookItem>[];
  Completer<int>? gate;
  bool partial = false;
  @override
  Future<int> save(BookItem book) async {
    calls.add(book);
    if (partial) throw BookSaveFailure(42, StateError('标签失败'));
    return gate?.future ?? Future.value(book.id ?? 42);
  }

  @override
  Future<BookItem> read(int id) async => throw UnimplementedError();
  @override
  Future<BooksPageResult> list({String keyword = '', int page = 1}) async =>
      const BooksPageResult([], 0, 1, 12);
  @override
  Future<void> remove(int id) async {}
}

class TestLabels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [
    ' 阅读 ',
    '学习',
  ];
}

BookDraftVault vaultFor(Map<String, String> data) => BookDraftVault(
  namespace: 'space',
  readValue: (key) async => data[key],
  writeValue: (key, value) async {
    data[key] = value;
  },
  deleteValue: (key) async {
    data.remove(key);
  },
);
Future<void> mount(
  WidgetTester tester,
  TestBooks repo, {
  BookDraftVault? vault,
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BookEditorPage(
                  repository: repo,
                  book: const BookItem(name: ''),
                  labelsRepository: TestLabels(),
                  vault: vault,
                  english: english,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'book partial create retries same real ID and preserves typed fields',
    (tester) async {
      final repo = TestBooks()..partial = true;
      await mount(tester, repo);
      await tester.enterText(find.byType(TextField).at(0), '书名');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.calls.single.id, isNull);
      expect(find.text('书名'), findsWidgets);
      repo.partial = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.id, 42);
      expect(find.text('open'), findsOneWidget);
    },
  );
  testWidgets('typing during book creation remains dirty and retry is PUT', (
    tester,
  ) async {
    final repo = TestBooks()..gate = Completer<int>();
    await mount(tester, repo);
    await tester.enterText(find.byType(TextField).at(0), '提交内容');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '请求期间继续编辑');
    repo.gate!.complete(42);
    await tester.pumpAndSettle();
    expect(find.text('请求期间继续编辑'), findsOneWidget);
    repo.gate = null;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.id, 42);
    expect(repo.calls.last.name, '请求期间继续编辑');
  });
  testWidgets(
    'book draft explicit keep and restore preserve name description labels',
    (tester) async {
      final data = <String, String>{};
      final vault = vaultFor(data);
      final repo = TestBooks();
      await mount(tester, repo, vault: vault);
      await tester.enterText(find.byType(TextField).at(0), '未保存书名');
      await tester.enterText(find.byType(TextField).at(1), '未保存说明');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿'));
      await tester.pumpAndSettle();
      expect((await vault.read(null))!.description, '未保存说明');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('未保存书名'), findsOneWidget);
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets(
    'English book form supports small width large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await mount(tester, TestBooks(), english: true);
      await tester.scrollUntilVisible(
        find.text('Add labels'),
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Add labels'));
      await tester.pumpAndSettle();
      expect(find.text('Choose labels'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(' 阅读 '),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(' 阅读 '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
