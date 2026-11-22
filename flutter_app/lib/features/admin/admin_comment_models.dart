enum AdminCommentStatus {
  visible('visible'),
  deleted('deleted');

  const AdminCommentStatus(this.value);
  final String value;
  static AdminCommentStatus parse(Object? value) => switch (value) {
    'visible' => visible,
    'deleted' => deleted,
    _ => throw const FormatException('Unsupported comment status'),
  };
}

enum AdminCommentTarget {
  blog('blog'),
  book('book'),
  document('document');

  const AdminCommentTarget(this.value);
  final String value;
  static AdminCommentTarget parse(Object? value) => switch (value) {
    'blog' => blog,
    'book' => book,
    'document' => document,
    _ => throw const FormatException('Unsupported comment target'),
  };
}

class AdminCommentFilter {
  const AdminCommentFilter({this.keyword = '', this.status, this.target});
  final String keyword;
  final AdminCommentStatus? status;
  final AdminCommentTarget? target;
  Map<String, String> query(int page) {
    _integer(page, minimum: 1);
    return {
      'page': '$page',
      'page_size': '20',
      if (keyword.isNotEmpty) 'keyword': keyword,
      if (status != null) 'status': status!.value,
      if (target != null) 'target_type': target!.value,
    };
  }

  bool sameAs(AdminCommentFilter other) =>
      keyword == other.keyword &&
      status == other.status &&
      target == other.target;
  @override
  String toString() => 'AdminCommentFilter(personalFields: [redacted])';
}

class AdminCommentRecord {
  const AdminCommentRecord({
    required this.id,
    required this.target,
    required this.targetId,
    required this.shareIdentify,
    required this.parentId,
    required this.rootId,
    required this.replyToId,
    required this.replyToAuthor,
    required this.authorMemberId,
    required this.author,
    required this.content,
    required this.status,
    required this.created,
    required this.modified,
    this.createdSubmicro = 0,
    this.modifiedSubmicro = 0,
  });
  final int id, targetId, parentId, rootId, replyToId, authorMemberId;
  final AdminCommentTarget target;
  final AdminCommentStatus status;
  final String shareIdentify, replyToAuthor, author, content;
  final DateTime created, modified;
  final int createdSubmicro, modifiedSubmicro;
  factory AdminCommentRecord.parse(Object? value) {
    final row = _object(value);
    return AdminCommentRecord(
      id: _integer(row['comment_id'], minimum: 1),
      target: AdminCommentTarget.parse(row['target_type']),
      targetId: _integer(row['target_id'], minimum: 1),
      shareIdentify: _text(row['share_identify']),
      parentId: _integer(row['parent_comment_id']),
      rootId: _integer(row['root_comment_id']),
      replyToId: _integer(row['reply_to_comment_id']),
      replyToAuthor: _text(row['reply_to_author_name']),
      authorMemberId: _integer(row['author_member_id']),
      author: _text(row['author_name']),
      content: _text(row['content']),
      status: AdminCommentStatus.parse(row['status']),
      created: _time(row['create_time']),
      modified: _time(row['modify_time']),
      createdSubmicro: _submicro(row['create_time']),
      modifiedSubmicro: _submicro(row['modify_time']),
    );
  }
  bool sameReviewedTarget(AdminCommentRecord other) =>
      id == other.id &&
      target == other.target &&
      targetId == other.targetId &&
      shareIdentify == other.shareIdentify &&
      parentId == other.parentId &&
      rootId == other.rootId &&
      replyToId == other.replyToId &&
      replyToAuthor == other.replyToAuthor &&
      authorMemberId == other.authorMemberId &&
      author == other.author &&
      content == other.content &&
      status == other.status &&
      created == other.created &&
      modified == other.modified &&
      createdSubmicro == other.createdSubmicro &&
      modifiedSubmicro == other.modifiedSubmicro;
  @override
  String toString() =>
      'AdminCommentRecord(id: $id, personalFields: [redacted])';
}

class AdminCommentPage {
  const AdminCommentPage({
    required this.items,
    required this.page,
    required this.total,
    required this.totalPages,
  });
  final List<AdminCommentRecord> items;
  final int page, total, totalPages;
  factory AdminCommentPage.parse(
    Map<String, Object?> envelope, {
    required int requestedPage,
  }) {
    if (envelope['code'] is! int || envelope['code'] != 0) {
      throw const FormatException('Missing comment success code');
    }
    final page = _integer(envelope['page'], minimum: 1);
    final size = _integer(envelope['page_size'], minimum: 1);
    final total = _integer(envelope['total']);
    final pages = _integer(envelope['total_pages']);
    if (page != requestedPage ||
        size != 20 ||
        pages != (total == 0 ? 1 : (total + 19) ~/ 20)) {
      throw const FormatException('Inconsistent comment pagination');
    }
    final data = envelope['data'];
    if (data is! List) throw const FormatException('Invalid comment list');
    final items = data.map(AdminCommentRecord.parse).toList(growable: false);
    if (items.length > 20 ||
        items.length > total ||
        (page > pages && items.isNotEmpty)) {
      throw const FormatException('Inconsistent comment item count');
    }
    final ids = <int>{};
    AdminCommentRecord? previous;
    for (final item in items) {
      if (!ids.add(item.id)) {
        throw const FormatException('Repeated comment identity');
      }
      if (previous != null) {
        final timeOrder = previous.created.compareTo(item.created);
        final fineOrder = timeOrder == 0
            ? previous.createdSubmicro.compareTo(item.createdSubmicro)
            : timeOrder;
        if (fineOrder < 0 || (fineOrder == 0 && previous.id <= item.id)) {
          throw const FormatException('Inconsistent comment ordering');
        }
      }
      previous = item;
    }
    return AdminCommentPage(
      items: List.unmodifiable(items),
      page: page,
      total: total,
      totalPages: pages,
    );
  }
  List<AdminCommentRecord> reviewedSelection(Iterable<int> selected) {
    final ids = selected.toSet();
    if (ids.isEmpty ||
        ids.length > 20 ||
        !ids.every((id) => items.any((item) => item.id == id))) {
      throw const FormatException('Selection must belong to the current page');
    }
    return List.unmodifiable(items.where((item) => ids.contains(item.id)));
  }

  @override
  String toString() =>
      'AdminCommentPage(page: $page, personalFields: [redacted])';
}

class AdminCommentDeleteReceipt {
  const AdminCommentDeleteReceipt(this.deleted);
  final int deleted;
  factory AdminCommentDeleteReceipt.fromAcknowledgedData(
    Map<String, Object?> data,
  ) => AdminCommentDeleteReceipt(_integer(data['deleted']));
  factory AdminCommentDeleteReceipt.parse(Map<String, Object?> envelope) {
    if (envelope['code'] is! int || envelope['code'] != 0) {
      throw const FormatException('Missing delete success code');
    }
    return AdminCommentDeleteReceipt(
      _integer(_object(envelope['data'])['deleted']),
    );
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid comment object');
  }
  return Map<String, Object?>.from(value);
}

int _integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw const FormatException('Invalid comment integer');
  }
  return value;
}

String _text(Object? value) => value is String
    ? value
    : throw const FormatException('Invalid comment text');
final _timestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-](\d{2}):(\d{2}))$',
);
DateTime _time(Object? value) {
  final match = value is String ? _timestamp.firstMatch(value) : null;
  if (match == null) {
    throw const FormatException('Comment time must be RFC3339 with offset');
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final calendar = DateTime.utc(parts[0], parts[1], parts[2]);
  if (calendar.year != parts[0] ||
      calendar.month != parts[1] ||
      calendar.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59 ||
      (match.group(9) != null &&
          (int.parse(match.group(9)!) > 23 ||
              int.parse(match.group(10)!) > 59))) {
    throw const FormatException('Invalid comment calendar time');
  }
  try {
    return DateTime.parse(value as String);
  } on FormatException {
    throw const FormatException('Invalid comment time');
  }
}

int _submicro(Object? value) {
  final fraction = _timestamp.firstMatch(value as String)!.group(7) ?? '';
  return int.parse(fraction.padRight(9, '0').substring(6, 9));
}
