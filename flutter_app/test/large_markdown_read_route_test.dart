import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/large_markdown_read_page.dart';
import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SingleNoteRepository implements NotesRepository {
  _SingleNoteRepository(this.note);
  final Note note;
  int reads = 0;
  int saves = 0;

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [note];

  @override
  Future<Note> read(int id) async {
    reads++;
    return note;
  }

  @override
  Future<int> save(Note value) async {
    saves++;
    throw StateError('Test repository must not save');
  }

  @override
  Future<void> remove(int id) async =>
      throw StateError('Test repository must not delete');
}

class _ProtectedNoteRepository
    implements NotesRepository, ProtectedNotesRepository {
  _ProtectedNoteRepository(this.source);
  final String source;
  int reads = 0;
  int unlocks = 0;
  int saves = 0;

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];

  @override
  Future<Note> read(int id) async {
    reads++;
    throw NoteLocked(id);
  }

  @override
  Future<Note> unlock(int id, String password) async {
    unlocks++;
    return Note(
      id: id,
      title: '受保护大型笔记',
      content: source,
      isProtected: true,
      unlockPassword: password,
    );
  }

  @override
  Future<int> save(Note note) async {
    saves++;
    throw StateError('Protected preview must not save');
  }

  @override
  Future<void> remove(int id) async =>
      throw StateError('Protected preview must not delete');
}

class _DedicatedEditorRepository implements NotesRepository {
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];

  @override
  Future<Note> read(int id) async =>
      throw const DedicatedEditorRequired(42, 'spreadsheet');

  @override
  Future<int> save(Note note) async => throw StateError('Unexpected save');

  @override
  Future<void> remove(int id) async => throw StateError('Unexpected delete');
}

Widget _openButton(NotesRepository repository) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () {
          openNativeNoteEditor(context, repository: repository, id: 42);
        },
        child: const Text('Open'),
      ),
    ),
  ),
);

List<EditableText> _editableTexts(WidgetTester tester) =>
    tester.widgetList<EditableText>(find.byType(EditableText)).toList();

Future<void> _dragIndexBarTo(WidgetTester tester, Finder target) async {
  final bar = find.byKey(const ValueKey('source-index-scrollbar'));
  final rect = tester.getRect(bar);
  const thumbExtent = 48.0;
  final startY = rect.top + thumbExtent / 2;
  final endY = rect.bottom - thumbExtent / 2;
  await tester.dragFrom(
    Offset(rect.center.dx, startY),
    Offset(0, endY - startY),
  );
  await tester.pumpAndSettle();
  expect(
    target,
    findsOneWidget,
    reason: 'index bar should land on target chunk',
  );
}

void main() {
  testWidgets('oversized existing Markdown opens read-only and stays chunked', (
    tester,
  ) async {
    final repository = _SingleNoteRepository(
      Note(
        id: 42,
        title: '大型正文',
        labels: const ['阅读', '本地'],
        content: '😀' * 125001 + 'TAIL_OF_ORIGINAL_SOURCE',
      ),
    );
    await tester.pumpWidget(_openButton(repository));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.reads, 1);
    expect(find.text('笔记原文'), findsOneWidget);
    expect(find.text('大型正文'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    final saveButton = find.ancestor(
      of: find.byTooltip('只读不可保存'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
    expect(find.byType(BackButton), findsOneWidget);
    expect(repository.saves, 0);

    var editors = _editableTexts(tester);
    expect(editors, isNotEmpty);
    expect(editors.every((editor) => editor.readOnly), isTrue);
    expect(
      editors.every((editor) => editor.controller.text.length <= 4096),
      isTrue,
    );
    expect(editors.length, lessThan(10));

    final pageChunks = SourceChunks(repository.note.content);
    final lastHeading = find.text(
      '原文 · 第 ${pageChunks.length} / ${pageChunks.length} 段',
    );
    await _dragIndexBarTo(tester, lastHeading);
    expect(lastHeading, findsOneWidget);
    editors = _editableTexts(tester);
    expect(editors, isNotEmpty);
    expect(editors.every((editor) => editor.readOnly), isTrue);
    expect(
      editors.every((editor) => editor.controller.text.length <= 4096),
      isTrue,
    );
    expect(
      editors.any(
        (editor) => editor.controller.text.contains('TAIL_OF_ORIGINAL_SOURCE'),
      ),
      isTrue,
    );
  });

  testWidgets(
    '320dp width and 200 percent text keep metadata bounded and source reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final title = '长标题内容' * 300;
      final labels = List<String>.generate(
        40,
        (index) => 'very long label $index',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: LargeMarkdownReadPage(
              title: title,
              labels: labels,
              source: '正文😀\r\n' * 300000,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final availableBody = tester.getSize(
        find
            .descendant(
              of: find.byType(LargeMarkdownReadPage),
              matching: find.byType(LayoutBuilder),
            )
            .first,
      );
      final metadataViewport = tester.getSize(
        find.byType(SingleChildScrollView).first,
      );
      expect(
        metadataViewport.height,
        lessThanOrEqualTo(availableBody.height * .45 + 1),
      );
      expect(
        find.byKey(const ValueKey('source-index-scrollbar')),
        findsOneWidget,
      );
      final pageChunks = SourceChunks('正文😀\r\n' * 300000);
      final lastHeading = find.text(
        '原文 · 第 ${pageChunks.length} / ${pageChunks.length} 段',
      );
      await _dragIndexBarTo(tester, lastHeading);
      expect(find.byTooltip('只读不可保存'), findsOneWidget);
    },
  );

  testWidgets(
    'exact 500000 UTF-8-byte existing body keeps the regular editor',
    (tester) async {
      final repository = _SingleNoteRepository(
        const Note(
          id: 42,
          title: 'At limit',
          content: '',
        ).copyWith(content: 'a' * 500000),
      );
      await tester.pumpWidget(_openButton(repository));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.reads, 1);
      expect(find.text('笔记原文'), findsNothing);
      expect(find.text('编辑笔记'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(repository.saves, 0);
    },
  );

  testWidgets(
    'locked oversized note shows no source and cancel never routes to reader',
    (tester) async {
      const secretMarker = 'ONLY_AFTER_UNLOCK';
      final source = '😀' * 125001 + secretMarker;
      final repository = _ProtectedNoteRepository(source);
      await tester.pumpWidget(_openButton(repository));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(repository.reads, 1);
      expect(find.text('解锁笔记'), findsOneWidget);
      expect(find.textContaining(secretMarker), findsNothing);
      expect(find.byType(LargeMarkdownReadPage), findsNothing);
      expect(repository.unlocks, 0);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(LargeMarkdownReadPage), findsNothing);
      expect(find.textContaining(secretMarker), findsNothing);
      expect(repository.unlocks, 0);
      expect(repository.saves, 0);
    },
  );

  testWidgets(
    'explicitly unlocked oversized note reveals source only on read-only route',
    (tester) async {
      const secretMarker = 'ONLY_AFTER_UNLOCK';
      final source = '😀' * 125001 + secretMarker;
      final repository = _ProtectedNoteRepository(source);
      await tester.pumpWidget(_openButton(repository));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(secretMarker), findsNothing);
      await tester.enterText(find.byKey(const Key('note-password')), 'secret');
      await tester.tap(find.text('解锁'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repository.unlocks, 1);
      expect(find.byType(LargeMarkdownReadPage), findsOneWidget);
      expect(repository.saves, 0);
      final chunks = SourceChunks(source);
      await _dragIndexBarTo(
        tester,
        find.text('原文 · 第 ${chunks.length} / ${chunks.length} 段'),
      );
      expect(
        _editableTexts(
          tester,
        ).any((editor) => editor.controller.text.contains(secretMarker)),
        isTrue,
      );
    },
  );

  testWidgets(
    'dedicated complex editor dispatch is not redirected to Markdown reader',
    (tester) async {
      final repository = _DedicatedEditorRepository();
      Object? failure;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await openNativeNoteEditor(
                      context,
                      repository: repository,
                      id: 42,
                    );
                  } catch (error) {
                    failure = error;
                  }
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();

      expect(failure, isA<DedicatedEditorRequired>());
      expect(find.byType(LargeMarkdownReadPage), findsNothing);
      expect(find.text('笔记原文'), findsNothing);
    },
  );
}
