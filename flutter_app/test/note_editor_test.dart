import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class Repository implements NotesRepository {
  final pending = Completer<int>();
  Note? submitted;
  @override
  Future<int> save(Note note) {
    submitted = note;
    return pending.future;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<Note> read(int id) async => throw UnimplementedError();
  @override
  Future<void> remove(int id) async {}
}

void main() {
  testWidgets('partial new-note save retries using the created ID', (
    tester,
  ) async {
    final repository = Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorPage(
          repository: repository,
          note: const Note(title: 'New', content: 'text'),
        ),
      ),
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    repository.pending.completeError(
      const NoteSaveFailure(42, 'labels failed'),
    );
    await tester.pumpAndSettle();
    expect(find.text('labels failed'), findsOneWidget);
    expect(find.text('未保存'), findsOneWidget);
    // The next request is an update, not a second creation.
    // A completed fake Future is enough: this assertion concerns the snapshot.
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.submitted!.id, 42);
  });

  testWidgets(
    'small editor with keyboard and double English text has no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 200),
            ),
            child: child!,
          ),
          home: NoteEditorPage(
            repository: Repository(),
            english: true,
            note: const Note(
              id: 1,
              title: 'Reading notes',
              content: '# Reading',
              labels: ['Reading', 'Ideas', 'Learning'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('input during save remains dirty and preview renders markdown', (
    tester,
  ) async {
    final repository = Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorPage(
          repository: repository,
          note: const Note(id: 1, title: '标题', content: '原文'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, '# 提交内容');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(repository.submitted!.content, '# 提交内容');
    await tester.enterText(find.byType(TextField).last, '# 后续输入');
    repository.pending.complete(1);
    await tester.pumpAndSettle();
    expect(find.text('未保存'), findsOneWidget);
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.text('后续输入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('discard confirmation leaves editor exactly once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NoteEditorPage(
                    repository: Repository(),
                    note: const Note(id: 1, title: '标题', content: '原文'),
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '修改');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(find.byType(NoteEditorPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps text available to retry', (tester) async {
    final repository = Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorPage(
          repository: repository,
          note: const Note(id: 1, title: '标题', content: '原文'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, '不能丢失');
    await tester.tap(find.text('保存'));
    await tester.pump();
    repository.pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('不能丢失'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text('未保存'), findsOneWidget);
  });
}
