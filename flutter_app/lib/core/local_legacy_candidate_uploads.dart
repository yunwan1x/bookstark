import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_legacy_go_export.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_import_identities.dart';
import 'local_legacy_zip_stage.dart';

enum LegacyUploadReason {
  incompatibleSchema,
  nonemptyCandidate,
  sourceMismatch,
  unresolvedSource,
  ambiguousPath,
  missingBlob,
  integrity,
  collision,
  storage,
}

final class LegacyUploadFailure implements Exception {
  const LegacyUploadFailure(this.reason);
  final LegacyUploadReason reason;
  @override
  String toString() => 'Legacy upload files could not be prepared';
}

enum LegacyUploadRole { original, thumbnail }

final class LegacyUploadBlob {
  const LegacyUploadBlob._(
    this.logicalName,
    this.attachmentId,
    this.aliasPath,
    this.staged,
  );
  final String logicalName, attachmentId, aliasPath;
  final LegacyStagedFile staged;
  int get bytes => staged.bytes;
  String get sha256Hex => staged.sha256Hex;
}

final class LegacyUploadBinding {
  const LegacyUploadBinding._(this.uploadId, this.role, this.blob);
  final int uploadId;
  final LegacyUploadRole role;
  final LegacyUploadBlob blob;
}

/// Data-only; no files copied, source rewritten, SQL changed or lease approved.
final class LegacyCandidateUploads {
  LegacyCandidateUploads._(
    this.sourceSha256,
    this.recipeSha256,
    List<LegacyUploadBlob> blobs,
    List<LegacyUploadBinding> bindings,
    this.uploadRows,
  ) : blobs = List.unmodifiable(blobs),
      bindings = List.unmodifiable(bindings);
  final String sourceSha256, recipeSha256;
  final List<LegacyUploadBlob> blobs;
  final List<LegacyUploadBinding> bindings;
  final int uploadRows;
  int get totalBytes => blobs.fold(0, (sum, blob) => sum + blob.bytes);
  String get planSha256 => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'domain': 'bookstark-legacy-upload-plan-v1',
            'source': sourceSha256,
            'recipe': recipeSha256,
            'blobs': [
              for (final b in blobs)
                [
                  b.logicalName,
                  b.attachmentId,
                  b.aliasPath,
                  b.bytes,
                  b.sha256Hex,
                ],
            ],
            'bindings': [
              for (final b in bindings)
                [b.uploadId, b.role.name, b.blob.attachmentId],
            ],
          }),
        ),
      )
      .toString();

  factory LegacyCandidateUploads.fromRecords(
    LegacyImportRecords records,
    LegacyZipStage stage, {
    bool Function()? isCancelled,
  }) {
    void check() {
      if (isCancelled?.call() == true) throw const LegacyRecordsCancelled();
    }

    check();
    final source = records.source, mapping = records.mapping;
    if (source.sourceSha256 != stage.sourceSha256 ||
        source.sourceSha256 != mapping.sourceSha256) {
      throw const LegacyUploadFailure(LegacyUploadReason.sourceMismatch);
    }
    const handled = {
      LegacyGoIssueCode.editorTypeMissing,
      LegacyGoIssueCode.protectedContent,
    };
    if (source.issues.any((issue) => !handled.contains(issue.code))) {
      throw const LegacyUploadFailure(LegacyUploadReason.unresolvedSource);
    }
    final rows = (source.sections['uploads.json'] as List)
        .cast<Map<String, Object?>>();
    final blobs = <String, LegacyUploadBlob>{},
        aliases = <String, String>{},
        ids = <String, String>{};
    final bindings = <LegacyUploadBinding>[];
    for (final row in rows) {
      check();
      final id = mapping.identities.lookup(LegacyImportKind.upload, [
        row['storage_path'] as String,
      ]).localId;
      for (final role in LegacyUploadRole.values) {
        check();
        final path =
            row[role == LegacyUploadRole.original
                    ? 'storage_path'
                    : 'thumb_path']
                as String;
        final bytes =
            row[role == LegacyUploadRole.original ? 'file_size' : 'thumb_size']
                as int;
        if (path.isEmpty && role == LegacyUploadRole.thumbnail && bytes == 0) {
          continue;
        }
        if (path.isEmpty ||
            path.contains(RegExp(r'[%?#\\:]')) ||
            path.codeUnits.any((c) => c < 32 || c == 127) ||
            path
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..')) {
          throw const LegacyUploadFailure(LegacyUploadReason.ambiguousPath);
        }
        final logical = 'uploads/$path';
        final staged = stage.files[logical];
        if (staged == null) {
          throw const LegacyUploadFailure(LegacyUploadReason.missingBlob);
        }
        if (staged.logicalName != logical ||
            staged.bytes != bytes ||
            bytes < 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(staged.sha256Hex) ||
            role == LegacyUploadRole.original &&
                staged.sha256Hex !=
                    (row['file_hash'] as String).toLowerCase()) {
          throw const LegacyUploadFailure(LegacyUploadReason.integrity);
        }
        var blob = blobs[logical];
        if (blob == null) {
          final attachment = sha256
              .convert(
                utf8.encode(
                  jsonEncode([
                    'bookstark-legacy-upload-v1',
                    source.sourceSha256,
                    logical,
                  ]),
                ),
              )
              .toString()
              .substring(0, 32);
          final alias = Uri(
            pathSegments: ['', 'upload-files', ...path.split('/')],
          ).path;
          final folded = alias.toLowerCase();
          if (ids.containsKey(attachment) && ids[attachment] != logical ||
              aliases.containsKey(folded) && aliases[folded] != logical) {
            throw const LegacyUploadFailure(LegacyUploadReason.collision);
          }
          ids[attachment] = logical;
          aliases[folded] = logical;
          blob = LegacyUploadBlob._(logical, attachment, alias, staged);
          blobs[logical] = blob;
        } else if (blob.bytes != bytes || blob.sha256Hex != staged.sha256Hex) {
          throw const LegacyUploadFailure(LegacyUploadReason.integrity);
        }
        bindings.add(LegacyUploadBinding._(id, role, blob));
      }
    }
    check();
    final stagedUploads = stage.files.keys
        .where((name) => name.startsWith('uploads/'))
        .toSet();
    if (stagedUploads.length != blobs.length ||
        !stagedUploads.containsAll(blobs.keys)) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    if (rows.length !=
        (mapping.identities.counts[LegacyImportKind.upload] ?? 0)) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    return LegacyCandidateUploads._(
      source.sourceSha256,
      mapping.recipeSha256,
      blobs.values.toList(),
      bindings,
      rows.length,
    );
  }
}
