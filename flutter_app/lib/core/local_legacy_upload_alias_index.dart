import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'local_generation_content_repository.dart';
import 'local_html_preview_document.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'local_data_paths.dart';
import 'local_legacy_upload_alias_policy.dart';

part 'local_legacy_upload_resource_bytes.dart';

/// Metadata only: callers still verify private file bytes, resource approval,
/// MIME and lease both before and after reading. No file/network handle exists.
final class LegacyUploadAliasReference {
  const LegacyUploadAliasReference._(
    this.generationId,
    this.sourceSha256,
    this.attachmentId,
    this.sha256Hex,
    this.bytes,
    this._current,
  );
  final String generationId, sourceSha256, attachmentId, sha256Hex;
  final int bytes;
  final bool Function() _current;
  bool get isCurrent => _current();
}

final class LegacyUploadAliasIndex {
  LegacyUploadAliasIndex({
    required Database database,
    required LocalDataPaths generation,
    required this.sourceSha256,
    required this.policy,
    required bool Function() isCurrent,
  }) : _database = database,
       _generation = generation,
       _leaseCurrent = isCurrent {
    if (generation.generationId == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256) ||
        !paths.isAbsolute(database.path) ||
        paths.normalize(database.path) !=
            paths.normalize(generation.databasePath)) {
      throw ArgumentError('Expected a matching owned generation database');
    }
  }
  final Database _database;
  final LocalDataPaths _generation;
  final bool Function() _leaseCurrent;
  final String sourceSha256;
  final LegacyUploadAliasPolicy policy;
  bool _closed = false, _retired = false;
  void dispose() {
    _closed = true;
  }

  bool _live() {
    if (_closed || _retired) {
      return false;
    }
    try {
      if (!_leaseCurrent()) {
        _retired = true;
        return false;
      }
      return true;
    } catch (_) {
      _retired = true;
      return false;
    }
  }

  Future<LegacyUploadAliasReference?> lookup(
    String rawUrl, {
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    if (maxBytes < 0 || maxBytes > 20 * 1024 * 1024) {
      throw ArgumentError('Expected a bounded inline resource size');
    }
    if (!_live()) {
      return null;
    }
    final alias = policy.canonicalPath(rawUrl);
    if (alias == null) {
      return null;
    }
    try {
      final version = await _database.rawQuery('PRAGMA user_version');
      if (!_live() ||
          version.length != 1 ||
          version.single.values.single != 15) {
        return null;
      }
      final rows = await _database.rawQuery(
        'SELECT b.attachment_id,b.source_sha256,b.file_sha256,b.file_size,'
        'typeof(b.attachment_id) AS id_type,typeof(b.source_sha256) AS source_type,'
        'typeof(b.file_sha256) AS hash_type,typeof(b.file_size) AS size_type '
        'FROM legacy_import_upload_blobs b JOIN legacy_import_sources s '
        'ON s.source_sha256=b.source_sha256 '
        "WHERE b.source_sha256=? AND b.alias_path=? AND s.source_kind='go_zip_v1' "
        'AND EXISTS (SELECT 1 FROM legacy_import_upload_bindings u '
        'JOIN legacy_import_records r ON r.source_sha256=u.source_sha256 '
        'AND r.kind=u.upload_kind AND r.local_id=u.upload_id '
        "WHERE u.source_sha256=b.source_sha256 AND u.attachment_id=b.attachment_id AND u.upload_kind='upload' AND u.role IN ('original','thumbnail'))",
        [sourceSha256, alias],
      );
      if (!_live() || rows.length != 1) {
        return null;
      }
      final row = rows.single,
          id = row['attachment_id'],
          hash = row['file_sha256'],
          size = row['file_size'];
      if (row['id_type'] != 'text' ||
          row['source_type'] != 'text' ||
          row['hash_type'] != 'text' ||
          row['size_type'] != 'integer' ||
          row['source_sha256'] != sourceSha256 ||
          id is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          size is! int ||
          size < 0 ||
          size > maxBytes) {
        return null;
      }
      if (!_live()) {
        return null;
      }
      return LegacyUploadAliasReference._(
        _generation.generationId!,
        sourceSha256,
        id,
        hash,
        size,
        _live,
      );
    } catch (_) {
      return null;
    }
  }
}
