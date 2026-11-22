// In-memory visual/test fixture only. Never imported by production lib/.
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';

class BooksFixture implements BooksRepository {
  final records = <int, BookItem>{
    1: BookItem(
      id: 1,
      name: '阅读的方法',
      description: '把零散的阅读整理成系统，记录观点和实践。',
      labels: const ['阅读', '学习'],
      labelText: '阅读,学习',
      documentCount: 7,
      modifiedAt: DateTime(2026, 11, 4),
    ),
    2: BookItem(
      id: 2,
      name: '写作与思考',
      description: '让笔记成为表达的起点',
      labels: const ['写作'],
      labelText: '写作',
      modifiedAt: DateTime(2026, 11, 3),
    ),
    3: BookItem(
      id: 3,
      name: '技术札记',
      description: '记录理解过的问题与解决过程',
      labels: const ['技术'],
      labelText: '技术',
      modifiedAt: DateTime(2026, 11, 2),
    ),
  };
  @override
  Future<BooksPageResult> list({String keyword = '', int page = 1}) async {
    final items = records.values
        .where(
          (item) =>
              item.name.contains(keyword) ||
              item.labels.any((label) => label.contains(keyword)),
        )
        .toList();
    return BooksPageResult(
      items.skip((page - 1) * 12).take(12).toList(),
      items.length,
      page,
      12,
    );
  }

  @override
  Future<BookItem> read(int id) async => records[id]!;
  @override
  Future<int> save(BookItem book) async {
    final id =
        book.id ?? (records.keys.fold<int>(0, (a, b) => a > b ? a : b) + 1);
    records[id] = book.copyWith(id: id);
    return id;
  }

  @override
  Future<void> remove(int id) async {
    records.remove(id);
  }
}

class LabelsFixture implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => page == 1
      ? [
          '阅读',
          '学习',
          '写作',
          '技术',
          ' 保留空白 ',
        ].where((name) => name.contains(keyword)).toList()
      : [];
}

class DocumentsFixture implements DocumentsRepository {
  static const body =
      '# 选择适合自己的书\n\n阅读不必从最难的书开始。先找到一个你真正想解决的问题，再挑选能帮助你理解它的书。\n\n## 三个选择标准\n\n- 与当前的问题有关\n- 能读懂，也有一点挑战\n- 愿意读完后付诸实践\n\n> 读书的价值，在于让生活发生一点改变。';
  final records = <int, DocumentItem>{
    1: const DocumentItem(
      id: 1,
      bookId: 1,
      name: '第一章：建立阅读习惯',
      markdown: '# 建立阅读习惯',
    ),
    2: const DocumentItem(
      id: 2,
      bookId: 1,
      parentId: 1,
      name: '选择适合自己的书',
      markdown: body,
      modifiedAt: '2026-11-04 12:00',
    ),
    3: const DocumentItem(
      id: 3,
      bookId: 1,
      parentId: 1,
      name: '每天二十分钟',
      markdown: '# 每天二十分钟\n\n为阅读留出固定的时间。',
    ),
    4: const DocumentItem(
      id: 4,
      bookId: 1,
      name: '第二章：把知识用起来',
      markdown: '# 把知识用起来',
    ),
    5: const DocumentItem(id: 5, bookId: 1, parentId: 4, name: '记录一个观点'),
    6: const DocumentItem(id: 6, bookId: 1, parentId: 4, name: '从一个行动开始'),
    7: const DocumentItem(id: 7, bookId: 1, name: '附录：阅读清单'),
  };
  int reads = 0, removes = 0;
  @override
  Future<List<DocumentNode>> tree(int bookId) async {
    List<DocumentNode> children(int parent) => records.values
        .where((item) => item.bookId == bookId && item.parentId == parent)
        .map(
          (item) => DocumentNode(
            id: item.id,
            name: item.name,
            parentId: parent,
            type: item.type,
            children: children(item.id),
          ),
        )
        .toList();
    return children(0);
  }

  @override
  Future<DocumentItem> read(int id) async {
    reads++;
    final item = records[id]!;
    final ordered = flattenDocuments(
      await tree(item.bookId),
    ).map((node) => node.id).toList();
    final index = ordered.indexOf(id);
    return DocumentItem(
      id: id,
      bookId: item.bookId,
      name: item.name,
      parentId: item.parentId,
      markdown: item.markdown,
      type: item.type,
      modifiedAt: item.modifiedAt,
      previousId: index > 0 ? ordered[index - 1] : 0,
      nextId: index + 1 < ordered.length ? ordered[index + 1] : 0,
    );
  }

  @override
  Future<DocumentItem> create(
    int bookId,
    String name, {
    int parentId = 0,
  }) async {
    validateDocumentName(name);
    final id = records.keys.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    return records[id] = DocumentItem(
      id: id,
      bookId: bookId,
      name: name,
      parentId: parentId,
    );
  }

  void _replace(int id, {String? name, String? markdown, int? parentId}) {
    final item = records[id]!;
    records[id] = DocumentItem(
      id: id,
      bookId: item.bookId,
      name: name ?? item.name,
      markdown: markdown ?? item.markdown,
      parentId: parentId ?? item.parentId,
      type: item.type,
    );
  }

  @override
  Future<void> rename(int id, String name) async {
    _replace(id, name: name);
  }

  @override
  Future<void> saveMarkdown(int id, String markdown) async {
    _replace(id, markdown: markdown);
  }

  @override
  Future<void> move(int bookId, int id, int parentId, {int order = 0}) async {
    _replace(id, parentId: parentId);
  }

  @override
  Future<void> reorder(int id, String direction) async {}
  @override
  Future<void> remove(int id) async {
    removes++;
    records.remove(id);
  }
}
