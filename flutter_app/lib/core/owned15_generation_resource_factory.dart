import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:sqflite/sqflite.dart';
import 'complex_editor_document.dart';
import 'owned_complex_document_references.dart';
import 'local_generation_content_repository.dart';
import 'local_legacy_upload_alias_index.dart';
import 'local_legacy_upload_alias_policy.dart';
import 'owned_writable_generation15.dart';
import 'owned15_generation_resources.dart';

/// This factory requires the sealed writable owner. A review session, Database,
/// generation path or readonly content repository cannot substitute for it.
Future<Owned15GenerationResources?> bindOwned15GenerationResources({
  required OwnedWritableGeneration15 owner,
  required GenerationContentHandle content,
  required ComplexEditorDocument document,
  required String fullFingerprint,
  required bool Function() isCurrent,
}) async {
  bool current() {
    try {
      return owner.current &&
          content.isCurrent &&
          isCurrent() &&
          content.metadata.generationId == owner.generation.generationId;
    } catch (_) {
      return false;
    }
  }

  if (!current() ||
      document.source != content.source ||
      document.kind.name != content.metadata.format.name) {
    return null;
  }
  await owner.confirmCurrent();
  final sourceRows = await owner.exclusiveSnapshot(
    (db) => db.rawQuery(
      'SELECT r.source_sha256,typeof(r.source_sha256) AS source_type '
      'FROM legacy_import_records r JOIN legacy_import_sources s '
      'ON s.source_sha256=r.source_sha256 '
      "WHERE r.kind='note' AND r.local_id=? AND s.source_kind='go_zip_v1'",
      [content.metadata.id],
    ),
  );
  if (!current() || sourceRows.length != 1) return null;
  final row = sourceRows.single, source = row['source_sha256'];
  if (row['source_type'] != 'text' ||
      source is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(source)) {
    return null;
  }
  final policy = LegacyUploadAliasPolicy(
    isolatedOrigin: Uri.parse(
      'https://${owner.generation.generationId}.bookstark-local.invalid',
    ),
  );
  final refs = <String>{};
  void add(String? raw) {
    if (raw == null) return;
    final canonical = policy.canonicalPath(raw);
    if (canonical == null) return;
    refs.add(canonical);
    if (refs.length > 32) throw const FormatException('Resource limit');
  }

  try {
    if (document.kind == ComplexEditorKind.markdown) {
      final visitor = _ImageVisitor(add);
      final nodes = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
      ).parseLines(const LineSplitter().convert(document.source));
      for (final node in nodes) {
        node.accept(visitor);
      }
    } else {
      final captured = OwnedComplexDocumentReferences.capture(
        document,
        fullFingerprint: fullFingerprint,
      );
      for (final uri in captured.references) {
        add(uri.toString());
      }
    }
  } catch (_) {
    // Too many or unsupported references cannot stop reading/editing the body.
    return null;
  }
  if (!current()) return null;
  final index = LegacyUploadAliasIndex(
    database: _OwnedAssetMetadata(owner, current),
    generation: owner.generation,
    sourceSha256: source,
    policy: policy,
    isCurrent: current,
  );
  return Owned15GenerationResources(
    index: index,
    content: content,
    generation: owner.generation,
    sourceDigest: document.digest,
    fullFingerprint: fullFingerprint,
    scopeIdentity: sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned15-raster-v1',
              owner.pointer.encode(),
              content.metadata.collection,
              content.metadata.id,
              content.resourceFingerprint,
              fullFingerprint,
              document.digest,
            ]),
          ),
        )
        .toString(),
    references: refs,
    isCurrent: current,
    confirmCurrent: owner.confirmCurrent,
  );
}

final class _ImageVisitor implements md.NodeVisitor {
  _ImageVisitor(this.add);
  final void Function(String?) add;
  @override
  bool visitElementBefore(md.Element element) {
    if (element.tag == 'img') add(element.attributes['src']);
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {}
  @override
  void visitText(md.Text text) {}
}

/// Never leaks the writable SQLite handle out of the owner's maintenance gate.
final class _OwnedAssetMetadata implements Database {
  _OwnedAssetMetadata(this.owner, this.current);
  final OwnedWritableGeneration15 owner;
  final bool Function() current;
  @override
  String get path => owner.generation.databasePath;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (!current()) throw StateError('Generation resource retired');
    return owner.exclusiveSnapshot((db) async {
      if (!current()) throw StateError('Generation resource retired');
      final result = await db.rawQuery(sql, arguments);
      if (!current()) throw StateError('Generation resource retired');
      return result;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Metadata-only resource handle');
}
