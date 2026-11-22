import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_legacy_import_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/legacy_zip/legacy-time-vectors.json',
            ).readAsStringSync(),
          )
          as Map;
  final vectors = fixture['vectors'] as List;
  test('independent vectors were produced by Go1.25 standard library', () {
    expect(fixture['synthetic_only'], isTrue);
    expect(fixture['go_version'], startsWith('go1.25.'));
    expect(vectors.length, 25);
  });
  for (var i = 0; i < vectors.length; i++) {
    test('Go timestamp vector $i', () {
      final row = vectors[i] as Map, input = row['input'] as String;
      if (row['empty'] == true) {
        expect(legacyImportTimestamp(input), isNull);
      } else if (row['ok'] == true) {
        expect(legacyImportTimestamp(input), row['unix_millis']);
      } else {
        expect(
          () => legacyImportTimestamp(input),
          throwsA(
            isA<LegacyTimestampFailure>().having(
              (e) => e.reason,
              'reason',
              LegacyTimestampReason.invalid,
            ),
          ),
        );
      }
    });
  }
  test(
    'empty modify falls back deterministically through create and export',
    () {
      const exported = '2026-11-08T01:02:03Z', created = '2024-02-29 01:02:03';
      expect(
        resolveLegacyImportTimestamp(
          modified: ' ',
          created: created,
          exported: exported,
        ),
        legacyImportTimestamp(created),
      );
      expect(
        resolveLegacyImportTimestamp(
          modified: '',
          created: '',
          exported: exported,
        ),
        legacyImportTimestamp(exported),
      );
      expect(
        resolveLegacyImportTimestamp(
          modified: exported,
          created: 'unused-invalid',
          exported: 'unused-invalid',
        ),
        legacyImportTimestamp(exported),
      );
    },
  );
  test('nonempty invalid time never quietly falls back to another date', () {
    expect(
      () => resolveLegacyImportTimestamp(
        modified: '2026-02-31T00:00:00Z',
        created: '2026-01-01T00:00:00Z',
        exported: '2026-11-08T00:00:00Z',
      ),
      throwsA(
        isA<LegacyTimestampFailure>().having(
          (e) => e.reason,
          'reason',
          LegacyTimestampReason.invalid,
        ),
      ),
    );
    expect(
      () => resolveLegacyImportTimestamp(
        modified: '',
        created: '',
        exported: ' ',
      ),
      throwsA(
        isA<LegacyTimestampFailure>().having(
          (e) => e.reason,
          'reason',
          LegacyTimestampReason.missing,
        ),
      ),
    );
  });
  test(
    'strict supported shapes reject unsupported offsets and extra precision',
    () {
      for (final input in [
        '2026-11-08T01:02:03+24:00',
        '2026-11-08T01:02:03+00:60',
        '2026-11-08T01:02:03.1234567890Z',
        '2026-11-08 01:02:03Z',
        'source-sensitive-time',
      ]) {
        expect(
          () => legacyImportTimestamp(input),
          throwsA(isA<LegacyTimestampFailure>()),
        );
      }
      expect(
        const LegacyTimestampFailure(LegacyTimestampReason.invalid).toString(),
        isNot(contains('source-sensitive-time')),
      );
    },
  );
  test('negative fractional seconds floor exactly without rounding', () {
    expect(legacyImportTimestamp('1969-12-31T23:59:59.999999999Z'), -1);
    expect(legacyImportTimestamp('1969-12-31T23:59:59.000000001Z'), -1000);
    expect(legacyImportTimestamp('1970-01-01T00:00:00.000999999Z'), 0);
  });
}
