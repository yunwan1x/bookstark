import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'dart:async';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';
import 'package:bookstark_flutter/core/local_assistant_repository.dart';
import 'package:bookstark_flutter/features/assistant/local_model_settings_page.dart';
import 'package:bookstark_flutter/features/settings/device_settings_page.dart';
import 'package:bookstark_flutter/core/native_recovery_storage.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_create_page.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/public_feed/resource_create_page.dart';
import 'package:bookstark_flutter/features/public_feed/document_create_page.dart';
import 'package:bookstark_flutter/features/public_feed/document_location_page.dart';
import 'package:file_selector/file_selector.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/features/drive/drive_page.dart';
import 'package:bookstark_flutter/features/drive/file_editor_page.dart';
import 'dart:convert';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/features/images/images_page.dart';
import 'package:bookstark_flutter/features/images/image_preview_page.dart';
import 'package:bookstark_flutter/features/search/search_page.dart';
import 'package:bookstark_flutter/features/labels/labels_page.dart';
import 'package:bookstark_flutter/features/labels/label_detail_page.dart';
import 'package:bookstark_flutter/features/books/chapters_page.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_documents_repository.dart';
import 'package:bookstark_flutter/core/local_tasks_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/local_topics_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/topics/topics_page.dart';
import 'package:bookstark_flutter/features/topics/topic_detail_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'package:bookstark_flutter/features/books/document_reader_page.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmark_editor_page.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import 'package:bookstark_flutter/features/navigation/navigation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
    'real root opens typed sources and routes local Markdown articles to WebView controllers',
    (tester) async {
      final oldHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal = oldHitTestPolicy,
      );
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bookstark-app-navigation-'),
      ))!;
      final supportAlias = Link('${directory.path}/support-alias');
      await tester.runAsync(() => supportAlias.create(directory.path));
      sqlite.databaseFactory = databaseFactoryFfiNoIsolate;
      await databaseFactoryFfiNoIsolate.setDatabasesPath(directory.path);
      FlutterSecureStorage.setMockInitialValues({});
      // This root-routing test deliberately leaves the browser plugin unavailable;
      // actual engine input/preview has its own real browser and Android contracts.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeComplexRecoveryStore.channel, (
            call,
          ) async {
            if (call.method == 'beginRead') return null;
            throw StateError('Unexpected recovery mutation in route-only test');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeComplexRecoveryStore.channel, null),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeRecoveryStorage.channel, (
            call,
          ) async {
            if (call.method == 'flush' && call.arguments == null) return true;
            if (call.method == 'localMetadata') {
              final keys = (await const FlutterSecureStorage(
                aOptions: AndroidOptions(
                  sharedPreferencesName: 'FlutterSecureStorage',
                ),
              ).readAll()).keys.toList();
              return {
                'format': 1,
                'secureKeys': keys,
                'htmlKeys': <String>[],
                'overflow': false,
                'valuesIncluded': false,
              };
            }

            if (call.method != 'localArticleCreationDraftFingerprint') {
              throw StateError(
                'Unexpected recovery purpose in root route test',
              );
            }
            final args = call.arguments as Map;
            expect(args.keys.toSet(), {'key'});
            final key = args['key'] as String;
            LocalArticleCreationLegacyScope.fromLegacyKey(key);
            return {
              'format': 1,
              'key': key,
              'sha256': null,
              'ciphertextBytes': 0,
              'valuesIncluded': false,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeRecoveryStorage.channel, null),
      );

      const localControl = MethodChannel('bookstark/local_data_control');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localControl, (call) async {
            if (call.method != 'readState') {
              throw StateError('Unexpected local mutation');
            }
            return {
              'format': 1,
              'pointerRaw': null,
              'intentRaw': null,
              'currentRetentionRaw': null,
              'sourceRetentionRaw': null,
              'metadataOnly': true,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localControl, null),
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => supportAlias.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        sqlite.databaseFactory = null;
        await directory.delete(recursive: true);
      });
      late int topicId,
          noteId,
          articleId,
          documentId,
          taskId,
          bookmarkId,
          bookId,
          createdDocumentId;
      await tester.runAsync(() async {
        final store = LocalStore(
          path: '${directory.path}/bookstark-flutter.db',
          factory: databaseFactoryFfiNoIsolate,
        );
        final repository = LocalBookmarksRepository(store);
        final id = await repository.save(
          const BookmarkItem(
            title: '真实本地书签',
            url: 'https://example.test/local',
            labels: ['a,b', ' 保留 ', '贯通标签'],
          ),
        );
        bookmarkId = id;
        await repository.setNavVisible(id, true);
        noteId = await LocalNotesRepository(store).save(
          const Note(title: '真实本地笔记', content: '# 笔记正文', labels: ['贯通标签']),
        );
        articleId =
            await LocalNotesRepository(
              store,
              collection: NoteCollection.article,
            ).save(
              const Note(title: '真实本地文章', content: '# 文章正文', labels: ['贯通标签']),
            );
        bookId = await LocalBooksRepository(
          store,
        ).save(const BookItem(name: '源书籍', labels: ['贯通标签']));
        final documents = LocalDocumentsRepository(store);
        documentId = (await documents.tree(bookId)).single.id;
        await documents.saveMarkdown(documentId, '# 文档正文');
        await (await store.database).update(
          'documents',
          {'labels': '["贯通标签"]'},
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
        taskId = await LocalTasksRepository(
          store,
        ).save(const TaskItem(content: '真实本地待办', dueDate: '2026-11-04'));
        final topics = LocalTopicsRepository(store);
        topicId = await topics.save(
          const TopicItem(title: '真实本地主题', question: '如何完成原生改写？'),
        );
        await topics.saveSummary(
          TopicSummary(topicId: topicId, content: '# 原生小结'),
        );
        for (final source in [
          (TopicResourceType.note, noteId),
          (TopicResourceType.article, articleId),
          (TopicResourceType.document, documentId),
          (TopicResourceType.task, taskId),
          (TopicResourceType.bookmark, bookmarkId),
        ]) {
          await topics.addResource(
            TopicResource(
              topicId: topicId,
              type: source.$1,
              targetId: source.$2,
            ),
          );
        }
        final media = LocalAttachments(
          Directory('${directory.path}/attachments'),
        );
        final images = LocalImagesRepository(store, media);
        await images.upload(
          ImageUploadPayload.fromBytes(
            name: '真实原生图片.svg',
            bytes: Uint8List.fromList(
              utf8.encode(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50"><rect width="50" height="50" fill="blue"/></svg>',
              ),
            ),
            category: ImageCategory.editor,
          ),
        );
        final drive = LocalDriveRepository(
          store,
          Directory('${directory.path}/drive-blobs'),
        );
        final driveSource = File('${directory.path}/drive-source.md');
        await driveSource.writeAsString('# 本地文件正文');
        await drive.upload(
          await DriveSourceSnapshot.prepare(
            XFile(driveSource.path),
            maxBytes: 4096,
          ),
          target: '真实文件.md',
        );
        drive.dispose();
        images.dispose();
        media.close();
        await store.close();
      });
      Future<void> drain() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(const BookstarkApp());
      await drain();
      await tester.tap(find.text('本地空间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入本地空间'));
      await drain();
      await tester.tap(find.text('设置'));
      await drain();
      expect(find.byType(DeviceSettingsPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('本地模型配置'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('本地模型配置'));
      await drain();
      expect(find.byType(LocalModelSettingsPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('local-model-endpoint')),
        'https://model.example.invalid/v1',
      );
      await tester.enterText(
        find.byKey(const Key('local-model-name')),
        'root-fixture-model',
      );
      await tester.enterText(
        find.byKey(const Key('local-model-key')),
        'root-fixture-key',
      );
      await tester.scrollUntilVisible(
        find.text('保存配置'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await drain();
      expect(
        tester
            .widget<LocalModelSettingsPage>(find.byType(LocalModelSettingsPage))
            .controller
            .saved!
            .model,
        'root-fixture-model',
      );
      await tester.binding.handlePopRoute();
      await drain();
      expect(find.byType(DeviceSettingsPage), findsOneWidget);
      await tester.tap(find.text('本地模型配置'));
      await drain();
      final restoredModel = tester
          .widget<LocalModelSettingsPage>(find.byType(LocalModelSettingsPage))
          .controller;
      expect(restoredModel.saved!.model, 'root-fixture-model');
      expect(restoredModel.saved!.apiKey, 'root-fixture-key');
      expect(restoredModel.dirty, false);
      await tester.binding.handlePopRoute();
      await drain();
      await tester.binding.handlePopRoute();
      await drain();

      final modelScope = jsonDecode(restoredModel.vault.key) as List;
      final bindingKey = jsonEncode(['bookstark.ai-binding-v1', modelScope[1]]);
      const secure = FlutterSecureStorage(
        aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
      );
      await secure.write(key: bindingKey, value: 'corrupt');

      final assistantButton = find.widgetWithText(OutlinedButton, '打开 AI 助手');
      await tester.scrollUntilVisible(
        assistantButton,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(assistantButton);
      await drain();
      expect(find.text('会话记录需要恢复'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '返回'));
      await drain();
      expect(await secure.read(key: bindingKey), 'corrupt');
      await tester.tap(assistantButton);
      await drain();
      await tester.tap(find.text('建立空白会话'));
      await drain();
      final assistantPage = tester.widget<AssistantPage>(
        find.byType(AssistantPage),
      );
      expect(assistantPage.local, isTrue);
      expect(assistantPage.modelLabel, 'root-fixture-model');
      expect(assistantPage.knowledgeGranted, isFalse);
      expect(assistantPage.repository, isA<LocalAssistantRepository>());
      final assistantSession = await assistantPage.repository.open();
      expect((await assistantPage.vault!.load())!.session, assistantSession.id);
      final localAssistant =
          assistantPage.repository as LocalAssistantRepository;
      final proposal = await localAssistant.draftLedger!.propose(
        LocalAssistantDraftPayload.note(
          title: 'AI proposed note',
          content: '# Proposal',
        ),
      );
      final editOpened = assistantPage.onEditLocalDraft!(proposal.id);
      unawaited(editOpened);
      await drain();
      expect(find.byType(NoteEditorPage), findsOneWidget);
      final content = find.widgetWithText(TextField, 'Markdown…');
      await tester.enterText(content, '﻿# Edited in real root');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await drain();
      final draftSaved = (await localAssistant.draftLedger!.load()).single;
      expect(draftSaved.resourceId, isNotNull);
      final sqlNote = await LocalNotesRepository(
        localAssistant.knowledge.store,
      ).read(draftSaved.resourceId!);
      expect(sqlNote.content, '﻿# Edited in real root');
      final db = await localAssistant.knowledge.store.database;
      expect(
        (await db.query(
          'assistant_creation_receipts',
          where: 'creation_key=?',
          whereArgs: [proposal.id],
        )).single['resource_id'],
        draftSaved.resourceId,
      );
      Navigator.of(tester.element(find.byType(NoteEditorPage))).pop();
      await drain();
      await editOpened;
      expect(find.byType(AssistantPage), findsOneWidget);
      await assistantPage.onForgetLocalDraft!(proposal.id);
      expect(await localAssistant.draftLedger!.load(), isEmpty);
      expect(
        (await db.query(
          'assistant_creation_receipts',
          where: 'creation_key=?',
          whereArgs: [proposal.id],
        )).single['resource_id'],
        draftSaved.resourceId,
      );
      expect(
        (await LocalNotesRepository(
          localAssistant.knowledge.store,
        ).read(draftSaved.resourceId!)).content,
        '﻿# Edited in real root',
      );

      final sourceOpened = assistantPage.onOpenSource!({
        'kind': 'note',
        'id': articleId,
        'url': 'https://ignored.invalid',
      });
      unawaited(sourceOpened);
      await drain();
      expect(find.byType(LocalComplexNotePage), findsOneWidget);
      expect(find.byType(NoteEditorPage), findsNothing);
      Navigator.of(tester.element(find.byType(LocalComplexNotePage))).pop();
      await drain();
      await sourceOpened;
      expect(find.byType(AssistantPage), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await drain();

      final articles = find.widgetWithText(FilledButton, '文章');
      await tester.scrollUntilVisible(
        articles,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(articles);
      await tester.pumpAndSettle();
      await tester.tap(articles);
      await drain();
      expect(find.byType(NotesPage), findsOneWidget);
      expect(
        tester.widget<NotesPage>(find.byType(NotesPage)).collection,
        NoteCollection.article,
      );
      await tester.tap(find.byTooltip('新建文章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown 文章'));
      await drain();
      expect(find.byType(LocalArticleCreatePage), findsOneWidget);
      expect(find.byType(NoteEditorPage), findsNothing);
      final creationPage = tester.widget<LocalArticleCreatePage>(
        find.byType(LocalArticleCreatePage),
      );
      expect(
        creationPage.controller.draft.document.kind,
        ComplexEditorKind.markdown,
      );
      expect(creationPage.controller.record.pending, isFalse);
      // Plugin unavailable here: no source-ready or SQL creation claim.
      expect(creationPage.controller.created, isNull);
      await tester.binding.handlePopRoute();
      await drain();
      expect(find.byType(LocalArticleCreatePage), findsNothing);
      expect(find.byType(NotesPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(NotesPage))).pop();
      await drain();
      final bookmarks = find.widgetWithText(FilledButton, '书签');
      await tester.scrollUntilVisible(
        bookmarks,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(bookmarks);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(bookmarks).onPressed, isNotNull);
      await tester.tap(bookmarks);
      await drain();
      expect(find.text('真实本地书签'), findsOneWidget);
      expect(find.byType(BookmarksPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(BookmarksPage))).pop();
      await drain();
      final navigation = find.widgetWithText(FilledButton, '导航');
      await tester.scrollUntilVisible(
        navigation,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(navigation);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(navigation).onPressed, isNotNull);
      await tester.tap(navigation);
      await drain();
      expect(find.text('真实本地书签'), findsOneWidget);
      expect(find.text('当前显示1条 · 已加载1条'), findsOneWidget);
      expect(find.byType(NavigationPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(NavigationPage))).pop();
      await drain();
      final topics = find.widgetWithText(FilledButton, '主题');
      await tester.scrollUntilVisible(
        topics,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(topics);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(topics).onPressed, isNotNull);
      await tester.tap(topics);
      await drain();
      expect(find.byType(TopicsPage), findsOneWidget);
      await tester.tap(find.text('真实本地主题'));
      await drain();
      expect(find.byType(TopicDetailPage), findsOneWidget);
      expect(
        tester.widget<TopicDetailPage>(find.byType(TopicDetailPage)).topicId,
        topicId,
      );
      expect(find.text('原生小结'), findsOneWidget);
      await tester.tap(find.text('资料5'));
      await drain();
      Future<void> source(String title, Type type) async {
        await tester.scrollUntilVisible(
          find.text(title),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await drain();
        expect(find.byType(type), findsOneWidget);
      }

      Future<void> back(Type type) async {
        Navigator.of(tester.element(find.byType(type))).pop();
        await drain();
      }

      await source('真实本地笔记', NoteEditorPage);
      expect(
        tester.widget<NoteEditorPage>(find.byType(NoteEditorPage)).note.id,
        noteId,
      );
      expect(
        tester.widget<NoteEditorPage>(find.byType(NoteEditorPage)).collection,
        NoteCollection.note,
      );
      await back(NoteEditorPage);
      await source('真实本地文章', LocalComplexNotePage);
      final articlePage = tester.widget<LocalComplexNotePage>(
        find.byType(LocalComplexNotePage),
      );
      expect(articlePage.controller.baseline.id, articleId);
      expect(articlePage.controller.baseline.collection, 'article');
      expect(
        articlePage.controller.edit.document.kind,
        ComplexEditorKind.markdown,
      );
      expect(find.byType(NoteEditorPage), findsNothing);
      await back(LocalComplexNotePage);
      await source('源书籍', DocumentReaderPage);
      expect(
        tester
            .widget<DocumentReaderPage>(find.byType(DocumentReaderPage))
            .documentId,
        documentId,
      );
      expect(find.text('文档正文'), findsOneWidget);
      await back(DocumentReaderPage);
      await source('真实本地待办', TaskEditorPage);
      expect(
        tester.widget<TaskEditorPage>(find.byType(TaskEditorPage)).task.id,
        taskId,
      );
      await back(TaskEditorPage);
      await source('真实本地书签', BookmarkEditorPage);
      final bookmark = tester
          .widget<BookmarkEditorPage>(find.byType(BookmarkEditorPage))
          .bookmark;
      expect(bookmark.id, bookmarkId);
      expect(bookmark.navVisible, isTrue);
      expect(bookmark.labels, ['a,b', ' 保留 ', '贯通标签']);

      await back(BookmarkEditorPage);
      await back(TopicDetailPage);
      await back(TopicsPage);
      final labels = find.widgetWithText(FilledButton, '标签管理');
      await tester.scrollUntilVisible(
        labels,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(labels);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(labels).onPressed, isNotNull);
      await tester.tap(labels);
      await drain();
      expect(find.byType(LabelsPage), findsOneWidget);
      await tester.ensureVisible(find.text('贯通标签'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('贯通标签'));
      await drain();
      expect(find.byType(LabelDetailPage), findsOneWidget);
      Future<void> labelSource(String subtitle, Type type) async {
        final card = find
            .ancestor(of: find.text(subtitle), matching: find.byType(Card))
            .first;
        await tester.scrollUntilVisible(
          find.text(subtitle),
          200,
          scrollable: find
              .descendant(
                of: find.byType(LabelDetailPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final button = find.descendant(
          of: card,
          matching: find.byTooltip('打开资源'),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await drain();
        expect(find.byType(type), findsOneWidget);
      }

      await labelSource('书籍 · ID $bookId', ChaptersPage);
      await back(ChaptersPage);
      await labelSource('笔记/文章 · ID $noteId', NoteEditorPage);
      expect(
        tester.widget<NoteEditorPage>(find.byType(NoteEditorPage)).collection,
        NoteCollection.note,
      );
      await back(NoteEditorPage);
      await labelSource('笔记/文章 · ID $articleId', LocalComplexNotePage);
      expect(
        tester
            .widget<LocalComplexNotePage>(find.byType(LocalComplexNotePage))
            .controller
            .baseline
            .collection,
        'article',
      );
      expect(find.byType(NoteEditorPage), findsNothing);
      await back(LocalComplexNotePage);
      await labelSource('书签 · ID $bookmarkId', BookmarkEditorPage);
      await back(BookmarkEditorPage);
      await labelSource('文档 · ID $documentId', DocumentReaderPage);
      expect(
        tester
            .widget<DocumentReaderPage>(find.byType(DocumentReaderPage))
            .documentId,
        documentId,
      );
      await back(DocumentReaderPage);
      final labelId = tester
          .widget<LabelDetailPage>(find.byType(LabelDetailPage))
          .labelId;
      await back(LabelDetailPage);
      await back(LabelsPage);
      final search = find.widgetWithText(OutlinedButton, '全局搜索');
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(search).onPressed, isNotNull);
      await tester.tap(search);
      await drain();
      expect(find.byType(SearchPage), findsOneWidget);
      Future<void> query(String value) async {
        final scroll = find
            .descendant(
              of: find.byType(SearchPage),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), value);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await drain();
      }

      Future<void> searchSource(String key, Type type) async {
        final scroll = find
            .descendant(
              of: find.byType(SearchPage),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        final card = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(card, 200, scrollable: scroll);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await drain();
        expect(find.byType(type), findsOneWidget);
      }

      await query('真实');
      await searchSource('search-blog-$noteId', NoteEditorPage);
      expect(
        tester.widget<NoteEditorPage>(find.byType(NoteEditorPage)).collection,
        NoteCollection.note,
      );
      await back(NoteEditorPage);
      await searchSource('search-blog-$articleId', LocalComplexNotePage);
      expect(
        tester
            .widget<LocalComplexNotePage>(find.byType(LocalComplexNotePage))
            .controller
            .baseline
            .collection,
        'article',
      );
      expect(find.byType(NoteEditorPage), findsNothing);
      await back(LocalComplexNotePage);
      await searchSource('search-bookmark-$bookmarkId', BookmarkEditorPage);
      await back(BookmarkEditorPage);
      await searchSource('search-task-$taskId', TaskEditorPage);
      await back(TaskEditorPage);
      await searchSource('search-topic-$topicId', TopicDetailPage);
      expect(find.byType(TopicsPage), findsNothing);
      await back(TopicDetailPage);
      await query('源书籍');
      await searchSource('search-book-$bookId', ChaptersPage);
      await back(ChaptersPage);
      await searchSource('search-document-$documentId', DocumentReaderPage);
      await back(DocumentReaderPage);
      await query('贯通');
      await searchSource('search-label-$labelId', LabelDetailPage);
      expect(find.byType(LabelsPage), findsNothing);
      await back(LabelDetailPage);
      await back(SearchPage);
      final imagesButton = find.widgetWithText(FilledButton, '图片库');
      await tester.scrollUntilVisible(
        imagesButton,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(imagesButton);
      await drain();
      await tester.tap(imagesButton);
      await drain();
      expect(find.byType(ImagesPage), findsOneWidget);
      final image = find.byKey(const ValueKey('managed-image-1'));
      await tester.scrollUntilVisible(
        image,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ImagesPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(image);
      await drain();
      await tester.tap(image);
      await drain();
      expect(find.byType(ImagePreviewPage), findsOneWidget);
      final remove = find.text('删除图片');
      await tester.scrollUntilVisible(
        remove,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ImagePreviewPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(remove);
      await drain();
      await tester.tap(remove);
      await drain();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await drain();
      expect(find.byType(ImagePreviewPage), findsNothing);
      expect(find.byType(ImagesPage), findsOneWidget);
      expect(find.text('当前筛选没有图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await back(ImagesPage);
      final filesButton = find.widgetWithText(FilledButton, '文件');
      await tester.scrollUntilVisible(
        filesButton,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(filesButton);
      await drain();
      await tester.tap(filesButton);
      await drain();
      expect(find.byType(DrivePage), findsOneWidget);
      await drain();
      final fileRow = find.text('真实文件.md');
      for (var i = 0; i < 10 && fileRow.evaluate().isEmpty; i++) {
        await drain();
      }
      expect(
        fileRow,
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      await tester.ensureVisible(fileRow);
      await drain();
      await tester.tap(find.byTooltip('真实文件.md 操作'));
      await drain();
      await tester.tap(find.text('编辑 UTF-8 文本'));
      await drain();
      expect(find.byType(FileEditorPage), findsOneWidget);
      final contentInput = find.byKey(const ValueKey('file-content-input'));
      for (var i = 0; i < 4 && contentInput.evaluate().isEmpty; i++) {
        await drain();
      }
      expect(
        contentInput,
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      expect(
        tester.widget<TextField>(contentInput).controller!.text,
        '# 本地文件正文',
      );
      await tester.enterText(contentInput, '# 从首页保存的文件');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await drain();
      for (
        var i = 0;
        i < 8 && find.textContaining('未保存').evaluate().isNotEmpty;
        i++
      ) {
        await drain();
      }
      expect(
        find.textContaining('未保存'),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      final closeFile = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '关闭',
      );
      for (
        var i = 0;
        i < 8 && tester.widget<IconButton>(closeFile).onPressed == null;
        i++
      ) {
        await drain();
      }
      expect(tester.widget<IconButton>(closeFile).onPressed, isNotNull);
      await tester.tap(closeFile);
      await drain();
      expect(
        find.byType(DrivePage),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      await back(DrivePage);
      final createResource = find.widgetWithText(FilledButton, '新建资源');
      await tester.scrollUntilVisible(
        createResource,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(createResource);
      await tester.pumpAndSettle();
      await tester.tap(createResource);
      await drain();
      expect(find.byType(ResourceCreatePage), findsOneWidget);
      final documentKind = find.text('文档');
      await tester.scrollUntilVisible(
        documentKind,
        160,
        scrollable: find
            .descendant(
              of: find.byType(ResourceCreatePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(documentKind);
      await tester.pumpAndSettle();
      await tester.tap(documentKind);
      await drain();
      expect(find.byType(DocumentCreatePage), findsOneWidget);
      await tester.tap(find.text('请选择位置'));
      await drain();
      expect(find.byType(DocumentLocationPage), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '请选择书籍'));
      await drain();
      await tester.tap(find.text('源书籍'));
      await drain();
      await tester.tap(find.text('选择此位置'));
      await drain();
      await tester.enterText(find.byType(TextField), '首页创建的文档 📚');
      await tester.pump();
      await tester.tap(find.text('创建并编辑'));
      await drain();
      for (
        var index = 0;
        index < 4 && find.byType(NoteEditorPage).evaluate().isEmpty;
        index++
      ) {
        await drain();
      }
      expect(find.byType(NoteEditorPage), findsOneWidget);
      final createdEditor = tester.widget<NoteEditorPage>(
        find.byType(NoteEditorPage),
      );
      createdDocumentId = createdEditor.note.id!;
      expect(createdEditor.documentPath, contains('首页创建的文档 📚'));
      await back(NoteEditorPage);
      await drain();
      expect(find.byType(DocumentCreatePage), findsNothing);
      final recentCreated = find.widgetWithText(ListTile, '首页创建的文档 📚');
      for (
        var index = 0;
        index < 10 && recentCreated.evaluate().isEmpty;
        index++
      ) {
        await drain();
      }
      await tester.scrollUntilVisible(
        recentCreated,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(recentCreated);
      await tester.pumpAndSettle();
      await tester.tap(recentCreated);
      await drain();
      expect(
        tester
            .widget<DocumentReaderPage>(find.byType(DocumentReaderPage))
            .documentId,
        createdDocumentId,
      );
      await back(DocumentReaderPage);
      await tester.pumpWidget(const SizedBox());
      await drain();
      await tester.runAsync(() async {
        final checkStore = LocalStore(
          path: '${directory.path}/bookstark-flutter.db',
          factory: databaseFactoryFfiNoIsolate,
        );
        final createdDocument = await LocalDocumentsRepository(
          checkStore,
        ).read(createdDocumentId);
        expect(createdDocument.bookId, bookId);
        expect(createdDocument.parentId, 0);
        expect(createdDocument.name, '首页创建的文档 📚');
        final checkDrive = LocalDriveRepository(
          checkStore,
          Directory('${directory.path}/drive-blobs'),
        );
        expect(
          (await checkDrive.readText(
            (await checkDrive.lookup('真实文件.md'))!,
          )).content,
          '# 从首页保存的文件',
        );
        checkDrive.dispose();
        await checkStore.close();
      });
    },
  );
}
