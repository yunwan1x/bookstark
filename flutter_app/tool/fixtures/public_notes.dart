import 'dart:convert';
import 'package:bookstark_flutter/core/public_notes_repository.dart';
import 'public_shares.dart';

class PublicNotesFixture implements PublicNotesRepository {
  @override
  Future<PublicNotesPageData> load(
    int page, {
    Future<void>? abortTrigger,
  }) async {
    Map<String, Object?> row(
      int id,
      String title,
      String identify, {
      bool locked = false,
      String label = '阅读',
    }) => {
      'blog_id': id,
      'blog_identify': identify,
      'blog_title': title,
      'blog_type': 'note',
      'editor_type': 'markdown',
      'visibility': 1,
      'has_password': locked,
      'is_pinned': 0,
      'modify_time': '2026-11-0${id == 1 ? 5 : 4}T12:00:00Z',
      'content_preview': id == 1
          ? '阅读不必从最难的书开始。先找到一个真正想解决的问题，再选择能帮助你理解它的书。'
          : '给自己留下十分钟，记录一次真实的尝试。慢一点，也是在前进。',
      'labels': [label],
    };
    final rows = page == 1
        ? [
            row(1, '从一个问题开始', 'reader'),
            row(2, '今天的小进步', 'note-two', label: '随想'),
            row(3, '我的年度复盘', 'protected', locked: true, label: '不得公开的标签'),
          ]
        : [];
    return parsePublicNotes(
      '<div id="publicTimeline"></div><script>var blogs = ${jsonEncode(rows)};\nvar container = document.getElementById(\'publicTimeline\');</script>',
      server: PublicSharesFixture.server,
      page: page,
    );
  }
}
