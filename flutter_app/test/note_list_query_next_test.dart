import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/note_list_query.dart';
import 'package:bookstark_flutter/core/note_list_source.dart';

void main() {
  test('defaults omit unsupported negative and filter wire values', () {
    expect(const NoteListQuery().parameters(page: 1), {
      'type': 'note',
      'page': '1',
      'page_size': '20',
    });
  });
  test('all supported server filters use exact existing wire names', () {
    final params = const NoteListQuery(
      keyword: '雪 & code',
      label: ' tag ',
      createdDate: '2026-11-11',
      pin: NotePinFilter.unpinned,
      visibility: NoteVisibilityFilter.private,
      hasCode: true,
    ).parameters(page: 3);
    expect(params['pinned'], '0');
    expect(params.containsKey('is_pinned'), isFalse);
    expect(params['date'], '2026-11-11');
    expect(params['has_code'], '1');
    expect(params.containsKey('date_from'), isFalse);
    expect(params['keyword'], '雪 & code');
    expect(params['label'], ' tag ');
  });
  test('invalid calendar and local fake filters rejected before IO', () {
    expect(
      () => const NoteListQuery(createdDate: '2026-02-30').parameters(page: 1),
      throwsFormatException,
    );
    for (final query in [
      const NoteListQuery(pin: NotePinFilter.pinned),
      const NoteListQuery(visibility: NoteVisibilityFilter.public),
      const NoteListQuery(createdDate: '2026-11-11'),
      const NoteListQuery(hasCode: true),
    ]) {
      expect(
        () => query.requireSupported(NoteListCapabilities.local),
        throwsUnsupportedError,
      );
    }
  });
  test(
    'labels JSON CSV compatibility retains whitespace and rejects corrupt arrays',
    () {
      expect(normalizeNoteListLabels(['a', ' b ']), ['a', ' b ']);
      expect(normalizeNoteListLabels('["a"," b "]'), ['a', ' b ']);
      expect(normalizeNoteListLabels('a, b '), ['a', ' b ']);
      expect(() => normalizeNoteListLabels('[broken'), throwsFormatException);
      expect(() => normalizeNoteListLabels(['a', 2]), throwsFormatException);
    },
  );
}
