import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unavailable and hidden module preferences survive normalization', () {
    final items = readHomeLayout([
      {'key': 'assets', 'width': 3, 'hidden': true},
      {'key': 'books', 'width': 2, 'hidden': false},
    ]);
    expect(items.length, 9);
    expect(items.first.toJson(), {'key': 'assets', 'width': 3, 'hidden': true});
    expect(items[1].key, 'books');
    expect(items.map((e) => e.key).toSet().length, 9);
    expect(
      readHomeLayout(items.map((e) => e.toJson()).toList()).first.hidden,
      true,
    );
  });
  test('ambiguous or invalid layouts never become defaults silently', () {
    for (final raw in [
      'broken',
      [
        {'key': 'unknown', 'width': 1},
      ],
      [
        {'key': 'notes', 'width': 1},
        {'key': 'notes', 'width': 2},
      ],
      [
        {'key': 'notes', 'width': 0},
      ],
      [
        {'key': 'notes', 'width': 4},
      ],
      [
        {'key': 'notes', 'width': 1, 'hidden': 'false'},
      ],
    ]) {
      expect(() => readHomeLayout(raw), throwsFormatException);
    }
    expect(readHomeLayout(null).length, 9);
  });
  test('request query preserves cutoff independently from activity window', () {
    final query = HomeQuery(
      month: DateTime(2026, 11),
      order: 'created',
      limit: 50,
      view: HomeCalendarView.week,
      end: '2024-02-29',
    );
    final uri = Uri.parse(query.apiPath);
    expect(uri.path, '/api/home');
    expect(uri.queryParameters, {
      'order': 'created',
      'limit': '50',
      'month': '2026-11',
      'view': 'week',
      'end': '2024-02-29',
    });
    expect(query.movePeriod(1).end, '2024-02-29');
    expect(query.copyWith(clearEnd: true).end, isNull);
  });
  test('invalid calendar dates and unsupported filters are rejected', () {
    for (final value in [
      '2026-02-29',
      '2026-02-31',
      '2026-13-01',
      '2026-1-01',
      '0000-01-01',
    ]) {
      expect(() => HomeQuery(end: value), throwsFormatException);
    }
    expect(() => HomeQuery(limit: 100), throwsFormatException);
    expect(() => HomeQuery(order: 'anything'), throwsFormatException);
  });
  test('November 2026 day grid includes complete Monday to Sunday weeks', () {
    final days = homeCalendarPeriods(HomeQuery(month: DateTime(2026, 11)));
    expect(homeDayKey(days.first.start), '2026-10-26');
    expect(homeDayKey(days.last.end), '2026-12-06');
    expect(days.length, 42);
    expect(days.every((p) => p.start == p.end), true);
  });
  test('week cutoff is Sunday while month cutoff respects leap year', () {
    final weeks = homeCalendarPeriods(
      HomeQuery(month: DateTime(2026, 11), view: HomeCalendarView.week),
    );
    expect(weeks.length, 6);
    expect(
      weeks.every(
        (p) =>
            p.start.weekday == DateTime.monday &&
            p.end.weekday == DateTime.sunday,
      ),
      true,
    );
    final months = homeCalendarPeriods(
      HomeQuery(month: DateTime(2024, 2), view: HomeCalendarView.month),
    );
    expect(months.length, 12);
    expect(months[1].cutoff, '2024-02-29');
    final next = HomeQuery(
      month: DateTime(2024, 2),
      view: HomeCalendarView.month,
    ).movePeriod(1);
    expect(next.month, DateTime(2025, 2));
  });
  test('share targets retain only a validated relative identifier', () {
    final item = HomeContentItem.read({
      'id': 8,
      'title': 'Owned share',
      'url': '/shares/demo-safe',
    }, module: 'shares');
    expect(item.shareIdentify, 'demo-safe');
    for (final url in [
      'https://other.invalid/shares/demo-safe',
      '//other.invalid/shares/demo-safe',
      '/shares/demo-safe?token=private',
      '/shares/demo-safe#fragment',
      '/shares/demo-safe/extra',
      '/shares/%2Fprivate',
      '/notes/8',
    ]) {
      expect(
        () => HomeContentItem.read({
          'id': 8,
          'title': 'Owned share',
          'url': url,
        }, module: 'shares'),
        throwsFormatException,
      );
    }
    expect(
      HomeContentItem.read({
        'id': 8,
        'title': 'Note',
        'url': 'javascript:bad()',
      }, module: 'notes').shareIdentify,
      isNull,
    );
  });
}
