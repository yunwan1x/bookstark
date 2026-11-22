import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_feed_models.dart';

PublicFeedItem item({
  bool locked = false,
  PublicFeedKind kind = PublicFeedKind.article,
  Uri? url,
  String? manageType,
  int? manageId,
}) => PublicFeedItem(
  kind: kind,
  identity: '${kind.name}:original',
  title: '标题',
  author: '作者',
  date: '2026-11-04',
  format: 'markdown',
  locked: locked,
  pinned: false,
  excerpt: 'secret body',
  labels: ['private label'],
  shareIdentify: kind == PublicFeedKind.bookmark ? null : '原始标识%2F',
  externalUri: url,
  manageType: manageType,
  manageTargetId: manageId,
);
void main() {
  test(
    'server navigation accepts real root or prefixed routes without credentials or duplicate filters',
    () {
      final server = Uri.parse('https://example.test/workspace');
      PublicFeedQuery parse(String value) =>
          PublicFeedQuery.fromNavigation(value, server: server);
      expect(
        parse('/shares?type=note&sort=updated&label=a%252Fb&page=2').label,
        'a%2Fb',
      );
      expect(
        parse('https://example.test/workspace/shares?type=bookmark').kind,
        PublicFeedKind.bookmark,
      );
      for (final bad in [
        '//example.test/shares',
        'https://evil.test/shares',
        'http://example.test/shares',
        'https://user@example.test/shares',
        '/shares#secret',
        '/shares?type=note&type=article',
        '/shares?redirect=https://evil.test',
        '/shares?page=0',
        '/shares?page=99999999999999999999999999999999',
        '/shares?sort=random',
        '/shares?type=unknown',
        '/shares/extra',
      ]) {
        expect(() => parse(bad), throwsFormatException, reason: bad);
      }
    },
  );
  test(
    'query preserves exact Unicode labels and literal percent without double decoding',
    () {
      final query = PublicFeedQuery(
        kind: PublicFeedKind.note,
        sort: PublicFeedSort.updated,
        label: ' 保留,a&b%2F📚 ',
        keyword: 'x&y? 中文',
      );
      final parsed = Uri.parse(query.requestPath).queryParameters;
      expect(parsed['label'], ' 保留,a&b%2F📚 ');
      expect(parsed['keyword'], 'x&y? 中文');
      expect(parsed['type'], 'note');
      expect(parsed['sort'], 'updated');
      expect(() => PublicFeedQuery(page: 0), throwsFormatException);
      expect(() => PublicFeedQuery(keyword: 'a' * 201), throwsFormatException);
    },
  );
  test(
    'locked resource never retains protected excerpts or labels in its model',
    () {
      final locked = item(locked: true);
      expect(locked.excerpt, isEmpty);
      expect(locked.labels, isEmpty);
      expect(() => locked.labels.add('leak'), throwsUnsupportedError);
      final open = item();
      expect(open.excerpt, 'secret body');
      expect(open.labels, ['private label']);
    },
  );
  test(
    'public bookmark needs real safe URL and cannot invent share or management identity',
    () {
      expect(
        () => item(
          kind: PublicFeedKind.bookmark,
          url: Uri.parse('javascript:alert(1)'),
        ),
        throwsFormatException,
      );
      expect(
        () => item(
          kind: PublicFeedKind.bookmark,
          url: Uri.parse('https://user:secret@example.test'),
        ),
        throwsFormatException,
      );
      expect(
        item(
          kind: PublicFeedKind.bookmark,
          url: Uri.parse('https://example.test/path?q=1#section'),
        ).manageTargetId,
        isNull,
      );
      expect(
        () => item(manageId: 3, manageType: 'book'),
        throwsFormatException,
      );
    },
  );
  test(
    'actual page boundaries retain filters and a removed category can return no active chip',
    () {
      final query = PublicFeedQuery(label: 'removed');
      final page = PublicFeedPageData(
        query: query,
        items: [],
        categories: [const PublicFeedCategory(label: '', selected: false)],
        previous: null,
        next: null,
      );
      expect(page.loadedCount, 0);
      expect(
        () => PublicFeedPageData(
          query: query,
          items: [],
          categories: [const PublicFeedCategory(label: '', selected: true)],
          previous: null,
          next: null,
        ),
        throwsFormatException,
      );
      expect(
        () => PublicFeedPageData(
          query: query,
          items: [],
          categories: [const PublicFeedCategory(label: '', selected: false)],
          previous: null,
          next: query.copyWith(page: 3),
        ),
        throwsFormatException,
      );
      expect(
        () => PublicFeedPageData(
          query: query,
          items: [],
          categories: [const PublicFeedCategory(label: '', selected: false)],
          previous: null,
          next: query.copyWith(page: 2, keyword: 'different'),
        ),
        throwsFormatException,
      );
    },
  );
}
