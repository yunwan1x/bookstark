import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/topic_resource_picker_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';

class TopicPickerFixture implements TopicResourcePickerRepository {
  Future<TopicResourceCandidatesPage> Function(
    TopicResourceType type,
    String keyword,
    int page,
    int? bookId,
  )?
  overrideList;
  @override
  Future<BooksPageResult> books({String keyword = '', int page = 1}) async =>
      BooksPageResult(
        page == 1 ? [const BookItem(id: 1, name: '阅读的方法')] : [],
        1,
        page,
        12,
      );
  @override
  Future<TopicResourceCandidatesPage> list(
    TopicResourceType type, {
    String keyword = '',
    int page = 1,
    int? bookId,
  }) async {
    if (overrideList != null) return overrideList!(type, keyword, page, bookId);
    if (page > 1) return const TopicResourceCandidatesPage([], hasMore: false);
    final notes = [
      const TopicResourceCandidate(
        id: 11,
        type: TopicResourceType.note,
        title: '阅读的意义',
        description: '把阅读变成理解，再把理解变成行动。',
      ),
      const TopicResourceCandidate(
        id: 12,
        type: TopicResourceType.note,
        title: '如何建立知识体系',
        description: '记录观点，关联已有经验。',
      ),
      const TopicResourceCandidate(
        id: 13,
        type: TopicResourceType.note,
        title: '每周回顾',
        description: '用一个问题串联本周的阅读。',
      ),
    ];
    final rows = type == TopicResourceType.note
        ? notes
        : type == TopicResourceType.document
        ? [
            const TopicResourceCandidate(
              id: 1,
              type: TopicResourceType.document,
              title: '阅读的起点',
            ),
          ]
        : [TopicResourceCandidate(id: 21, type: type, title: '${type.name}资料')];
    return TopicResourceCandidatesPage(
      rows.where((item) => item.title.contains(keyword)).toList(),
      hasMore: false,
    );
  }
}
