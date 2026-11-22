import 'dart:convert';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:flutter_test/flutter_test.dart';

LegacyFormatSource source({String? hash, String? scope}) => LegacyFormatSource(
  archiveSha256: hash ?? 'a' * 64,
  scopeKey: scope ?? 'b' * 32,
  items: const [
    LegacyFormatItem(
      id: 'note',
      title: '旅行手记',
      collection: 'note',
      originalBody: '\uFEFF# 原文\r\n',
      passwordHash: '',
    ),
    LegacyFormatItem(
      id: 'article',
      title: '网页收藏',
      collection: 'article',
      originalBody: '<p>原文</p>',
      passwordHash: '',
    ),
    LegacyFormatItem(
      id: 'protected',
      title: '会议纪要',
      collection: 'note',
      originalBody: 'ENC:v1:opaque-synthetic-marker',
      passwordHash: 'synthetic-hash-marker',
    ),
  ],
);
void main() {
  test('nothing is inferred and incomplete choices cannot serialize', () {
    final selection = LegacyFormatSelection(source());
    expect(selection.choices, isEmpty);
    expect(selection.unresolved, 3);
    expect(selection.complete, isFalse);
    expect(selection.toJson, throwsStateError);
  });
  test(
    'single choice preserves source exact body and other unresolved items',
    () {
      final original = source();
      final empty = LegacyFormatSelection(original);
      final changed = empty.choose('note', LegacyContentFormat.markdown);
      expect(empty.choices, isEmpty);
      expect(changed.unresolved, 2);
      expect(changed.choices['article'], isNull);
      expect(original.byId['note']!.originalBody, '\uFEFF# 原文\r\n');
    },
  );
  test(
    'batch applies only missing choices and never overwrites an explicit one',
    () {
      final selection = LegacyFormatSelection(source())
          .choose('article', LegacyContentFormat.html)
          .chooseMissing(LegacyContentFormat.markdown);
      expect(selection.complete, isTrue);
      expect(selection.choices, {
        'note': LegacyContentFormat.markdown,
        'article': LegacyContentFormat.html,
        'protected': LegacyContentFormat.markdown,
      });
      expect(() => selection.choices.clear(), throwsUnsupportedError);
    },
  );
  test(
    'source-bound stable recipe contains no bodies, hashes, password or lifetime key',
    () {
      final original = source();
      final selected = LegacyFormatSelection(
        original,
      ).chooseMissing(LegacyContentFormat.markdown);
      final wire = jsonEncode(selected);
      for (final forbidden in [
        'opaque-synthetic-marker',
        'synthetic-hash-marker',
        'originalBody',
        'password',
        original.scopeKey,
        '# 原文',
      ]) {
        expect(wire, isNot(contains(forbidden)));
      }
      final restored = LegacyFormatSelection.fromJson(
        original,
        (jsonDecode(wire) as Map).cast<String, Object?>(),
      );
      expect(restored.choices, selected.choices);
      expect(restored.digest, selected.digest);
      final order = LegacyFormatSelection(original)
          .choose('protected', LegacyContentFormat.markdown)
          .choose('note', LegacyContentFormat.markdown)
          .choose('article', LegacyContentFormat.markdown);
      expect(order.digest, selected.digest);
    },
  );
  test('same choice set cannot silently apply to a different archive', () {
    final original = LegacyFormatSelection(
      source(),
    ).chooseMissing(LegacyContentFormat.html);
    expect(
      () => LegacyFormatSelection.fromJson(
        source(hash: 'c' * 64),
        original.toJson(),
      ),
      throwsFormatException,
    );
  });
  test('unknown IDs, duplicate entries and unknown formats are refused', () {
    final original = source();
    expect(
      () => LegacyFormatSelection(
        original,
      ).choose('unknown', LegacyContentFormat.html),
      throwsFormatException,
    );
    final selected = LegacyFormatSelection(
      original,
    ).chooseMissing(LegacyContentFormat.html);
    final data = selected.toJson();
    final duplicate = {
      ...data,
      'editors': [
        {'identify': 'note', 'format': 'html'},
        {'identify': 'note', 'format': 'html'},
        {'identify': 'protected', 'format': 'html'},
      ],
    };
    expect(
      () => LegacyFormatSelection.fromJson(original, duplicate),
      throwsFormatException,
    );
    expect(() => LegacyContentFormat.parse('unknown'), throwsFormatException);
    expect(
      () => LegacyFormatSelection.fromJson(original, {
        ...data,
        'password': 'never',
      }),
      throwsFormatException,
    );
  });
  test('source lists are immutable and protected state is explicit', () {
    final original = source();
    expect(original.byId['protected']!.isProtected, isTrue);
    expect(original.byId['note']!.isProtected, isFalse);
    expect(() => original.items.clear(), throwsUnsupportedError);
    expect(() => original.byId.clear(), throwsUnsupportedError);
  });
  test('zero blog source can return an explicit empty format recipe', () {
    final original = LegacyFormatSource(
      archiveSha256: 'a' * 64,
      scopeKey: 'b' * 32,
      items: const [],
    );
    final selection = LegacyFormatSelection(original);
    expect(selection.complete, isTrue);
    expect(selection.toJson()['editors'], isEmpty);
  });
}
