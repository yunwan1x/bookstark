import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/reading_position_vault.dart';
import 'package:bookstark_flutter/features/books/books_feature.dart';
import 'package:bookstark_flutter/features/books/document_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/books.dart';

class ExcerptNotes extends NotesRepository {
  final saved = <Note>[];
  @override
  Future<int> save(Note note) async {
    saved.add(note);
    return note.id ?? 1;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => saved;
  @override
  Future<Note> read(int id) async => saved.last.copyWith(id: id);
  @override
  Future<void> remove(int id) async {}
}

void main() {
  testWidgets(
    'native Markdown selection opens an excerpt draft and creates only after save',
    (tester) async {
      final notes = ExcerptNotes();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: BooksFeature(
            books: BooksFixture(),
            documents: DocumentsFixture(),
            labels: LabelsFixture(),
            notes: notes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读的方法'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开或收起').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择适合自己的书'));
      await tester.pumpAndSettle();
      final paragraph = find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text.startsWith('阅读不必'),
      );
      await tester.tap(paragraph);
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(paragraph);
      const quote = '阅读不必从最难的书开始。';
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: const TextSelection(
            baseOffset: 0,
            extentOffset: quote.length,
          ),
        ),
        SelectionChangedCause.longPress,
      );
      state.showToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('摘录为笔记'));
      await tester.pumpAndSettle();
      expect(find.text('编辑笔记'), findsOneWidget);
      expect(notes.saved, isEmpty);
      final content = tester
          .widget<TextField>(find.byType(TextField).last)
          .controller!
          .text;
      expect(content, contains('> $quote'));
      expect(content, contains('文档 #2'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(notes.saved.length, 1);
      expect(notes.saved.single.title, '摘录 · 选择适合自己的书');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reading position restores only after explicit action and persists later scroll for same document',
    (tester) async {
      final values = <String, String>{};
      final vault = ReadingPositionVault(
        namespace: 'reader-space',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      await vault.write(2, const ReadingPosition(0.6, 'old'));
      final docs = DocumentsFixture();
      docs.records[2] = DocumentItem(
        id: 2,
        bookId: 1,
        parentId: 1,
        name: '长文档',
        markdown: List.filled(30, '## 标题\n\n正文内容保留阅读位置。').join('\n\n'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: DocumentReaderPage(
            bookId: 1,
            documentId: 2,
            books: BooksFixture(),
            documents: docs,
            positions: vault,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(ListView);
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.offset, 0);
      await tester.tap(find.text('继续上次阅读'));
      await tester.pumpAndSettle();
      expect(
        controller.offset / controller.position.maxScrollExtent,
        closeTo(0.6, 0.02),
      );
      await tester.drag(list, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final position = await vault.read(2);
      expect(position!.fraction, greaterThan(0.6));
      await tester.tap(find.text('下一篇'));
      await tester.pumpAndSettle();
      expect((await vault.read(2))!.fraction, position.fraction);
      expect(await vault.read(3), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
