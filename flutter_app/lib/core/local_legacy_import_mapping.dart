import 'dart:convert';
import 'local_legacy_format_selection.dart';
import 'local_legacy_go_export.dart';
import 'local_legacy_import_identities.dart';
import 'local_legacy_import_relations.dart';

enum LegacyMappingReason { invalidRecipe, unsupportedDocumentFormat }

final class LegacyMappingFailure implements Exception {
  const LegacyMappingFailure(this.reason);
  final LegacyMappingReason reason;
  @override
  String toString() => 'Legacy format mapping failed';
}

/// Binds explicit picker results to the REAL inspected source and its IDs.
/// This is not an import receipt or a candidate/activation readiness verdict.
final class LegacyImportMapping {
  LegacyImportMapping._({
    required this.identities,
    required this.relations,
    required this.recipeSha256,
    required this.recipeJson,
    required Map<int, LegacyContentFormat> noteFormats,
    required Map<int, LegacyContentFormat> documentFormats,
    required List<LegacyGoIssue> unresolvedIssues,
  }) : noteFormats = Map.unmodifiable(noteFormats),
       documentFormats = Map.unmodifiable(documentFormats),
       unresolvedIssues = List.unmodifiable(unresolvedIssues);
  final LegacyImportIdentities identities;
  final LegacyImportRelations relations;
  final String recipeSha256, recipeJson;
  String get sourceSha256 => identities.sourceSha256;
  final Map<int, LegacyContentFormat> noteFormats, documentFormats;
  // Unknown metadata, protection and missing uploads are NOT acknowledged here.
  final List<LegacyGoIssue> unresolvedIssues;

  factory LegacyImportMapping.fromRecipe(
    LegacyGoExport source,
    Map<String, Object?> recipe, {
    required String scopeKey,
  }) {
    final identities = LegacyImportIdentities.fromExport(source);
    final relations = LegacyImportRelations.fromExport(source, identities);
    late final LegacyFormatSelection choices;
    try {
      // Rebuild from inspected rows. Never trust picker-owned title/body/hash
      // objects merely because they carry a matching archive hash.
      final realSource = LegacyFormatSource.fromInspection(
        source,
        scopeKey: scopeKey,
      );
      choices = LegacyFormatSelection.fromJson(realSource, recipe);
    } on FormatException {
      throw const LegacyMappingFailure(LegacyMappingReason.invalidRecipe);
    }
    final notes = <int, LegacyContentFormat>{};
    for (final entry in choices.choices.entries) {
      notes[identities.lookup(LegacyImportKind.note, [entry.key]).localId] =
          entry.value;
    }
    final documents = <int, LegacyContentFormat>{};
    for (final book in source.sections['books.json'] as List) {
      final row = book as Map;
      for (final value in row['documents'] as List) {
        final doc = value as Map;
        late final LegacyContentFormat format;
        try {
          format = LegacyContentFormat.parse(doc['doc_type'] as String);
        } on FormatException {
          throw const LegacyMappingFailure(
            LegacyMappingReason.unsupportedDocumentFormat,
          );
        }
        final identity = identities.lookup(LegacyImportKind.document, [
          row['identify'] as String,
          doc['identify'] as String,
        ]);
        documents[identity.localId] = format;
      }
    }
    return LegacyImportMapping._(
      identities: identities,
      relations: relations,
      recipeSha256: choices.digest,
      recipeJson: jsonEncode(choices.toJson()),
      noteFormats: notes,
      documentFormats: documents,
      unresolvedIssues: source.issues
          .where((issue) => issue.code != LegacyGoIssueCode.editorTypeMissing)
          .toList(),
    );
  }
}
