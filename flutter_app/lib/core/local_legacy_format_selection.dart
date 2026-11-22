import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_go_export.dart';

enum LegacyContentFormat {
  markdown,
  html,
  spreadsheet,
  drawing,
  mindmap,
  richdoc,
  presentation;

  static LegacyContentFormat parse(String value) => values.firstWhere(
    (format) => format.name == value,
    orElse: () => throw const FormatException('Unknown legacy content format'),
  );
}

final class LegacyFormatItem {
  const LegacyFormatItem({
    required this.id,
    required this.title,
    required this.collection,
    required this.originalBody,
    required this.passwordHash,
  });
  final String id, title, collection, originalBody, passwordHash;
  bool get isProtected =>
      passwordHash.isNotEmpty || originalBody.startsWith('ENC:');
}

/// Stable source identity plus an ephemeral picker/inspection lifetime.
/// No editor type is inferred from the title, body or collection.
final class LegacyFormatSource {
  LegacyFormatSource({
    required this.archiveSha256,
    required this.scopeKey,
    required List<LegacyFormatItem> items,
  }) : items = List.unmodifiable(items) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(archiveSha256) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(scopeKey) ||
        items.length > 100000) {
      throw const FormatException('Invalid legacy format source identity');
    }
    final index = <String, LegacyFormatItem>{};
    for (final item in items) {
      if (item.id.isEmpty ||
          utf8.encode(item.id).length > 1024 ||
          !{'note', 'article'}.contains(item.collection) ||
          index.containsKey(item.id)) {
        throw const FormatException('Invalid legacy format item identity');
      }
      index[item.id] = item;
    }
    byId = Map.unmodifiable(index);
  }
  factory LegacyFormatSource.fromInspection(
    LegacyGoExport inspection, {
    required String scopeKey,
  }) {
    final blogs = inspection.sections['blogs.json'] as List;
    return LegacyFormatSource(
      archiveSha256: inspection.sourceSha256,
      scopeKey: scopeKey,
      items: [
        for (final value in blogs)
          LegacyFormatItem(
            id: (value as Map)['blog_identify'] as String,
            title: value['blog_title'] as String,
            collection: value['blog_type'] as String,
            originalBody: value['blog_content'] as String,
            passwordHash: value['password'] as String,
          ),
      ],
    );
  }
  final String archiveSha256, scopeKey;
  final List<LegacyFormatItem> items;
  late final Map<String, LegacyFormatItem> byId;
}

/// Only explicit user choices, bound to archive bytes. No passwords or bodies
/// are included in the serializable recipe, and applying it never writes data.
final class LegacyFormatSelection {
  LegacyFormatSelection(
    this.source, {
    Map<String, LegacyContentFormat> choices = const {},
  }) : choices = Map.unmodifiable(choices) {
    if (choices.keys.any((id) => !source.byId.containsKey(id))) {
      throw const FormatException('Format choice belongs to another source');
    }
  }
  final LegacyFormatSource source;
  final Map<String, LegacyContentFormat> choices;
  int get unresolved => source.items.length - choices.length;
  bool get complete => unresolved == 0;

  LegacyFormatSelection choose(String id, LegacyContentFormat format) {
    if (!source.byId.containsKey(id)) {
      throw const FormatException('Unknown legacy format item');
    }
    return LegacyFormatSelection(source, choices: {...choices, id: format});
  }

  LegacyFormatSelection chooseMissing(LegacyContentFormat format) =>
      LegacyFormatSelection(
        source,
        choices: {
          for (final item in source.items) item.id: choices[item.id] ?? format,
        },
      );

  Map<String, Object?> toJson() {
    if (!complete) throw StateError('Legacy content formats are incomplete');
    final ids = choices.keys.toList()..sort();
    return {
      'version': 1,
      'source_sha256': source.archiveSha256,
      'editors': [
        for (final id in ids) {'identify': id, 'format': choices[id]!.name},
      ],
    };
  }

  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  factory LegacyFormatSelection.fromJson(
    LegacyFormatSource source,
    Map<String, Object?> value,
  ) {
    if (value.length != 3 ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['source_sha256'] != source.archiveSha256 ||
        value['editors'] is! List) {
      throw const FormatException('Format recipe source or version differs');
    }
    final rows = value['editors'] as List;
    if (rows.length != source.items.length) {
      throw const FormatException('Format recipe does not cover the source');
    }
    final choices = <String, LegacyContentFormat>{};
    for (final row in rows) {
      if (row is! Map ||
          row.length != 2 ||
          row['identify'] is! String ||
          row['format'] is! String ||
          choices.containsKey(row['identify'])) {
        throw const FormatException('Invalid or duplicated format choice');
      }
      choices[row['identify'] as String] = LegacyContentFormat.parse(
        row['format'] as String,
      );
    }
    final result = LegacyFormatSelection(source, choices: choices);
    if (!result.complete) {
      throw const FormatException('Incomplete format recipe');
    }
    return result;
  }
}
