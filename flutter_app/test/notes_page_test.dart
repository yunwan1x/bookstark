import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class SearchRepository implements NotesRepository {
  final oldSearch = Completer<List<Note>>();
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async {
    if (keyword == '旧') return oldSearch.future;
    return [Note(id: 1, title: keyword.isEmpty ? '初始笔记' : '新结果', content: '')];
  }

  @override
  Future<void> remove(int id) async => throw StateError('删除失败');
  @override
  Future<Note> read(int id) async =>
      const Note(id: 1, title: '初始笔记', content: '');
  @override
  Future<int> save(Note note) async => 1;
}

void main() {
  testWidgets('slow old search cannot overwrite a newer search', (
    tester,
  ) async {
    final repository = SearchRepository();
    await tester.pumpWidget(
      MaterialApp(home: NotesPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    repository.oldSearch.complete([
      const Note(id: 2, title: '旧结果', content: ''),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
  });
  testWidgets('failed trash action preserves note in list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NotesPage(repository: SearchRepository())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移到回收站'));
    await tester.pumpAndSettle();
    expect(find.text('初始笔记'), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });
}
