import 'package:bookstark_flutter/features/admin/admin_members_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> row(int id, {int role = 1, int status = 0}) => {
  'member_id': id,
  'account': ' owned fixture ',
  'role': role,
  'status': status,
  'create_time': '2026-11-07T08:00:00+08:00',
  'create_at': 1794009600,
  'last_login_time': null,
  'email': '',
  'default_home': '',
};
Map<String, Object?> envelope(
  Object? data, {
  int page = 1,
  int total = 1,
  int pages = 1,
}) => {
  'code': 0,
  'data': data,
  'page': page,
  'page_size': 20,
  'total': total,
  'total_pages': pages,
};
void main() {
  test(
    'member projection preserves account and nullable login without inventing contacts',
    () {
      final member = AdminMemberRecord.parse(row(1));
      expect(member.account, ' owned fixture ');
      expect(member.lastLogin, isNull);
      expect(member.created.isUtc, isTrue);
      expect(member.toString(), isNot(contains(member.account)));
    },
  );
  test('member roles, status and identity require integers', () {
    for (final patch in [
      {'role': true},
      {'role': 0.0},
      {'status': 1.0},
      {'status': 9},
      {'member_id': 1.0},
      {'member_id': 0},
    ]) {
      expect(
        () => AdminMemberRecord.parse({...row(1), ...patch}),
        throwsFormatException,
      );
    }
  });
  test(
    'member time requires an explicit offset and keeps absent login absent',
    () {
      expect(
        () => AdminMemberRecord.parse({...row(1), 'create_time': '2026-11-07'}),
        throwsFormatException,
      );
      final member = AdminMemberRecord.parse({
        ...row(1),
        'last_login_time': '2026-11-07T01:00:00Z',
      });
      expect(member.lastLogin, DateTime.utc(2026, 11, 7, 1));
    },
  );
  test('member page accepts nil Go slices and exact page20 metadata', () {
    final first = AdminMemberPage.parse(envelope([row(1)]), requestedPage: 1);
    expect(first.items, hasLength(1));
    expect(first.hasNext, isFalse);
    expect(first.hasPrevious, isFalse);
    expect(
      AdminMemberPage.parse(envelope(null, total: 0), requestedPage: 1).items,
      isEmpty,
    );
    final last = AdminMemberPage.parse(
      envelope([row(21)], page: 2, total: 21, pages: 2),
      requestedPage: 2,
    );
    expect(last.items.single.id, 21);
    expect(last.hasNext, isFalse);
    expect(
      AdminMemberPage.parse(
        envelope(null, page: 3, total: 21, pages: 2),
        requestedPage: 3,
      ).items,
      isEmpty,
    );
  });
  test(
    'malformed page metadata never becomes fake totals or duplicate users',
    () {
      for (final value in [
        {...envelope([]), 'code': 0.0},
        {...envelope([]), 'page': 1.0},
        {...envelope([]), 'page_size': 20.0},
        {...envelope([]), 'page_size': 0},
        envelope([], total: 21, pages: 1),
        envelope([row(1), row(1)], total: 2),
        envelope([row(2), row(1)], total: 2),
        envelope([row(1), row(2)], total: 1),
        envelope(false),
      ]) {
        expect(
          () => AdminMemberPage.parse(value, requestedPage: 1),
          throwsFormatException,
        );
      }
      expect(
        () => AdminMemberPage.parse(
          envelope([row(1)], page: 2),
          requestedPage: 2,
        ),
        throwsFormatException,
      );
    },
  );
  test('confirmation fingerprint includes role and approval state', () {
    final member = AdminMemberRecord.parse(row(1));
    expect(member.sameReviewedTarget(AdminMemberRecord.parse(row(1))), isTrue);
    expect(
      member.sameReviewedTarget(AdminMemberRecord.parse(row(1, status: 1))),
      isFalse,
    );
    expect(
      member.sameReviewedTarget(AdminMemberRecord.parse(row(1, role: 0))),
      isFalse,
    );
  });
  test('password boundaries are UTF8 bytes and spaces remain significant', () {
    expect(() => AdminMemberPassword.validate('界界', '界界'), returnsNormally);
    final limit = List.filled(24, '界').join();
    expect(() => AdminMemberPassword.validate(limit, limit), returnsNormally);
    expect(
      () => AdminMemberPassword.validate('      ', '      '),
      returnsNormally,
    );
    expect(
      () => AdminMemberPassword.validate('abcde', 'abcde'),
      throwsFormatException,
    );
    final over = List.filled(25, '界').join();
    expect(
      () => AdminMemberPassword.validate(over, over),
      throwsFormatException,
    );
    expect(
      () => AdminMemberPassword.validate('abcdef', 'abcdef '),
      throwsFormatException,
    );
  });
}
