import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BatchArticles implements NotesRepository, FilteredNotesRepository {
  final records = <int, Note>{
    1: const Note(id: 1, title: '第一篇文章', content: '完整正文', labels: ['阅读']),
    2: const Note(id: 2, title: '第二篇文章', content: '保留失败项', labels: ['工作']),
  };
  final removed = <int>[];
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      listFiltered(keyword: keyword, page: page);
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async => page == 1
      ? records.values
            .where((note) => label.isEmpty || note.labels.contains(label))
            .toList()
      : [];
  @override
  Future<void> remove(int id) async {
    removed.add(id);
    if (id == 2) throw StateError('模拟权限变化');
    records.remove(id);
  }

  @override
  Future<Note> read(int id) async => records[id]!;
  @override
  Future<int> save(Note note) async => note.id ?? 3;
}

class PagedArticles extends BatchArticles {
  PagedArticles() {
    records.clear();
    for (var id = 1; id <= 45; id++) {
      records[id] = Note(id: id, title: 'Article $id', content: 'Body');
    }
  }
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async => records.values.skip((page - 1) * 20).take(20).toList();
  @override
  Future<void> remove(int id) async {
    removed.add(id);
    if (id == 35) throw StateError('Page-two item failed');
    records.remove(id);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  test(
    'v2 migration retains old notes and isolates article IDs, labels and soft deletion',
    () async {
      final dir = await Directory.systemTemp.createTemp('bookstark-articles-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.db';
      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              "CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, labels TEXT NOT NULL DEFAULT '[]')",
            );
          },
        ),
      );
      final oldId = await old.insert('notes', {
        'title': '旧笔记',
        'content': '不能丢失',
        'updated_at': 1,
        'labels': '["阅读"]',
      });
      await old.close();
      final store = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(store.close);
      final notes = LocalNotesRepository(store);
      final articles = LocalNotesRepository(
        store,
        collection: NoteCollection.article,
      );
      final articleId = await articles.save(
        const Note(title: '新文章', content: '# 完整内容', labels: ['阅读', '100%']),
      );
      await articles.save(
        const Note(title: '其他文章', content: '非匹配', labels: ['阅读笔记']),
      );
      expect((await notes.list()).single.id, oldId);
      expect((await notes.read(oldId)).content, '不能丢失');
      expect((await articles.list()).length, 2);
      expect((await articles.listFiltered(label: '阅读')).single.id, articleId);
      expect((await articles.listFiltered(label: '100%')).single.id, articleId);
      await expectLater(articles.read(oldId), throwsStateError);
      await expectLater(
        notes.save(Note(id: articleId, title: '误写', content: '错误集合')),
        throwsStateError,
      );
      await expectLater(articles.remove(oldId), throwsStateError);
      expect((await notes.read(oldId)).content, '不能丢失');
      await expectLater(
        articles.save(const Note(title: '新文章', content: '不得覆盖')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await articles.read(articleId)).content, '# 完整内容');
      await articles.remove(articleId);
      expect((await articles.list()).length, 1);
      expect((await notes.list()).single.id, oldId);
    },
  );
  test(
    'remote articles submit actual type and filter across server pages',
    () async {
      final requests = <http.Request>[];
      final client = BookstarkClient(
        'https://example.test/prefix',
        transport: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=fixture; Path=/'},
            );
          }
          if (request.method == 'GET') return http.Response('{"data":[]}', 200);
          return http.Response(
            request.method == 'POST' ? '{"blog_id":9}' : '{}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repository = RemoteNotesRepository(
        client,
        collection: NoteCollection.article,
      );
      await repository.listFiltered(
        page: 3,
        label: '阅读 & 工作',
        pinned: '1',
        keyword: '中文',
      );
      expect(
        requests.first.url.queryParameters,
        containsPair('type', 'article'),
      );
      expect(
        requests.first.url.queryParameters,
        containsPair('label', '阅读 & 工作'),
      );
      expect(requests.first.url.queryParameters, containsPair('page', '3'));
      expect(requests.first.url.queryParameters, containsPair('pinned', '1'));
      await repository.save(const Note(title: '文章标题', content: '完整正文'));
      final body =
          jsonDecode(
                requests
                    .singleWhere((request) => request.method == 'POST')
                    .body,
              )
              as Map;
      expect(body['blog_type'], 'article');
      expect(body['visibility'], 0);
      expect(body['editor_type'], 'markdown');
    },
  );
  testWidgets(
    'batch trash confirms once and retains failed article selection with error',
    (tester) async {
      final repository = BatchArticles();
      await tester.pumpWidget(
        MaterialApp(
          home: NotesPage(
            repository: repository,
            collection: NoteCollection.article,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选已加载'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '移到回收站'));
      await tester.pumpAndSettle();
      expect(repository.removed, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '移到回收站'));
      await tester.pumpAndSettle();
      expect(repository.removed, [1, 2]);
      expect(find.text('第一篇文章'), findsNothing);
      expect(find.text('第二篇文章'), findsOneWidget);
      expect(find.textContaining('模拟权限变化'), findsOneWidget);
      expect(find.text('已选1条（已加载）'), findsOneWidget);
    },
  );
  testWidgets('article label filtering can clear without changing collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotesPage(
          repository: BatchArticles(),
          collection: NoteCollection.article,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '准确标签名'), '阅读');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('第一篇文章'), findsOneWidget);
    expect(find.text('第二篇文章'), findsNothing);
    expect(find.text('知识库 · 文章'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '阅读'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '全部标签'));
    await tester.pumpAndSettle();
    expect(find.text('第二篇文章'), findsOneWidget);
  });
  testWidgets(
    'English article controls remain scrollable with keyboard and double text',
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
          home: NotesPage(
            repository: BatchArticles(),
            collection: NoteCollection.article,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'batch failure on a later page remains visible and selected after reload',
    (tester) async {
      final repository = PagedArticles();
      await tester.pumpWidget(
        MaterialApp(
          home: NotesPage(
            repository: repository,
            collection: NoteCollection.article,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('加载更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      final target = find.text('Article 35');
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      final trash = find.byTooltip('批量移到回收站');
      await tester.ensureVisible(trash);
      await tester.pumpAndSettle();
      await tester.tap(trash);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移到回收站'));
      await tester.pumpAndSettle();
      expect(repository.removed, [1, 35]);
      expect(find.text('Article 35'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Checkbox && widget.value == true,
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('已选1条（已加载）'),
        -500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 50,
      );
      await tester.pumpAndSettle();
      expect(find.text('已选1条（已加载）'), findsOneWidget);
      expect(find.textContaining('Page-two item failed'), findsOneWidget);
    },
  );
}
