import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_label_management_repository.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late LocalStore store;
  late LocalLabelManagementRepository repo;
  setUp(() {
    store = LocalStore(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalLabelManagementRepository(
      store,
      clock: () => DateTime(2026, 11, 4),
    );
  });
  tearDown(() async => store.close());
  Future<int> book() async => (await store.database).insert('books', {
    'book_name': '书籍',
    'identify': 'book',
    'labels': '[]',
    'create_time': '2026-11-04',
    'modify_time': '2026-11-04',
  });
  test(
    'document-only association is used and global unused removal preserves document',
    () async {
      final db = await store.database;
      final bid = await book();
      final did = await db.insert('documents', {
        'book_id': bid,
        'document_name': '章节',
        'identify': 'document',
        'labels': jsonEncode(['文档标签']),
        'markdown': '# 保留',
        'create_time': '2026-11-04',
        'modify_time': '2026-11-04',
      });
      final unused = await repo.save('未使用');
      final page = await repo.list(const LabelManagementQuery());
      expect(page.total, 2);
      expect(page.used, 1);
      expect(page.unused, 1);
      final used = page.items.singleWhere((row) => row.name == '文档标签');
      expect(used.bookCount + used.blogCount + used.bookmarkCount, 0);
      final detail = await repo.read(used.id);
      expect(detail.verifiedUnused, isFalse);
      expect(detail.items.single.id, did);
      expect(await repo.removeUnused(), 1);
      await expectLater(repo.read(unused.id), throwsStateError);
      expect(
        (await repo.read(used.id)).items.single.type,
        LabelResourceType.document,
      );
      expect((await db.query('documents')).single['markdown'], '# 保留');
    },
  );
  test(
    'rename and merge preserve exact labels, source content and bookmark flags',
    () async {
      final db = await store.database;
      final nid = await store.createNote(
        '私密笔记',
        'ENC:retained',
        labels: [' 阅读 ', '旧名', 'target'],
        collection: 'note',
      );
      await db.insert('bookmarks', {
        'title': '书签',
        'url': 'https://example.test',
        'labels': jsonEncode(['旧名', 'target']),
        'nav_visible': 1,
        'is_pinned': 1,
        'create_time': 1,
        'modify_time': 1,
      });
      final rows = (await repo.list(const LabelManagementQuery())).items;
      final old = rows.singleWhere((row) => row.name == '旧名'),
          target = rows.singleWhere((row) => row.name == 'target');
      await repo.save('新名', id: old.id);
      await repo.merge(target.id, [old.id]);
      final note = (await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [nid],
      )).single;
      expect(jsonDecode(note['labels'] as String), [' 阅读 ', 'target']);
      expect(note['content'], 'ENC:retained');
      expect(note['id'], nid);
      final bookmark = (await db.query('bookmarks')).single;
      expect(jsonDecode(bookmark['labels'] as String), ['target']);
      expect(bookmark['nav_visible'], 1);
      expect(bookmark['is_pinned'], 1);
      expect(
        (await repo.list(
          const LabelManagementQuery(),
        )).items.any((row) => row.name == '新名'),
        isFalse,
      );
      expect(await LocalLabelsRepository(store).search(' 阅读 '), [' 阅读 ']);
    },
  );
  test('source update failure rolls entire rename and merge back', () async {
    final db = await store.database;
    await store.createNote('笔记', '正文', labels: ['源']);
    final target = await repo.save('目标');
    final source = (await repo.list(
      const LabelManagementQuery(keyword: '源'),
    )).items.single;
    await db.execute(
      "CREATE TRIGGER reject_label_write BEFORE UPDATE OF labels ON notes BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
    );
    await expectLater(repo.save('新名称', id: source.id), throwsA(anything));
    expect((await repo.read(source.id)).label.name, '源');
    await expectLater(repo.merge(target.id, [source.id]), throwsA(anything));
    expect((await repo.read(source.id)).items.length, 1);
    expect((await repo.read(target.id)).items, isEmpty);
    expect(jsonDecode((await db.query('notes')).single['labels'] as String), [
      '源',
    ]);
  });
  test(
    'unbinding one actual resource preserves other resources and persists recommendations',
    () async {
      await store.createNote('笔记1', '一', labels: ['阅读']);
      await store.createNote('笔记2', '二', labels: ['阅读']);
      final label = (await repo.list(
        const LabelManagementQuery(),
      )).items.single;
      final refs = (await repo.read(label.id)).items;
      await repo.unbind(label.id, refs.first);
      expect((await repo.read(label.id)).items.single.id, refs.last.id);
      const settings = LabelRecommendationSettings(
        strategy: LabelRecommendationStrategy.manual,
        manualLabels: ['阅读'],
        pageSize: 3,
      );
      await repo.saveRecommendationSettings(settings);
      final restored = await LocalLabelManagementRepository(
        store,
      ).recommendationSettings();
      expect(restored.strategy, LabelRecommendationStrategy.manual);
      expect(restored.manualLabels, ['阅读']);
      expect((await repo.recommendations(restored)).single.id, label.id);
      expect(await LocalLabelsRepository(store).search('阅读'), ['阅读']);
    },
  );
}
