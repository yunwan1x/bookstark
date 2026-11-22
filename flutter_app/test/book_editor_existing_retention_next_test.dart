import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/features/books/book_editor_page.dart';

class Labels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [];
}

class Books implements BooksRepository {
  int saves = 0;
  bool fail = false;
  BookItem actual = const BookItem(id: 17, name: 'Original');
  @override
  Future<int> save(BookItem value) async {
    saves++;
    if (fail) throw StateError('Offline');
    actual = value;
    return 17;
  }

  @override
  Future<BookItem> read(int id) async => actual;
  @override
  Future<BooksPageResult> list({String keyword = '', int page = 1}) =>
      throw UnimplementedError();
  @override
  Future<void> remove(int id) => throw UnimplementedError();
}

Future<void> open(
  WidgetTester tester,
  Books books,
  BookDraftVault vault, {
  bool Function()? current,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => BookEditorPage(
                repository: books,
                book: books.actual,
                labelsRepository: Labels(),
                vault: vault,
                english: true,
                ownerScope: 'one',
                isCurrentScope: current,
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'existing ID network failure retains actual fields for cold restore',
    (tester) async {
      final values = <String, String>{};
      final books = Books()..fail = true;
      final vault = BookDraftVault(
        namespace: 'existing-failure',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      await open(tester, books, vault);
      await tester.enterText(find.byType(TextField).first, 'Edited');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(books.saves, 1);
      expect((await vault.read(17))!.name, 'Edited');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await open(tester, books, vault);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Edited'), findsOneWidget);
      expect(books.actual.name, 'Original');
      expect(books.saves, 1);
    },
  );
  testWidgets(
    'ACK then draft removal failure retries storage only, no second save',
    (tester) async {
      final values = <String, String>{};
      final books = Books();
      var failDelete = true;
      final vault = BookDraftVault(
        namespace: 'existing-cleanup',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          if (failDelete) throw StateError('Store offline');
          values.remove(k);
        },
      );
      await open(tester, books, vault);
      await tester.enterText(find.byType(TextField).first, 'Saved');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(books.saves, 1);
      expect(books.actual.name, 'Saved');
      failDelete = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(books.saves, 1);
      expect(await vault.read(17), isNull);
    },
  );
  testWidgets('retired existing editor does not dispatch a save', (
    tester,
  ) async {
    final books = Books();
    var current = true;
    final vault = BookDraftVault(
      namespace: 'existing-retired',
      readValue: (_) async => null,
      writeValue: (_, _) async {},
      deleteValue: (_) async {},
    );
    await open(tester, books, vault, current: () => current);
    await tester.enterText(find.byType(TextField).first, 'Old scope');
    current = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(books.saves, 0);
  });
}
