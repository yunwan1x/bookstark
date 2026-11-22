import 'dart:convert';

class HtmlCreationCandidate {
  const HtmlCreationCandidate({
    required this.id,
    required this.title,
    required this.version,
    required this.protected,
    required this.modified,
  });
  final int id, version;
  final String title, modified;
  final bool protected;
}

/// List titles are hints only, with no assertion of a matching creation input.
class HtmlCreationCandidatePage {
  HtmlCreationCandidatePage({
    required List<HtmlCreationCandidate> candidates,
    required this.page,
    required this.totalPages,
    required this.total,
  }) : candidates = List.unmodifiable(candidates);
  final List<HtmlCreationCandidate> candidates;
  final int page, totalPages, total;
  factory HtmlCreationCandidatePage.parse(
    Map<String, Object?> response, {
    required int memberId,
    required String collection,
    required int page,
  }) {
    final rows = response['data'] ?? const <Object?>[];
    final total = response['total'];
    final totalPages = response['total_pages'];
    final pageSize = response['page_size'];
    if (!response.containsKey('data') ||
        response['code'] != 0 ||
        response['page'] != page ||
        total is! int ||
        total < 0 ||
        totalPages is! int ||
        totalPages < 0 ||
        pageSize is! int ||
        pageSize < 1 ||
        pageSize > 200 ||
        rows is! List ||
        rows.length > pageSize ||
        rows.length > total) {
      throw const FormatException('Invalid HTML candidate page');
    }
    final seen = <int>{};
    final candidates = <HtmlCreationCandidate>[];
    for (final row in rows) {
      if (row is! Map ||
          row['member_id'] != memberId ||
          row['blog_type'] != collection ||
          row['editor_type'] != 'html' ||
          row['blog_id'] is! int ||
          (row['blog_id'] as int) <= 0 ||
          !seen.add(row['blog_id'] as int) ||
          row['blog_title'] is! String ||
          utf8.encode(row['blog_title'] as String).length > 200 ||
          row['version'] is! int ||
          (row['version'] as int) < 0 ||
          row['has_password'] is! bool ||
          row['modify_time'] is! String ||
          DateTime.tryParse(row['modify_time'] as String) == null) {
        throw const FormatException('Invalid owned HTML candidate');
      }
      candidates.add(
        HtmlCreationCandidate(
          id: row['blog_id'] as int,
          title: row['blog_title'] as String,
          version: row['version'] as int,
          protected: row['has_password'] as bool,
          modified: row['modify_time'] as String,
        ),
      );
    }
    return HtmlCreationCandidatePage(
      candidates: candidates,
      page: page,
      totalPages: totalPages,
      total: total,
    );
  }
}
