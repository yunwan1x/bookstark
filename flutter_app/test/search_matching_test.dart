import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/search_matching.dart';

void main() {
  test(
    'bounded snippets retain legacy Unicode and match placement semantics',
    () {
      _check(searchSnippet('', 'x') == '', 'empty body');
      _check(
        searchSnippet('short body', 'absent') == 'short body',
        'short miss',
      );
      _check(searchSnippet('a' * 150, 'absent') == 'a' * 150, 'exact 150 miss');
      _check(
        searchSnippet('a' * 151, 'absent') == '${'a' * 150}...',
        '150-rune miss truncation',
      );

      final mixed = '${'📚' * 70}Needle${'é' * 90}';
      final mixedResult = searchSnippet(mixed, 'nEeDlE');
      _sameAsOracle(
        mixed,
        'nEeDlE',
        mixedResult,
        'surrogate and combining runes',
      );
      _check(!mixedResult.contains('\uFFFD'), 'no replacement rune');

      final repeated = 'needle${'x' * 220}NEEDLE';
      final repeatedResult = searchSnippet(repeated, 'NeEdLe');
      _sameAsOracle(
        repeated,
        'NeEdLe',
        repeatedResult,
        'first case-insensitive match',
      );
      _check(!repeatedResult.startsWith('...'), 'first match wins');

      final beginning = 'Needle${'x' * 220}';
      final beginningResult = searchSnippet(beginning, 'needle');
      _sameAsOracle(beginning, 'needle', beginningResult, 'start boundary');
      _check(
        !beginningResult.startsWith('...'),
        'start has no prefix ellipsis',
      );
      _check(beginningResult.endsWith('...'), 'start has suffix ellipsis');

      final middle = '${'a' * 200}needle${'b' * 200}';
      final middleResult = searchSnippet(middle, 'needle');
      _sameAsOracle(middle, 'needle', middleResult, 'middle match');
      _check(
        middleResult.startsWith('...') && middleResult.endsWith('...'),
        'middle ellipses',
      );

      final end = 'x' * 217 + '📖needle';
      final endResult = searchSnippet(end, 'NEEDLE');
      _sameAsOracle(end, 'NEEDLE', endResult, 'near-end backfill');
      _check(
        endResult.startsWith('...'),
        'near-end backfill starts with ellipsis',
      );
      _check(!endResult.endsWith('...'), 'end has no suffix ellipsis');
      _check(
        endResult.runes.skip(3).length == 150,
        'near-end content window has 150 runes',
      );

      final longQuery = '${'Ab😀_' * 80}Tail';
      final longBody = '前缀' * 91 + longQuery.toLowerCase() + '后缀' * 100;
      _sameAsOracle(
        longBody,
        longQuery,
        searchSnippet(longBody, longQuery),
        'long literal query',
      );

      _randomizedOracleChecks();
      _largeBodyCheck();
    },
  );
}

void _randomizedOracleChecks() {
  final random = Random(0x51A7);
  const alphabet = ['a', 'B', 'ç', '漢', '📚', '🧪', 'é', '_', '\n'];
  for (var sample = 0; sample < 300; sample++) {
    final body = List.generate(
      random.nextInt(500),
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    final query = sample % 3 == 0
        ? 'missing-$sample'
        : _randomSubstring(body, random);
    _sameAsOracle(
      body,
      query,
      searchSnippet(body, query),
      'random sample $sample',
    );
  }
}

String _randomSubstring(String text, Random random) {
  final runes = text.runes.toList();
  if (runes.isEmpty) return 'none';
  final start = random.nextInt(runes.length);
  final end = start + 1 + random.nextInt(min(16, runes.length - start));
  return String.fromCharCodes(runes.sublist(start, end));
}

void _largeBodyCheck() {
  const chunkLength = 1024 * 1024;
  final chunk = 'a'.padRight(chunkLength, 'a');
  final body = StringBuffer();
  for (var i = 0; i < 10; i++) {
    body.write(chunk);
  }
  body.write('🧪Target');
  for (var i = 0; i < 10; i++) {
    body.write(chunk);
  }
  final snippet = searchSnippet(body.toString(), 'target');
  _check(
    snippet.contains('Target'),
    '20 MiB body retains case-insensitive match',
  );
  _check(snippet.runes.length <= 156, '20 MiB body returns bounded snippet');
}

String _originalSearchSnippet(String text, String query) {
  if (text.isEmpty) return '';
  final runes = text.runes.toList();
  final match = RegExp(
    RegExp.escape(query),
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) {
    return runes.length <= 150
        ? text
        : '${String.fromCharCodes(runes.take(150))}...';
  }
  final index = text.substring(0, match.start).runes.length;
  final half = (150 - query.runes.length) ~/ 2;
  var start = (index - half).clamp(0, runes.length);
  var end = start + 150;
  if (end > runes.length) {
    end = runes.length;
    start = (end - 150).clamp(0, runes.length);
  }
  return '${start > 0 ? '...' : ''}'
      '${String.fromCharCodes(runes.sublist(start, end))}'
      '${end < runes.length ? '...' : ''}';
}

void _sameAsOracle(String text, String query, String actual, String label) {
  final expected = _originalSearchSnippet(text, query);
  _check(actual == expected, '$label: expected $expected but got $actual');
}

void _check(bool condition, String label) {
  if (!condition) throw StateError('FAILED: $label');
}
