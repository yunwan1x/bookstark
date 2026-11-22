import 'package:bookstark_flutter/features/admin/admin_community_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_community_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('community notices are controlled and fully translated', () {
    const en = AdminCommunityStrings(true), zh = AdminCommunityStrings(false);
    for (final notice in AdminCommunityNotice.values) {
      expect(en.notice(notice).trim(), isNotEmpty);
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(en.notice(notice)), isFalse);
      expect(zh.notice(notice).trim(), isNotEmpty);
    }
    expect(en.linksCount(1), '1 link');
    expect(en.selectedCount(1), '1 selected');
  });
  test(
    'missing deletion count never becomes fabricated zero and dates keep local meaning',
    () {
      const s = AdminCommunityStrings(true);
      expect(
        s.notice(AdminCommunityNotice.knownDeletedRead),
        isNot(contains('0')),
      );
      expect(
        s.notice(AdminCommunityNotice.knownDeletedRead, deleted: 3),
        contains('3'),
      );
      expect(s.notice(AdminCommunityNotice.knownDeleteZero), contains('0'));
      expect(s.date(DateTime(2026, 11, 7, 9, 20)), '2026-11-07 09:20');
      expect(s.date(DateTime(1)), 'Not provided');
    },
  );
}
