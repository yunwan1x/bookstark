import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'remote_article_creation_page_next_test.dart' as article_fixture;
import 'package:bookstark_flutter/features/complex_editors/remote_article_creation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/bookmark_draft_vault.dart';
import 'package:bookstark_flutter/core/document_creation.dart';
import 'package:bookstark_flutter/core/resource_creation_result.dart';
import 'package:bookstark_flutter/features/public_feed/resource_create_coordinator.dart';
import 'package:bookstark_flutter/features/public_feed/resource_create_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import '../tool/fixtures/books.dart';
import '../tool/fixtures/bookmarks.dart';

class CreationNotes implements NotesRepository {
  CreationNotes(this.id, {this.partial = false});
  final int id;
  bool partial;
  int saves = 0;
  @override
  Future<int> save(Note note) async {
    saves++;
    if (partial) {
      partial = false;
      throw NoteSaveFailure(id, 'labels pending');
    }
    return note.id ?? id;
  }

  @override
  Future<Note> read(int id) async =>
      Note(id: id, title: 'Actual', content: 'Body');
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<void> remove(int id) async {}
}

ResourceCreateCoordinator coordinator(
  CreationNotes notes,
  CreationNotes articles, {
  Future<ResourceCreationResult?> Function(BuildContext)? onCreateArticle,
}) {
  final values = <String, String>{};
  Future<String?> read(String key) async => values[key];
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  Future<void> remove(String key) async {
    values.remove(key);
  }

  DraftVault drafts(String name) => DraftVault(
    namespace: name,
    readValue: read,
    writeValue: write,
    deleteValue: remove,
  );
  return ResourceCreateCoordinator(
    notes: notes,
    articles: articles,
    onCreateArticle: onCreateArticle,
    bookmarks: BookmarksFixture(),
    books: BooksFixture(),
    documents: DocumentsFixture(),
    labels: LabelsFixture(),
    noteDrafts: drafts('note'),
    articleDrafts: drafts('article'),
    documentDrafts: drafts('doc'),
    bookmarkDrafts: BookmarkDraftVault(
      namespace: 'bookmarks',
      readValue: read,
      writeValue: write,
      deleteValue: remove,
    ),
    bookDrafts: BookDraftVault(
      namespace: 'books',
      readValue: read,
      writeValue: write,
      deleteValue: remove,
    ),
    documentCreationVault: DocumentCreationVault(
      namespace: 'creation',
      readValue: read,
      writeValue: write,
      deleteValue: remove,
    ),
  );
}

void main() {
  testWidgets(
    'canceling selector writes nothing and produces no invented creation result',
    (tester) async {
      final notes = CreationNotes(701), articles = CreationNotes(702);
      final creator = coordinator(notes, articles);
      ResourceCreationResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await creator.open(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceCreatePage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('取消'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(ResourceCreatePage), findsNothing);
      expect(notes.saves + articles.saves, 0);
    },
  );
  for (final existing in [false, true]) {
    testWidgets(
      'bookmark receipt distinguishes confirmed existing edit from new creation: $existing',
      (tester) async {
        final notes = CreationNotes(701), articles = CreationNotes(702);
        final creator = coordinator(notes, articles);
        ResourceCreationResult? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await creator.open(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('书签'));
        await tester.pumpAndSettle();
        final url = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '网址',
        );
        final title = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '标题',
        );
        await tester.enterText(
          url,
          existing ? 'https://flutter.dev' : 'https://example.test/created',
        );
        await tester.enterText(title, 'Actual bookmark title');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        if (existing) {
          await tester.tap(find.text('编辑已有书签'));
          await tester.pumpAndSettle();
          await tester.enterText(title, 'Explicit existing edit');
          await tester.tap(find.text('保存'));
          await tester.pumpAndSettle();
        }
        expect(result?.id, existing ? 1 : 4);
        expect(result?.kind, CreatedResourceKind.bookmark);
        expect(result?.created, !existing);
        expect(result?.metadataComplete, true);
        expect(
          result?.title,
          existing ? 'Explicit existing edit' : 'Actual bookmark title',
        );
        expect(notes.saves + articles.saves, 0);
      },
    );
  }
  for (final (article, partial) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'typed note/article acknowledgement preserves pending metadata: $article/$partial',
      (tester) async {
        if (article) {
          final notes = CreationNotes(741), articles = CreationNotes(742);
          final f = article_fixture.ArticleCreationPageFixture()
            ..deleteFails = partial;
          ResourceCreationResult? result;
          final creator = coordinator(
            notes,
            articles,
            onCreateArticle: (context) async {
              final c = await f.open();
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RemoteArticleCreationPage(
                    binding: f.binding(c),
                    surfaceBuilder: article_fixture.articleCreationSurface,
                    openKnown: (_, _) async {},
                  ),
                ),
              );
              final record = c.record, id = record.knownId;
              if (id == null) return null;
              return ResourceCreationResult(
                kind: CreatedResourceKind.article,
                id: id,
                title: record.input.title,
                created:
                    record.knownIDOrigin == MarkdownKnownIDOrigin.postReceipt,
                metadataComplete: c.phase == MarkdownCreationPhase.finished,
              );
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await creator.open(
                        context,
                        initialKind: ResourceCreateKind.article,
                      );
                    },
                    child: const Text('Open article'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open article'));
          for (var i = 0; i < 35; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(find.byType(RemoteArticleCreationPage), findsOneWidget);
          expect(find.byType(NoteEditorPage), findsNothing);
          final engine = tester
              .state<article_fixture.ArticleCreationEngineState>(
                find.byType(article_fixture.ArticleCreationEngine),
              );
          engine.enter('# Actual article source');
          await tester.pump(const Duration(milliseconds: 650));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(f.wire.posts, 0);
          await tester.tap(
            find.widgetWithText(FilledButton, 'Save article').hitTestable(),
          );
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(f.wire.posts, 1);
          expect(f.wire.sent!.content, '# Actual article source');
          expect(f.values.isNotEmpty, partial);
          await tester.ensureVisible(
            find.widgetWithText(OutlinedButton, 'Keep and return'),
          );
          await tester.tap(
            find
                .widgetWithText(OutlinedButton, 'Keep and return')
                .hitTestable(),
          );
          // Native messenger completion needs a real event-loop turn as well
          // as widget frames. Keep this bounded; never bypass the close ACK.
          for (var i = 0; i < 100 && result == null; i++) {
            await tester.pump(const Duration(milliseconds: 10));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
          }
          expect(result?.id, 208);
          expect(result?.kind, CreatedResourceKind.article);
          expect(result?.created, isTrue);
          expect(result?.metadataComplete, !partial);
          expect(notes.saves, 0);
          expect(articles.saves, 0);
          expect(f.repo.saves, 0);
          expect(f.wire.posts, 1);
          await tester.pumpWidget(const SizedBox());
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(tester.takeException(), isNull);
          return;
        }
        final notes = CreationNotes(741, partial: !article && partial),
            articles = CreationNotes(742, partial: article && partial);
        final creator = coordinator(notes, articles);
        ResourceCreationResult? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await creator.open(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(article ? '文章' : '笔记'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == (article ? '文章标题' : '笔记标题'),
          ),
          'Actual new title',
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == 'Markdown…',
          ),
          'Actual body',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(NoteEditorPage))).pop();
        await tester.pumpAndSettle();
        expect(result?.id, article ? 742 : 741);
        expect(
          result?.kind,
          article ? CreatedResourceKind.article : CreatedResourceKind.note,
        );
        expect(result?.created, true);
        expect(result?.metadataComplete, !partial);
        expect(result?.title, 'Actual new title');
        expect(notes.saves, article ? 0 : 1);
        expect(articles.saves, article ? 1 : 0);
      },
    );
  }
}
