import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/core/search_matching.dart';
import 'package:bookstark_flutter/core/local_topics_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late LocalStore store;
  late LocalSearchRepository repo;
  setUp(() {
    store = LocalStore(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalSearchRepository(store);
  });
  tearDown(() async => store.close());
  test(
    'real SQLite returns all seven groups with typed IDs and original blog collection',
    () async {
      const q = '搜索标记';
      final db = await store.database;
      await store.createNote(q, '正文', labels: [q]);
      await store.createNote('$q文章', '文章正文', collection: 'article');
      final book = await db.insert('books', {
        'book_name': q,
        'identify': 'book',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      await db.insert('documents', {
        'book_id': book,
        'document_name': q,
        'identify': 'doc',
        'markdown': '文档正文',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      await db.insert('bookmarks', {
        'title': q,
        'url': 'https://example.test',
        'create_time': 1,
        'modify_time': 1,
      });
      await db.insert('tasks', {
        'content': q,
        'due_date': '2026-11-08',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      await LocalTopicsRepository(
        store,
      ).save(const TopicItem(title: '主题', question: q));
      final result = await repo.search(q);
      expect(result.loaded, 8);
      expect(result.groups.values.every((rows) => rows.isNotEmpty), isTrue);
      expect(
        result.groups[SearchKind.blog]!.map((hit) => hit.blogType).toSet(),
        {'note', 'article'},
      );
      expect(result.all.map((hit) => hit.key).toSet().length, 8);
    },
  );
  test('literal wildcard characters never expand SQLite LIKE search', () async {
    await store.createNote('字面100%_\\保留', '正文');
    await store.createNote('普通100xy', '正文');
    final result = await repo.search('%_\\');
    expect(result.groups[SearchKind.blog]!.single.title, '字面100%_\\保留');
    expect(matchesSearchWord('needle_suffix', 'needle'), isFalse);
    expect(matchesSearchWord('a needle!', 'needle'), isTrue);
    final snippet = searchSnippet(
      '${List.filled(180, '📚').join()}阅读${List.filled(180, '📖').join()}',
      '阅读',
    );
    expect(snippet, contains('阅读'));
    expect(snippet.runes.length, lessThanOrEqualTo(156));
    expect(snippet.contains('\uFFFD'), isFalse);
  });
  test(
    'encrypted content and deleted-parent documents do not leak into results',
    () async {
      await store.createNote('受保护', 'ENC:v1:private-secret');
      expect((await repo.search('private')).groups[SearchKind.blog], isEmpty);
      expect(
        (await repo.search('受保护')).groups[SearchKind.blog]!.single.snippet,
        isEmpty,
      );
      final db = await store.database;
      final book = await db.insert('books', {
        'book_name': '已删除书籍',
        'identify': 'gone',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
        'deleted': 1,
      });
      await db.insert('documents', {
        'book_id': book,
        'document_name': '隐藏正文',
        'identify': 'orphan',
        'markdown': '隐藏正文',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      expect((await repo.search('隐藏正文')).groups[SearchKind.document], isEmpty);
    },
  );
  test(
    'ASCII boundary filtering after twenty candidates does not fabricate more pages',
    () async {
      final db = await store.database;
      for (var index = 0; index < 21; index++) {
        await db.insert('tasks', {
          'content': index == 0 ? 'needle' : 'needleSuffix',
          'due_date': '2026-11-08',
          'create_time': '2026-11-04',
          'modify_time': index.toString().padLeft(4, '0'),
        });
      }
      final result = await repo.search('needle');
      expect(result.groups[SearchKind.task], isEmpty);
      final topics = LocalTopicsRepository(store);
      final id = await topics.save(const TopicItem(title: '普通主题'));
      await topics.saveSummary(TopicSummary(topicId: id, content: '# 小结专用关键字'));
      final found = await repo.search('小结专用关键字');
      expect(found.groups[SearchKind.topic]!.single.id, id);
      expect(
        found.groups[SearchKind.topic]!.single.snippet,
        contains('小结专用关键字'),
      );
    },
  );
  test(
    'large bodies retain tail and chunk-boundary whole-word matches',
    () async {
      // Cross a 256 KiB byte boundary, then put another match beyond the
      // Android CursorWindow-sized region and the complex-editor 20 MiB limit.
      // Existing Markdown search remains unrestricted. FFI verifies semantics only.
      final body =
          '${'x' * (256 * 1024 - 3)} needle ${'📚' * 5500000} tailword!';
      final note = await store.createNote('Large', body);
      await store.createNote(
        'Substring only',
        '${'x' * 2200000} tailwordSuffix',
      );
      final db = await store.database;
      final book = await db.insert('books', {
        'book_name': 'Large book',
        'identify': 'large-book',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      final document = await db.insert('documents', {
        'book_id': book,
        'document_name': 'Large document',
        'identify': 'large-doc',
        'markdown': body,
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      for (final query in ['needle', 'tailword']) {
        final found = await repo.search(query);
        expect(found.groups[SearchKind.blog]!.map((hit) => hit.id), [note]);
        expect(found.groups[SearchKind.document]!.single.id, document);
        for (final kind in [SearchKind.blog, SearchKind.document]) {
          final snippet = found.groups[kind]!.single.snippet;
          expect(snippet, contains(query));
          expect(snippet, isNot(contains('\uFFFD')));
          expect(snippet.runes.length, lessThanOrEqualTo(156));
        }
      }
      expect((await store.readNote(note))['content'], body);
    },
  );
}
