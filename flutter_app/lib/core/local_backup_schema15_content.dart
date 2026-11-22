import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'bounded_note_text_reader.dart';
import 'complex_editor_document.dart';
import 'local_backup_codec.dart';
import 'local_content_crypto_limits.dart';
import 'local_content_protection_format.dart';
import 'local_legacy_import_records.dart';
import 'local_legacy_json.dart';
import 'local_legacy_upload_alias_policy.dart';

/// Read-only stored-state checks. Never unlocks, normalizes, encrypts, rewrites
/// provenance, or claims its opaque source ID re-proves an original ZIP's hash.
Future<void> verifySchema15BackupContent(
  Database db,
  LocalBackupManifest manifest,
) => _Schema15Content(db, manifest).verify();

class _Schema15Content {
  _Schema15Content(this.db, this.manifest);
  final Database db;
  final LocalBackupManifest manifest;
  final recipes = <String, String>{};
  final _clock = Stopwatch()..start();
  bool hex(Object? v, int n) =>
      v is String &&
      RegExp(
        '^[a-f0-9]{$n}'
        r'$',
      ).hasMatch(v);
  void guard() {
    if (_clock.elapsed > const Duration(minutes: 3)) {
      throw const FormatException('Schema15 verification deadline');
    }
  }

  Future<void> bad(String sql) async {
    guard();
    final value = (await db.rawQuery(sql)).single.values.single;
    guard();
    if (value != 0) {
      throw const FormatException('Invalid schema15 reference or metadata');
    }
  }

  Stream<Map<String, Object?>> rows(String table) async* {
    const fields = {
      'legacy_import_sources': (
        ['source_sha256', 'source_kind', 'imported_at'],
        <String>[],
      ),
      'legacy_import_records': (
        ['kind', 'source_sha256', 'payload_sha256'],
        ['local_id'],
      ),
      'legacy_import_label_relations': (
        ['source_sha256', 'resource_kind', 'payload_sha256'],
        ['label_id', 'resource_id'],
      ),
      'legacy_import_upload_blobs': (
        [
          'attachment_id',
          'source_sha256',
          'logical_name',
          'alias_path',
          'file_sha256',
        ],
        ['file_size'],
      ),
      'notes': (['collection', 'editor_type', 'password_hash'], ['id']),
    };
    final spec = fields[table];
    if (spec == null) {
      throw const FormatException('Schema15 metadata table unavailable');
    }
    final projection = <String>[];
    for (final col in spec.$1) {
      projection.add(
        'CASE WHEN length(CAST("$col" AS BLOB))<=262144 THEN CAST("$col" AS BLOB) END AS "$col"',
      );
    }
    projection.addAll(spec.$2.map((col) => '"$col"'));
    if (table == 'notes') {
      projection.add('typeof(content) AS _body_type');
      projection.add(
        'EXISTS(SELECT 1 FROM html_creation_receipts h WHERE h.note_id=notes.id) AS _has_creation_receipt',
      );
    }
    int? cursor;
    while (true) {
      guard();
      final found = await db.rawQuery(
        'SELECT rowid AS _rowid,${projection.join(',')} FROM "$table" ${cursor == null ? '' : 'WHERE rowid>? '}ORDER BY rowid LIMIT 64',
        cursor == null ? const [] : [cursor],
      );
      guard();
      if (found.isEmpty) return;
      for (final raw in found) {
        final row = Map<String, Object?>.from(raw);
        for (final col in spec.$1) {
          final bytes = row[col];
          if (bytes is! Uint8List) {
            throw const FormatException('Schema15 metadata type or bound');
          }
          row[col] = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
        }
        yield row;
      }
      cursor = found.last['_rowid'] as int;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<Uint8List> cell(
    String table,
    String column,
    int id,
    int maximum,
  ) async {
    guard();
    final length = (await db.rawQuery(
      'SELECT length(CAST("$column" AS BLOB)) AS n FROM "$table" WHERE rowid=?',
      [id],
    )).single['n'];
    if (length is! int || length < 0 || length > maximum) {
      throw const FormatException('Schema15 stored cell bound');
    }
    final result = Uint8List(length);
    for (var offset = 0; offset < length;) {
      guard();
      final size = (length - offset).clamp(0, 256 * 1024);
      final part = (await db.rawQuery(
        'SELECT substr(CAST("$column" AS BLOB),?,?) AS b FROM "$table" WHERE rowid=?',
        [offset + 1, size, id],
      )).single['b'];
      if (part is! Uint8List || part.length != size) {
        throw const FormatException('Schema15 stored cell incomplete');
      }
      result.setRange(offset, offset + size, part);
      offset += size;
    }
    guard();
    return result;
  }

  Future<Map<String, Object?>> object(
    String table,
    String column,
    int id,
    int max,
  ) async {
    final data = decodeLegacyJson(
      await cell(table, column, id, max),
      limits: LegacyJsonLimits(
        maxBytes: max,
        maxDepth: 52,
        maxNodes: 2000000,
        maxObjectMembers: 512,
      ),
    );
    if (data is! Map<String, Object?>) {
      throw const FormatException('Schema15 object required');
    }
    return data;
  }

  Future<void> verify() async {
    if (manifest.databaseSchema != 15) {
      throw const FormatException('Schema15 manifest required');
    }
    await bad(
      "SELECT count(*) FROM notes WHERE revision<=0 OR is_pinned NOT IN (0,1)",
    );
    await bad("SELECT count(*) FROM documents WHERE revision<=0");
    await bad("SELECT count(*) FROM topic_comments WHERE parent_comment_id<0");
    // Existing writer admits one original Go ZIP into an empty new generation.
    if ((await db.rawQuery(
          'SELECT count(*) AS n FROM legacy_import_sources',
        )).single['n'] !=
        1) {
      throw const FormatException(
        'Schema15 requires one retained original source',
      );
    }
    await for (final row in rows('legacy_import_sources')) {
      final source = row['source_sha256'];
      if (!hex(source, 64) ||
          row['source_kind'] != 'go_zip_v1' ||
          row['imported_at'] is! String ||
          DateTime.tryParse(row['imported_at'] as String) == null) {
        throw const FormatException('Schema15 source identity');
      }
      final id = row['_rowid'] as int;
      final original = await object(
        'legacy_import_sources',
        'manifest_json',
        id,
        8 * 1024 * 1024,
      );
      if (original['version'] != 1 ||
          original['source'] != 'bookstark' ||
          original['stats'] is! Map) {
        throw const FormatException('Schema15 original export metadata');
      }
      final rawRecipe = await cell(
        'legacy_import_sources',
        'format_recipe_json',
        id,
        8 * 1024 * 1024,
      );
      final recipe = decodeLegacyJson(
        rawRecipe,
        limits: const LegacyJsonLimits(maxBytes: 8 * 1024 * 1024),
      );
      if (recipe is! Map ||
          recipe['version'] != 1 ||
          recipe['source_sha256'] != source ||
          recipe['editors'] is! List) {
        throw const FormatException('Schema15 format recipe');
      }
      final choices = <String>{};
      for (final choice in recipe['editors'] as List) {
        if (choice is! Map ||
            choice['identify'] is! String ||
            choice['format'] is! String ||
            !choices.add(choice['identify'] as String)) {
          throw const FormatException('Schema15 format choice');
        }
        ComplexEditorKind.parse(choice['format'] as String);
      }
      recipes[source as String] = sha256.convert(rawRecipe).toString();
      const counts = {
        'book': 'books',
        'document': 'documents',
        'note': 'blogs',
        'bookmark': 'bookmarks',
        'task': 'tasks',
        'topic': 'topics',
        'label': 'labels',
        'friendLink': 'friend_links',
        'upload': 'uploads',
      };
      for (final entry in counts.entries) {
        final n = (await db.rawQuery(
          'SELECT count(*) AS n FROM legacy_import_records WHERE source_sha256=? AND kind=?',
          [source, entry.key],
        )).single['n'];
        if ((original['stats'] as Map)[entry.value] != n) {
          throw const FormatException('Schema15 original count mismatch');
        }
      }
    }
    await for (final row in rows('notes')) {
      guard();
      final hash = row['password_hash'];
      if (hash is! String) {
        throw const FormatException('Schema15 password metadata');
      }
      final kind = ComplexEditorKind.parse(row['editor_type'] as String);
      final bodyType = row['_body_type'];
      final hasCreationReceipt = row['_has_creation_receipt'];
      if (!const {'text', 'blob'}.contains(bodyType) ||
          !const {0, 1}.contains(hasCreationReceipt)) {
        throw const FormatException('Schema15 stored content type');
      }
      final stored = await cell(
        'notes',
        'content',
        row['_rowid'] as int,
        localCryptoMaxWireBytes,
      );
      final String source;
      try {
        source = BoundedNoteTextReader.decodeUtf8PreservingBom(stored);
      } on FormatException {
        // Full backup preserves an old opaque raw note, without granting a
        // reader/writer capability or accepting malformed new/protected data.
        if (bodyType != 'blob' ||
            row['collection'] != 'note' ||
            kind != ComplexEditorKind.markdown ||
            hash.isNotEmpty ||
            hasCreationReceipt != 0) {
          rethrow;
        }
        continue;
      }
      // Preserve legal historical hash+plaintext exactly. Do not silently encrypt
      // it just to make a backup notice claim ciphertext-only.
      if (!localProtectedRecordSupported(hash, source)) {
        throw const FormatException('Schema15 stored protection state');
      }
      if (!source.startsWith('ENC:')) ComplexEditorDocument.parse(kind, source);
    }
    final targets = {
      'book': ('books', 'book_id'),
      'document': ('documents', 'document_id'),
      'note': ('notes', 'id'),
      'bookmark': ('bookmarks', 'bookmark_id'),
      'task': ('tasks', 'task_id'),
      'topic': ('topics', 'topic_id'),
      'summary': ('topic_summaries', 'summary_id'),
      'topicResource': ('topic_resources', 'topic_resource_id'),
      'comment': ('topic_comments', 'comment_id'),
      'label': ('local_labels', 'label_id'),
      'friendLink': ('legacy_friend_links', 'link_id'),
    };
    final historical = <String, Map<String, Object?>>{};
    final ordinals = <String, Set<int>>{};
    await for (final row in rows('legacy_import_records')) {
      guard();
      final source = row['source_sha256'],
          kind = row['kind'],
          id = row['local_id'];
      if (source is! String ||
          !recipes.containsKey(source) ||
          kind is! String ||
          id is! int ||
          id <= 0 ||
          !hex(row['payload_sha256'], 64)) {
        throw const FormatException('Schema15 record identity');
      }
      final payloadBytes = await cell(
        'legacy_import_records',
        'payload',
        row['_rowid'] as int,
        LegacyImportRecords.maxPayloadBytes,
      );
      if (sha256.convert(payloadBytes).toString() != row['payload_sha256']) {
        throw const FormatException('Schema15 payload hash');
      }
      final payload = decodeLegacyJson(
        payloadBytes,
        limits: const LegacyJsonLimits(
          maxBytes: LegacyImportRecords.maxPayloadBytes,
          maxDepth: 52,
          maxNodes: 2000000,
          maxObjectMembers: 512,
        ),
      );
      if (payload is! Map ||
          payload['version'] != 1 ||
          payload['source_sha256'] != source ||
          payload['kind'] != kind ||
          payload['local_id'] != id ||
          payload['format_recipe_sha256'] != recipes[source] ||
          payload['source_ordinal'] is! int ||
          (payload['source_ordinal'] as int) < 0 ||
          payload['fields'] is! Map ||
          payload['source_key'] is! List ||
          (payload['source_key'] as List).any((v) => v is! String)) {
        throw const FormatException('Schema15 payload binding');
      }
      final key = BoundedNoteTextReader.decodeUtf8PreservingBom(
        await cell(
          'legacy_import_records',
          'source_key',
          row['_rowid'] as int,
          LegacyImportRecords.maxPayloadBytes,
        ),
      );
      if (jsonEncode(payload['source_key']) != key) {
        throw const FormatException('Schema15 source key differs');
      }
      final parent = payload['parent'];
      const parentKinds = {
        'document': 'book',
        'summary': 'topic',
        'topicResource': 'topic',
        'comment': 'topic',
      };
      final parentKind = parentKinds[kind];
      if (parentKind == null
          ? parent != null
          : parent is! Map ||
                parent['kind'] != parentKind ||
                parent['local_id'] is! int ||
                (parent['local_id'] as int) <= 0) {
        throw const FormatException('Schema15 provenance parent');
      }
      final ordinalGroup = jsonEncode([source, kind, parent]);
      if (!(ordinals[ordinalGroup] ??= <int>{}).add(
        payload['source_ordinal'] as int,
      )) {
        throw const FormatException('Schema15 duplicate source order');
      }
      final sections = payload['child_sections'];
      final expectedSections = kind == 'book'
          ? const ['documents']
          : kind == 'topic'
          ? const ['summaries', 'resources', 'comments']
          : const <String>[];
      if (expectedSections.isEmpty
          ? sections != null
          : sections is! Map ||
                sections.length != expectedSections.length ||
                !expectedSections.every((name) => sections.containsKey(name))) {
        throw const FormatException('Schema15 original child sections');
      }
      if (sections is Map) {
        for (final value in sections.values) {
          if (value is! Map ||
              value.length != 2 ||
              value['present'] is! bool ||
              value['count'] is! int ||
              (value['count'] as int) < 0 ||
              (value['present'] == false && value['count'] != 0)) {
            throw const FormatException('Schema15 original child count');
          }
        }
      }
      if (historical.length >= 1000000) {
        throw const FormatException('Schema15 provenance count limit');
      }
      historical[jsonEncode([source, kind, id])] = {
        'parent': parent,
        'sections': sections,
        'ordinal': payload['source_ordinal'],
      };
      if (kind == 'upload') {
        final fields = payload['fields'] as Map;
        final bindings = await db.rawQuery(
          'SELECT u.role,b.logical_name,b.file_size,b.file_sha256 '
          'FROM legacy_import_upload_bindings u JOIN legacy_import_upload_blobs b '
          'ON b.attachment_id=u.attachment_id AND b.source_sha256=u.source_sha256 '
          'WHERE u.source_sha256=? AND u.upload_id=?',
          [source, id],
        );
        var expected = 0;
        for (final role in const ['original', 'thumbnail']) {
          final path =
              fields[role == 'original' ? 'storage_path' : 'thumb_path'];
          final size = fields[role == 'original' ? 'file_size' : 'thumb_size'];
          if (path is! String || size is! int || size < 0) {
            throw const FormatException('Schema15 original upload fields');
          }
          if (role == 'thumbnail' && path.isEmpty && size == 0) continue;
          expected++;
          final matches = bindings.where((b) => b['role'] == role).toList();
          if (matches.length != 1 ||
              matches.single['logical_name'] != 'uploads/$path' ||
              matches.single['file_size'] != size ||
              (role == 'original' &&
                  (fields['file_hash'] is! String ||
                      matches.single['file_sha256'] !=
                          (fields['file_hash'] as String).toLowerCase()))) {
            throw const FormatException('Schema15 original upload binding');
          }
        }
        if (bindings.length != expected) {
          throw const FormatException('Schema15 unexpected upload binding');
        }
      }
      if (kind != 'upload') {
        final target = targets[kind];
        if (target == null) {
          throw const FormatException('Schema15 unknown target');
        }
        final exists = (await db.rawQuery(
          'SELECT count(*) AS n FROM "${target.$1}" WHERE "${target.$2}"=?',
          [id],
        )).single['n'];
        if (exists != 1) {
          throw const FormatException('Schema15 retained target missing');
        }
      }
    }
    for (final entry in historical.entries) {
      guard();
      final identity = jsonDecode(entry.key) as List;
      final parent = entry.value['parent'];
      if (parent is Map &&
          !historical.containsKey(
            jsonEncode([identity[0], parent['kind'], parent['local_id']]),
          )) {
        throw const FormatException('Schema15 historical parent missing');
      }
      final sections = entry.value['sections'];
      if (sections is Map) {
        const childKinds = {
          'documents': 'document',
          'summaries': 'summary',
          'resources': 'topicResource',
          'comments': 'comment',
        };
        for (final name in sections.keys) {
          final group = jsonEncode([
            identity[0],
            childKinds[name],
            {'kind': identity[1], 'local_id': identity[2]},
          ]);
          final count = (sections[name] as Map)['count'] as int;
          final actual = ordinals[group] ?? const <int>{};
          if (actual.length != count || actual.any((n) => n >= count)) {
            throw const FormatException(
              'Schema15 retained child count differs',
            );
          }
        }
      }
    }
    await for (final row in rows('legacy_import_label_relations')) {
      final source = row['source_sha256'];
      if (source is! String ||
          !recipes.containsKey(source) ||
          !hex(row['payload_sha256'], 64)) {
        throw const FormatException('Schema15 relation identity');
      }
      final bytes = await cell(
        'legacy_import_label_relations',
        'payload',
        row['_rowid'] as int,
        LegacyImportRecords.maxPayloadBytes,
      );
      if (sha256.convert(bytes).toString() != row['payload_sha256']) {
        throw const FormatException('Schema15 relation hash');
      }
      final value = decodeLegacyJson(
        bytes,
        limits: const LegacyJsonLimits(
          maxBytes: LegacyImportRecords.maxPayloadBytes,
          maxDepth: 52,
          maxNodes: 2000000,
          maxObjectMembers: 512,
        ),
      );
      if (value is! Map ||
          value['version'] != 1 ||
          value['source_sha256'] != source ||
          value['format_recipe_sha256'] != recipes[source] ||
          value['label_id'] != row['label_id'] ||
          value['resource_kind'] != row['resource_kind'] ||
          value['resource_id'] != row['resource_id'] ||
          value['fields'] is! Map ||
          value['source_ordinal'] is! int ||
          (value['source_ordinal'] as int) < 0) {
        throw const FormatException('Schema15 relation binding');
      }
    }
    await bad(
      'SELECT count(*) FROM legacy_import_label_relations r LEFT JOIN local_labels l ON l.label_id=r.label_id '
      'LEFT JOIN legacy_import_records t ON t.source_sha256=r.source_sha256 AND t.kind=r.resource_kind AND t.local_id=r.resource_id '
      'WHERE l.label_id IS NULL OR t.local_id IS NULL',
    );
    final files = {for (final f in manifest.files) f.path: f};
    final policy = LegacyUploadAliasPolicy(
      isolatedOrigin: Uri.parse('https://${'0' * 32}.bookstark-local.invalid'),
    );
    final folded = <String>{};
    await for (final row in rows('legacy_import_upload_blobs')) {
      final id = row['attachment_id'],
          source = row['source_sha256'],
          logical = row['logical_name'],
          alias = row['alias_path'];
      if (!hex(id, 32) ||
          source is! String ||
          !recipes.containsKey(source) ||
          logical is! String ||
          !logical.startsWith('uploads/') ||
          alias is! String ||
          policy.canonicalPath(alias) != alias ||
          !folded.add(alias.toLowerCase()) ||
          !hex(row['file_sha256'], 64) ||
          row['file_size'] is! int) {
        throw const FormatException('Schema15 upload metadata');
      }
      final relative = logical.substring(8);
      if (relative.isEmpty ||
          relative.contains(RegExp(r'[%?#\\:]')) ||
          relative.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
          relative.codeUnits.any((c) => c < 32 || c == 127) ||
          Uri(
                pathSegments: ['', 'upload-files', ...relative.split('/')],
              ).path !=
              alias ||
          sha256
                  .convert(
                    utf8.encode(
                      jsonEncode([
                        'bookstark-legacy-upload-v1',
                        source,
                        logical,
                      ]),
                    ),
                  )
                  .toString()
                  .substring(0, 32) !=
              id) {
        throw const FormatException('Schema15 upload alias identity');
      }
      final file = files['attachments/${id as String}'];
      if (file == null ||
          file.bytes != row['file_size'] ||
          file.sha256 != row['file_sha256']) {
        throw const FormatException('Schema15 original upload bytes missing');
      }
    }
    await bad(
      "SELECT count(*) FROM legacy_import_records r WHERE r.kind='upload' AND NOT EXISTS "
      "(SELECT 1 FROM legacy_import_upload_bindings b WHERE b.source_sha256=r.source_sha256 AND b.upload_id=r.local_id AND b.role='original')",
    );
    await bad(
      'SELECT count(*) FROM legacy_import_upload_blobs b WHERE NOT EXISTS '
      '(SELECT 1 FROM legacy_import_upload_bindings u WHERE u.source_sha256=b.source_sha256 AND u.attachment_id=b.attachment_id)',
    );
    await bad(
      'SELECT count(*) FROM topic_comments c LEFT JOIN topic_comments p ON p.comment_id=c.parent_comment_id '
      'WHERE c.parent_comment_id>0 AND (p.comment_id IS NULL OR p.topic_id!=c.topic_id OR p.comment_id=c.comment_id)',
    );
    final parents = <int, int>{};
    final comments = await db.rawQuery(
      'SELECT comment_id,parent_comment_id FROM topic_comments LIMIT 1000001',
    );
    if (comments.length > 1000000) {
      throw const FormatException('Schema15 comment graph bound');
    }
    for (final row in comments) {
      parents[row['comment_id'] as int] = row['parent_comment_id'] as int;
    }
    final done = <int>{};
    for (final start in parents.keys) {
      guard();
      final chain = <int>{};
      var cursor = start;
      while (cursor != 0 && !done.contains(cursor)) {
        if (!chain.add(cursor)) {
          throw const FormatException('Schema15 cyclic comment parents');
        }
        final parent = parents[cursor];
        if (parent == null) {
          throw const FormatException('Schema15 missing comment parent');
        }
        cursor = parent;
      }
      done.addAll(chain);
    }
    guard();
    _clock.stop();
  }
}
