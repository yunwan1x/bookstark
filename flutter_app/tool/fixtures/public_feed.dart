import 'package:bookstark_flutter/core/public_feed_models.dart';
import 'package:bookstark_flutter/core/public_feed_repository.dart';

class PublicFeedFixture implements PublicFeedRepository {
  @override
  Future<PublicFeedPageData> load(
    PublicFeedQuery query, {
    Future<void>? abortTrigger,
  }) async {
    const labels = ['', '阅读方法', '知识管理', 'Flutter'];
    final all = [
      for (var index = 0; index < 3; index++)
        PublicFeedItem(
          kind: query.kind,
          identity: '${query.kind.name}:fixture-$index',
          shareIdentify: query.kind == PublicFeedKind.bookmark
              ? null
              : 'fixture-$index',
          externalUri: query.kind == PublicFeedKind.bookmark
              ? Uri.parse('https://example.test/$index')
              : null,
          title: ['让阅读成为可持续的习惯', '建立自己的知识连接', '需要密码的阅读笔记'][index],
          author: ['林间读者', 'BookStark', '远山'][index],
          date: '2026-11-05',
          format: query.kind == PublicFeedKind.bookmark
              ? 'bookmark'
              : 'Markdown',
          locked: query.kind != PublicFeedKind.bookmark && index == 2,
          pinned: index == 0,
          excerpt: '从一个真正关心的问题开始，记录关键观点，把阅读与生活连接起来。',
          labels: [labels[index + 1]],
        ),
    ];
    return PublicFeedPageData(
      query: query,
      items: all
          .where(
            (item) =>
                (query.label.isEmpty || item.labels.contains(query.label)) &&
                (query.keyword.isEmpty || item.title.contains(query.keyword)),
          )
          .toList(),
      categories: [
        for (final label in labels)
          PublicFeedCategory(label: label, selected: label == query.label),
      ],
      previous: null,
      next: null,
    );
  }
}
