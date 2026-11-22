import 'package:bookstark_flutter/features/admin/admin_comment_models.dart';
import 'package:flutter_test/flutter_test.dart';

int checks = 0;
void check(bool value, String message) {
  if (!value) throw StateError(message);
  checks++;
}

void rejects(void Function() action, String message) {
  try {
    action();
  } on FormatException {
    checks++;
    return;
  }
  throw StateError('Expected rejection: $message');
}

Map<String, Object?> row(
  int id, {
  String created = '2026-11-07T08:00:00+08:00',
}) => {
  'comment_id': id,
  'target_type': 'document',
  'target_id': 10,
  'share_identify': 'owned-share',
  'parent_comment_id': 0,
  'root_comment_id': id,
  'reply_to_comment_id': 0,
  'reply_to_author_name': '',
  'author_member_id': 0,
  'author_name': '匿名示例',
  'content': '  原始正文\n第二行 😀  ',
  'status': 'visible',
  'create_time': created,
  'modify_time': '2026-11-07T09:00:00+08:00',
  'author_email': 'ignored-private@example.invalid',
  'ip_hash': 'ignored-private-hash',
};
Map<String, Object?> envelope(
  List<Object?> rows, {
  int page = 1,
  int total = 2,
  int pages = 1,
}) => {
  'code': 0,
  'data': rows,
  'page': page,
  'page_size': 20,
  'total': total,
  'total_pages': pages,
};
AdminCommentPage parse(Map<String, Object?> value, {int page = 1}) =>
    AdminCommentPage.parse(value, requestedPage: page);
void checkModelContract() {
  final record = AdminCommentRecord.parse(row(2));
  check(
    record.content == '  原始正文\n第二行 😀  ',
    'preserve exact body whitespace/Unicode',
  );
  check(record.authorMemberId == 0, 'anonymous author id remains zero');
  check(
    !record.toString().contains('匿名') && !record.toString().contains('private'),
    'safe diagnostics',
  );
  final sameInstant = AdminCommentRecord.parse(
    row(2, created: '2026-11-07T00:00:00Z'),
  );
  check(
    record.sameReviewedTarget(sameInstant),
    'equivalent timestamp offsets compare as same instant',
  );
  check(
    !record.sameReviewedTarget(
      AdminCommentRecord.parse({...row(2), 'status': 'deleted'}),
    ),
    'review binds status',
  );
  check(
    !record.sameReviewedTarget(
      AdminCommentRecord.parse({...row(2), 'content': 'changed'}),
    ),
    'review binds content',
  );
  check(
    !record.sameReviewedTarget(
      AdminCommentRecord.parse({...row(2), 'root_comment_id': 9}),
    ),
    'review binds cascade relationship',
  );
  for (final change in [
    {'comment_id': 0},
    {'comment_id': 2.0},
    {'comment_id': 9007199254740992},
    {'target_type': 'note'},
    {'status': 'approved'},
    {'target_id': 0},
    {'author_member_id': -1},
    {'parent_comment_id': null},
    {'content': null},
    {'create_time': '2026-11-07 00:00:00'},
    {'modify_time': 'invalid'},
  ]) {
    rejects(
      () => AdminCommentRecord.parse({...row(2), ...change}),
      'malformed record $change',
    );
  }
  for (final time in [
    '2026-02-30T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-01-01T24:00:00Z',
    '2026-01-01T00:00:60Z',
    '2026-01-01T00:00:00+25:00',
    '2026-01-01T00:00:00.1234567890Z',
  ]) {
    rejects(
      () => AdminCommentRecord.parse({...row(2), 'create_time': time}),
      'invalid calendar or precision',
    );
  }
  final nanos = AdminCommentRecord.parse(
    row(2, created: '2026-11-07T00:00:00.123456789Z'),
  );
  check(
    nanos.createdSubmicro == 789 && nanos.created.microsecond == 456,
    'retain Go nanosecond ordering beyond Dart microseconds',
  );
  final nanosChanged = AdminCommentRecord.parse(
    row(2, created: '2026-11-07T00:00:00.123456788Z'),
  );
  check(
    !nanos.sameReviewedTarget(nanosChanged),
    'review compares submicro precision',
  );
  check(
    parse(
          envelope([
            row(1, created: '2026-11-07T00:00:00.123456789Z'),
            row(2, created: '2026-11-07T00:00:00.123456788Z'),
          ]),
        ).items.first.id ==
        1,
    'nanosecond order precedes descending id tie-break',
  );
  final first = parse(envelope([row(2), row(1)]));
  check(
    first.items.length == 2 && first.page == 1,
    'page selected ids and metadata',
  );
  rejects(() => parse(envelope([row(1), row(2)])), 'tie order descending id');
  rejects(() => parse(envelope([row(2), row(2)])), 'duplicate ids');
  rejects(
    () => parse(envelope([row(2, created: '2026-11-06T00:00:00Z'), row(1)])),
    'date primary ordering',
  );
  rejects(() => parse({...envelope([]), 'code': 0.0}), 'integer response code');
  rejects(
    () => parse({...envelope([]), 'page_size': 20.0}),
    'integer page size',
  );
  rejects(() => parse({...envelope([]), 'page_size': 100}), 'fixed page size');
  rejects(() => parse(envelope([], page: 2)), 'request page match');
  rejects(
    () => parse(envelope([row(2), row(1)], total: 1)),
    'count bounded by total',
  );
  rejects(
    () => parse(envelope([row(2)], page: 3), page: 3),
    'no rows beyond last page',
  );
  rejects(
    () => parse(
      envelope([for (var id = 21; id > 0; id--) row(id)], total: 21, pages: 2),
    ),
    'no more than20 rows',
  );
  final empty = parse(envelope([], total: 0, pages: 1));
  check(
    empty.total == 0 && empty.totalPages == 1,
    'Go generic empty page count minimum one',
  );
  rejects(
    () => parse(envelope([], total: 0, pages: 0)),
    'do not guess empty pages zero',
  );
  final second = parse(
    envelope([row(1)], page: 2, total: 21, pages: 2),
    page: 2,
  );
  check(second.page == 2, 'second page correct');
  check(
    first.reviewedSelection([1, 1, 2]).length == 2,
    'deduplicate selection from current page',
  );
  rejects(() => first.reviewedSelection([]), 'no empty delete');
  rejects(() => first.reviewedSelection([99]), 'no hidden or cross-page id');
  final filter = AdminCommentFilter(
    keyword: '  _% /?& 😀  ',
    status: AdminCommentStatus.deleted,
    target: AdminCommentTarget.book,
  );
  final query = filter.query(2);
  check(
    query['keyword'] == '  _% /?& 😀  ' && query['page_size'] == '20',
    'preserve keyword and fixed size',
  );
  check(
    query['status'] == 'deleted' && query['target_type'] == 'book',
    'only API enum values',
  );
  check(
    Uri(queryParameters: query).queryParameters['keyword'] == filter.keyword,
    'query encoding retains exact filter',
  );
  rejects(() => filter.query(0), 'positive page only');
  check(
    !const AdminCommentFilter().query(1).containsKey('status'),
    'all statuses omitted',
  );
  check(
    !filter.toString().contains(filter.keyword),
    'filter diagnostics omit search',
  );
  for (final deleted in [0, 1, 3, 50]) {
    final receipt = AdminCommentDeleteReceipt.parse({
      'code': 0,
      'data': {'deleted': deleted},
    });
    check(
      receipt.deleted == deleted,
      'actual affected count including zero and cascade',
    );
  }
  for (final deleted in [-1, 0.0, '2', null]) {
    rejects(
      () => AdminCommentDeleteReceipt.parse({
        'code': 0,
        'data': {'deleted': deleted},
      }),
      'valid affected row integer',
    );
  }
}

void main() {
  test(
    'actual comment contract fields, selection, dates and receipt counts',
    checkModelContract,
  );
}
