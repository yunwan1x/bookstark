import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';

class PublicSharesFixture implements PublicSharesRepository {
  static final server = Uri.parse('https://fixture.invalid');
  static PublicShareReference reference(String id) =>
      PublicShareReference(server, id);
  static const body = '''## 从一个问题开始

阅读不必从最难的书开始。先找到一个真正想解决的问题，再选择能帮助你理解它的书。

## 三个选择标准

- 与当前的问题有关
- 能读懂，也有一点挑战
- 愿意读完后付诸实践

> 读书的价值，在于让生活发生一点改变。
''';
  static Map<String, Object?> node(
    int id,
    int parent,
    String identify,
    String name, [
    List<Map<String, Object?>> children = const [],
  ]) => {
    'document_id': id,
    'parent_id': parent,
    'identify': identify,
    'document_name': name,
    'doc_type': 'markdown',
    'children': children,
  };
  static PublicShareDetail book() =>
      PublicShareDetail.fromJson(reference('book'), {
        'share_type': 'book',
        'share_id': 8,
        'target_id': 4,
        'share_identify': 'book',
        'has_password': false,
        'title': '把阅读变成行动',
        'author': '小林',
        'description': '从选择一本书，到建立自己的知识体系。',
        'doc_tree': [
          node(1, 0, 'start', '第一章：开始阅读', [
            node(2, 1, 'question', '从一个问题开始'),
            node(3, 1, 'choose', '选择适合自己的书'),
          ]),
          node(4, 0, 'notes', '第二章：记录与整理'),
          node(5, 0, 'end', '后记'),
        ],
      });
  @override
  Future<PublicShareDetail> load(
    PublicShareReference ref, {
    Future<void>? abortTrigger,
  }) async {
    if (ref.identify == 'book') return book();
    return PublicShareDetail.fromJson(ref, {
      'share_type': 'blog',
      'share_id': -7,
      'target_id': 7,
      'share_identify': ref.identify,
      'has_password': ref.identify == 'protected',
      'title': ref.identify == 'protected' ? '我的年度复盘' : '选择适合自己的书',
      'author': '小林',
      'share_time': '2026-11-05T08:00:00+08:00',
      'doc_type': 'markdown',
      'content': body,
    });
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (password != 'fixture-only') throw StateError('Wrong fixture password');
    return detail.unlockMarkdown(body);
  }

  @override
  Future<PublicShareChapter> chapter(
    PublicShareDetail book,
    String identify, {
    Future<void>? abortTrigger,
  }) async {
    List<PublicShareNode> flatten(List<PublicShareNode> nodes) => [
      for (final node in nodes) ...[node, ...flatten(node.children)],
    ];
    final node = flatten(
      book.nodes,
    ).singleWhere((node) => node.identify == identify);
    return PublicShareChapter(
      node: node,
      title: node.name,
      content: body,
      format: 'markdown',
      rawAvailable: false,
    );
  }
}
