import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';

/// Search scans arbitrary-size Markdown, retaining only one BLOB block, a small
/// regex overlap and the 150-rune result. No full-body allocation or truncation.
final class LocalSearchBodyScan {
  const LocalSearchBodyScan({required this.wholeWord, required this.snippet});
  final bool wholeWord;
  final String snippet;
  static const chunkBytes = 64 * 1024;
  static Future<LocalSearchBodyScan> read(
    DatabaseExecutor tx, {
    required int id,
    required String query,
    required void Function() guard,
    String? collection,
    String? editorType,
  }) async {
    if (id <= 0 || query.isEmpty) {
      throw ArgumentError('Actual search identity/query required');
    }
    final note = collection != null;
    if (note &&
        (!{'note', 'article'}.contains(collection) || editorType == null)) {
      throw ArgumentError('Actual note scope required');
    }
    final table = note ? 'notes' : 'documents',
        column = note ? 'content' : 'markdown';
    final scope = note
        ? 'id=? AND collection=? AND editor_type=? AND deleted=0'
        : "document_id=? AND deleted=0 AND doc_type!='html'";
    final args = note ? <Object?>[id, collection, editorType] : <Object?>[id];
    guard();
    final sizes = await tx.rawQuery(
      'SELECT length(CAST($column AS BLOB)) AS n FROM $table WHERE $scope',
      args,
    );
    guard();
    final size = sizes.length == 1 ? sizes.single['n'] : null;
    if (size is! int || size < 0) throw StateError('Search source changed');
    final scan = _Scan(query);
    final decoder = const Utf8Decoder(
      allowMalformed: false,
    ).startChunkedConversion(_TextSink(scan.add));
    for (var offset = 0; offset < size;) {
      guard();
      final count = math.min(chunkBytes, size - offset);
      final rows = await tx.rawQuery(
        'SELECT substr(CAST($column AS BLOB),?,?) AS bytes FROM $table WHERE $scope',
        [offset + 1, count, ...args],
      );
      guard();
      final bytes = rows.length == 1 ? rows.single['bytes'] : null;
      if (bytes is! Uint8List || bytes.length != count) {
        throw StateError('Search source incomplete');
      }
      // Dart's decoder discards one initial BOM; restore exactly that one without
      // changing its strict decoding, including a second ordinary BOM.
      if (offset == 0 &&
          bytes.length >= 3 &&
          bytes[0] == 239 &&
          bytes[1] == 187 &&
          bytes[2] == 191) {
        scan.add('\ufeff');
      }
      decoder.add(bytes);
      offset += count;
    }
    // A match never authorizes early return: malformed/incomplete trailing UTF8
    // must fail this same transaction, and retirement cancels before publishing.
    decoder.close();
    guard();
    return scan.finish();
  }
}

final class _TextSink implements Sink<String> {
  _TextSink(this.accept);
  final void Function(String) accept;
  @override
  void add(String value) => accept(value);
  @override
  void close() {}
}

final class _Scan {
  _Scan(this.query)
    : substring = RegExp(RegExp.escape(query), caseSensitive: false),
      word = RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(query)}' r'(?=$|[^A-Za-z0-9_])',
        caseSensitive: false,
      );
  final String query;
  final RegExp substring, word;
  String carry = '';
  int total = 0;
  int? matchIndex, start;
  bool wholeWord = false;
  final List<int> first = [], history = [], selected = [];
  void add(String text) {
    if (text.isEmpty) return;
    final window = carry + text;
    final carryRunes = carry.runes.length;
    final windowBase = total - carryRunes;
    if (matchIndex == null) {
      final found = substring.firstMatch(window);
      if (found != null) {
        matchIndex = windowBase + window.substring(0, found.start).runes.length;
        final half = (150 - query.runes.length) ~/ 2;
        start = math.max(0, matchIndex! - half);
        // Long direct-helper queries may complete across blocks after their
        // 150-rune centered snippet has already passed. Keep that exact portion
        // from the regex overlap, not only the fixed short-query history.
        final prefix = carryRunes > history.length
            ? carry.runes.toList(growable: false)
            : history;
        final prefixBase = total - prefix.length;
        for (var i = 0; i < prefix.length && selected.length < 150; i++) {
          if (prefixBase + i >= start!) selected.add(prefix[i]);
        }
      }
    }
    _word(window, windowBase, false);
    final runes = text.runes.toList(growable: false);
    if (first.length < 150) first.addAll(runes.take(150 - first.length));
    if (start != null && selected.length < 150) {
      for (
        var i = math.max(0, start! - total);
        i < runes.length && selected.length < 150;
        i++
      ) {
        selected.add(runes[i]);
      }
    }
    total += runes.length;
    history.addAll(runes);
    if (history.length > 300) history.removeRange(0, history.length - 300);
    // Rune-based suffix cannot split a surrogate pair. query.length is UTF16,
    // therefore enough even for a query crossing both byte/UTF16 block boundaries.
    final keep = query.length + 2;
    final all = window.runes.toList(growable: false);
    carry = String.fromCharCodes(all.skip(math.max(0, all.length - keep)));
  }

  void _word(String window, int base, bool eof) {
    if (wholeWord) return;
    for (final match in word.allMatches(window)) {
      // At a noninitial overlap boundary the missing left neighbor is not proof;
      // any complete match here was already considered in the previous block.
      if (base > 0 && match.start == 0) continue;
      if (match.end == window.length && !eof) continue;
      wholeWord = true;
      return;
    }
  }

  LocalSearchBodyScan finish() {
    _word(carry, total - carry.runes.length, true);
    if (matchIndex == null) {
      return LocalSearchBodyScan(
        wholeWord: wholeWord,
        snippet: String.fromCharCodes(first) + (total > 150 ? '...' : ''),
      );
    }
    final nearEnd = total - start! < 150;
    final actualStart = nearEnd ? math.max(0, total - 150) : start!;
    final content = nearEnd
        ? history.skip(math.max(0, history.length - 150))
        : selected;
    return LocalSearchBodyScan(
      wholeWord: wholeWord,
      snippet:
          (actualStart > 0 ? '...' : '') +
          String.fromCharCodes(content) +
          (actualStart + 150 < total ? '...' : ''),
    );
  }
}
