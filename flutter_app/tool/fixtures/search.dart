// Private test fixture, excluded from lib/main.dart.
import 'package:bookstark_flutter/core/search_repository.dart';

class SearchFixture implements SearchRepository {
  SearchFixture({bool sample = true}) {
    if (!sample) return;
    groups.addAll({
      SearchKind.document: [
        for (var i = 1; i <= 3; i++)
          SearchHit(
            kind: SearchKind.document,
            id: i,
            title: i == 1 ? '阅读的起点' : '阅读文档$i',
            bookName: '阅读的方法',
            snippet: '选择一个真正想解决的问题，再开始阅读。',
          ),
      ],
      SearchKind.blog: [
        for (var i = 1; i <= 5; i++)
          SearchHit(
            kind: SearchKind.blog,
            id: i,
            title: i == 1 ? '阅读的意义' : '阅读记录$i',
            blogType: i <= 3 ? 'note' : 'article',
            snippet: '把阅读变成理解，再把理解变成行动。',
          ),
      ],
      SearchKind.book: [
        for (var i = 1; i <= 2; i++)
          SearchHit(
            kind: SearchKind.book,
            id: i,
            title: '阅读的方法$i',
            description: '围绕问题进行阅读。',
            documentCount: 3,
          ),
      ],
      SearchKind.bookmark: [
        for (var i = 1; i <= 2; i++)
          SearchHit(
            kind: SearchKind.bookmark,
            id: i,
            title: '阅读参考$i',
            url: 'https://example.invalid/reading/$i',
            description: '阅读与知识整理的参考资料。',
          ),
      ],
      SearchKind.task: [
        for (var i = 1; i <= 2; i++)
          SearchHit(
            kind: SearchKind.task,
            id: i,
            title: '每周阅读回顾$i',
            dueDate: '2026-11-08',
            done: i == 2,
          ),
      ],
      SearchKind.topic: [
        const SearchHit(
          kind: SearchKind.topic,
          id: 1,
          title: '阅读与知识整理',
          question: '如何把阅读变成行动？',
          itemCount: 3,
        ),
      ],
      SearchKind.label: [
        const SearchHit(kind: SearchKind.label, id: 1, title: '阅读'),
        const SearchHit(kind: SearchKind.label, id: 2, title: '阅读方法'),
      ],
    });
  }
  final groups = <SearchKind, List<SearchHit>>{};
  final calls = <String>[];
  Future<SearchResults> Function(String query)? searchOverride;
  @override
  Future<SearchResults> search(String query) async {
    final q = normalizeSearchQuery(query);
    calls.add(q);
    if (searchOverride != null) return searchOverride!(q);
    return SearchResults(
      query: q,
      groups: {
        for (final entry in groups.entries)
          entry.key: entry.value
              .where(
                (hit) =>
                    '${hit.title} ${hit.snippet} ${hit.description} ${hit.question} ${hit.url}'
                        .toLowerCase()
                        .contains(q.toLowerCase()),
              )
              .take(20)
              .toList(),
      },
    );
  }
}
