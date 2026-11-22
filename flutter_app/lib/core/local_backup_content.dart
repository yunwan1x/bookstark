import 'local_backup_schema15_content.dart';
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'drive_models.dart';
import 'local_backup_codec.dart';
import 'local_backup_schema.dart';
import 'local_html_preview_document.dart';
import 'trash_repository.dart';

class LocalBackupContentReport {
  const LocalBackupContentReport({
    required this.disabledHtmlBindings,
    required this.unavailableReferences,
    required this.pendingImageCleanup,
  });
  final int disabledHtmlBindings, unavailableReferences, pendingImageCleanup;
  bool get needsAdditionalReview =>
      disabledHtmlBindings + unavailableReferences + pendingImageCleanup > 0;
}

/// Schema verification must precede this check on the same private inactive DB.
/// Raw editor source and trash payloads are retained without rewriting.
class LocalBackupContentVerifier {
  LocalBackupContentVerifier(this.factory);
  final DatabaseFactory factory;
  static const maxHierarchyNodes = 250000, maxStructuredBytes = 1024 * 1024;
  static const _ids = {
    'notes': 'id',
    'tasks': 'task_id',
    'trash_entries': 'trash_id',
    'books': 'book_id',
    'documents': 'document_id',
    'bookmarks': 'bookmark_id',
    'topics': 'topic_id',
    'topic_summaries': 'summary_id',
    'topic_resources': 'topic_resource_id',
    'topic_comments': 'comment_id',
    'local_labels': 'label_id',
    'local_images': 'image_id',
    'local_drive_nodes': 'node_id',
  };
  static const _flags = {
    'notes': ['deleted'],
    'tasks': ['done', 'deleted'],
    'books': ['deleted'],
    'documents': ['deleted'],
    'bookmarks': ['is_public', 'is_pinned', 'nav_visible', 'deleted'],
    'topics': ['is_pinned', 'deleted'],
    'local_images': ['file_present', 'deleted'],
    'local_drive_nodes': ['directory'],
  };

  Future<LocalBackupContentReport> verify(
    File database,
    LocalBackupManifest manifest,
    LocalBackupDatabaseFacts schema,
  ) async {
    if (schema.databaseSchema != manifest.databaseSchema) {
      throw const FormatException('Backup schema facts do not match manifest');
    }
    if ((schema.tables['tasks'] ?? 0) > maxHierarchyNodes ||
        (schema.tables['documents'] ?? 0) > maxHierarchyNodes) {
      throw const FormatException('Backup hierarchy exceeds its checked limit');
    }
    final db = await factory.openDatabase(
      database.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await db.execute('PRAGMA trusted_schema = OFF');
      final actualVersion = await db.rawQuery('PRAGMA user_version');
      if (actualVersion.length != 1 ||
          actualVersion.single.values.single != manifest.databaseSchema) {
        throw const FormatException(
          'Backup database changed after verification',
        );
      }
      await _types(
        db,
        LocalBackupManifest.requiredTablesFor(manifest.databaseSchema),
        allowSchema15OpaqueNote: manifest.databaseSchema == 15,
      );
      if (manifest.databaseSchema == 16) {
        await _reject(
          db,
          "SELECT COUNT(*) AS n FROM assistant_creation_receipts WHERE length(creation_key)!=32 OR creation_key GLOB '*[^0-9a-f]*' OR resource_type NOT IN ('note','task') OR resource_id<=0 OR length(input_hash)!=64 OR input_hash GLOB '*[^0-9a-f]*' OR created_at<=0",
        );
      }
      for (final entry in _ids.entries) {
        await _reject(
          db,
          'SELECT COUNT(*) AS n FROM "${entry.key}" WHERE "${entry.value}" <= 0',
        );
      }
      for (final entry in _flags.entries) {
        for (final field in entry.value) {
          await _reject(
            db,
            'SELECT COUNT(*) AS n FROM "${entry.key}" WHERE "$field" NOT IN (0,1)',
          );
        }
      }
      await _reject(
        db,
        "SELECT COUNT(*) AS n FROM notes WHERE collection NOT IN ('note','article') OR editor_type NOT IN ('markdown','html','spreadsheet','drawing','mindmap','richdoc','presentation')",
      );
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM tasks WHERE parent_id<0 OR topic_id<0',
      );
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM documents WHERE parent_id<0 OR book_id<=0',
      );
      await _reject(db, 'SELECT COUNT(*) AS n FROM books WHERE doc_count<0');
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM local_images WHERE file_size<0 OR width<0 OR height<0',
      );
      await _reject(
        db,
        "SELECT COUNT(*) AS n FROM topic_resources WHERE target_id<=0 OR resource_type NOT IN ('document','note','article','bookmark','task')",
      );
      await _reject(
        db,
        "SELECT COUNT(*) AS n FROM topic_comments WHERE target_id<=0 OR target_type NOT IN ('resource','summary','task')",
      );
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM trash_entries WHERE resource_id<=0',
      );
      for (final table in ['notes', 'books', 'documents', 'bookmarks']) {
        await _reject(
          db,
          'SELECT COUNT(*) AS n FROM "$table" WHERE length(CAST(labels AS BLOB))>$maxStructuredBytes',
        );
        await for (final row in _rows(db, table, ['labels'])) {
          final labels = jsonDecode(row['labels'] as String);
          if (labels is! List || labels.any((label) => label is! String)) {
            throw const FormatException('Invalid backup label metadata');
          }
        }
      }
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM label_recommendation_settings WHERE length(CAST(settings AS BLOB))>$maxStructuredBytes',
      );
      await for (final row in _rows(db, 'label_recommendation_settings', [
        'settings',
      ])) {
        if (jsonDecode(row['settings'] as String) is! Map<String, dynamic>) {
          throw const FormatException('Invalid backup recommendation metadata');
        }
      }
      await for (final row in _rows(db, 'trash_entries', ['resource_type'])) {
        if (!trashTypes.contains(row['resource_type'])) {
          throw const FormatException('Unknown backup trash resource type');
        }
      }
      await for (final row in _rows(db, 'html_creation_receipts', [
        'creation_key',
        'input_hash',
        'note_id',
        'created_at',
      ])) {
        if (!_hex(row['creation_key'], 32) ||
            !_hex(row['input_hash'], 64) ||
            (row['note_id'] as int) <= 0 ||
            (row['created_at'] as int) <= 0) {
          throw const FormatException('Invalid retained creation receipt');
        }
      }
      await _reject(
        db,
        "SELECT COUNT(*) AS n FROM html_creation_receipts WHERE collection NOT IN ('note','article')",
      );
      if (manifest.databaseSchema == 15) {
        await verifySchema15BackupContent(db, manifest);
      }
      await _sequence(db, manifest.databaseSchema);
      await _reject(
        db,
        'SELECT COUNT(*) AS n FROM documents d LEFT JOIN books b ON b.book_id=d.book_id WHERE d.deleted=0 AND (b.book_id IS NULL OR b.deleted!=0)',
      );
      var unavailable = await _count(
        db,
        'SELECT COUNT(*) AS n FROM documents d LEFT JOIN books b ON b.book_id=d.book_id WHERE d.deleted=1 AND b.book_id IS NULL',
      );
      unavailable += await _hierarchy(db, 'tasks', 'task_id');
      unavailable += await _hierarchy(
        db,
        'documents',
        'document_id',
        documents: true,
      );
      final files = {for (final file in manifest.files) file.path: file};
      await _drive(db, files);
      final images = await _images(db, files);
      unavailable += images.$1;
      final disabled = await _bindings(db);
      for (final table in [
        'topic_summaries',
        'topic_resources',
        'topic_comments',
      ]) {
        await _reject(
          db,
          'SELECT COUNT(*) AS n FROM "$table" r LEFT JOIN topics t ON t.topic_id=r.topic_id WHERE t.topic_id IS NULL',
        );
      }
      unavailable += await _count(
        db,
        'SELECT COUNT(*) AS n FROM tasks r LEFT JOIN topics t ON t.topic_id=r.topic_id WHERE r.topic_id>0 AND t.topic_id IS NULL',
      );
      unavailable += await _count(
        db,
        "SELECT COUNT(*) AS n FROM topic_resources r LEFT JOIN notes n ON r.resource_type IN ('note','article') AND n.id=r.target_id AND n.collection=r.resource_type AND n.deleted=0 LEFT JOIN documents d ON r.resource_type='document' AND d.document_id=r.target_id AND d.deleted=0 LEFT JOIN bookmarks b ON r.resource_type='bookmark' AND b.bookmark_id=r.target_id AND b.deleted=0 LEFT JOIN tasks t ON r.resource_type='task' AND t.task_id=r.target_id AND t.deleted=0 WHERE n.id IS NULL AND d.document_id IS NULL AND b.bookmark_id IS NULL AND t.task_id IS NULL",
      );
      return LocalBackupContentReport(
        disabledHtmlBindings: disabled,
        unavailableReferences: unavailable,
        pendingImageCleanup: images.$2,
      );
    } finally {
      await db.close();
    }
  }

  bool _hex(Object? value, int length) =>
      value is String &&
      RegExp(
        '^[a-f0-9]{$length}'
        r'$',
      ).hasMatch(value);

  Future<void> _types(
    Database db,
    Set<String> requiredTables, {
    bool allowSchema15OpaqueNote = false,
  }) async {
    for (final table in requiredTables.where((t) => t != 'sqlite_sequence')) {
      await _reject(db, 'SELECT COUNT(*) AS n FROM "$table" WHERE rowid<=0');
      for (final column in await db.rawQuery('PRAGMA table_info("$table")')) {
        final name = column['name'] as String, type = column['type'] as String;
        if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name) ||
            !{'TEXT', 'INTEGER'}.contains(type.toUpperCase())) {
          throw const FormatException('Unexpected checked backup column');
        }
        final kind = type.toUpperCase() == 'TEXT' ? 'text' : 'integer';
        final nonnull = column['notnull'] == 1 || (column['pk'] as int) > 0;
        final test = nonnull
            ? 'typeof("$name") != \'$kind\''
            : '"$name" IS NOT NULL AND typeof("$name") != \'$kind\'';
        final checkedTest =
            allowSchema15OpaqueNote && table == 'notes' && name == 'content'
            ? "($test) AND NOT (typeof(content)='blob' AND collection='note' AND editor_type='markdown' AND password_hash='' AND NOT EXISTS (SELECT 1 FROM html_creation_receipts r WHERE r.note_id=notes.id))"
            : test;
        await _reject(
          db,
          'SELECT COUNT(*) AS n FROM "$table" WHERE $checkedTest',
        );
      }
    }
  }

  Future<int> _count(Database db, String sql) async {
    final n = (await db.rawQuery(sql)).single['n'];
    if (n is! int || n < 0) {
      throw const FormatException('Invalid checked backup count');
    }
    return n;
  }

  Future<void> _reject(Database db, String sql) async {
    if (await _count(db, sql) != 0) {
      throw const FormatException(
        'Backup local metadata or relationship is invalid',
      );
    }
  }

  Stream<Map<String, Object?>> _rows(
    Database db,
    String table,
    List<String> columns,
  ) async* {
    var last = 0;
    while (true) {
      final rows = await db.query(
        table,
        columns: ['rowid AS _backup_rowid', ...columns],
        where: 'rowid>?',
        whereArgs: [last],
        orderBy: 'rowid',
        limit: 64,
      );
      if (rows.isEmpty) return;
      for (final row in rows) {
        final id = row['_backup_rowid'];
        if (id is! int || id <= last) {
          throw const FormatException('Invalid backup row cursor');
        }
        last = id;
        yield row;
      }
    }
  }

  Future<void> _sequence(Database db, int schemaVersion) async {
    final values = <String, int>{};
    for (final row in await db.query('sqlite_sequence')) {
      final name = row['name'], seq = row['seq'];
      if (name is! String ||
          !_ids.containsKey(name) ||
          seq is! int ||
          seq < 0 ||
          values.containsKey(name)) {
        throw const FormatException('Invalid backup identity sequence');
      }
      values[name] = seq;
    }
    for (final entry in _ids.entries) {
      var maximum =
          (await db.rawQuery(
                'SELECT MAX("${entry.value}") AS maximum FROM "${entry.key}"',
              )).single['maximum']
              as int? ??
          0;
      if (entry.key == 'notes') {
        final old =
            (await db.rawQuery(
                  'SELECT MAX(note_id) AS maximum FROM html_creation_receipts',
                )).single['maximum']
                as int? ??
            0;
        if (old > maximum) maximum = old;
      }
      if (schemaVersion == 16 && {'notes', 'tasks'}.contains(entry.key)) {
        final kind = entry.key == 'notes' ? 'note' : 'task';
        final historical =
            (await db.rawQuery(
                  'SELECT MAX(resource_id) AS maximum FROM assistant_creation_receipts WHERE resource_type=?',
                  [kind],
                )).single['maximum']
                as int? ??
            0;
        if (historical > maximum) maximum = historical;
      }
      if (entry.key == 'local_drive_nodes') {
        final old =
            (await db.rawQuery(
                  'SELECT MAX(node_id) AS maximum FROM html_preview_resources',
                )).single['maximum']
                as int? ??
            0;
        if (old > maximum) maximum = old;
      }
      if (maximum > 0 && (values[entry.key] ?? -1) < maximum) {
        throw const FormatException(
          'Backup sequence could reuse a retained ID',
        );
      }
    }
  }

  Future<int> _hierarchy(
    Database db,
    String table,
    String id, {
    bool documents = false,
  }) async {
    final nodes = <int, ({int parent, int book, bool deleted})>{};
    await for (final row in _rows(db, table, [
      id,
      'parent_id',
      'deleted',
      if (documents) 'book_id',
    ])) {
      nodes[row[id] as int] = (
        parent: row['parent_id'] as int,
        book: documents ? row['book_id'] as int : 0,
        deleted: row['deleted'] == 1,
      );
      if (nodes.length > maxHierarchyNodes) {
        throw const FormatException(
          'Backup hierarchy exceeds its checked limit',
        );
      }
    }
    final unavailable = <int>{};
    for (final entry in nodes.entries) {
      final node = entry.value;
      if (node.parent == 0) continue;
      final parent = nodes[node.parent];
      if (parent == null || parent.book != node.book) {
        if (!node.deleted) {
          throw const FormatException('Active backup parent unavailable');
        }
        unavailable.add(entry.key);
      } else if (!node.deleted && parent.deleted) {
        throw const FormatException('Active backup parent has been deleted');
      }
    }
    final done = <int>{};
    for (final start in nodes.keys) {
      final chain = <int>{};
      var cursor = start;
      while (cursor != 0 &&
          !done.contains(cursor) &&
          !unavailable.contains(cursor)) {
        if (!chain.add(cursor)) {
          throw const FormatException('Cyclic backup hierarchy');
        }
        cursor = nodes[cursor]!.parent;
      }
      done.addAll(chain);
    }
    return unavailable.length;
  }

  Future<void> _drive(Database db, Map<String, LocalBackupFile> files) async {
    await _reject(
      db,
      "SELECT COUNT(*) AS n FROM local_drive_nodes c LEFT JOIN local_drive_nodes p ON p.path=c.parent_path WHERE c.parent_path!='' AND (p.node_id IS NULL OR p.directory!=1)",
    );
    await for (final row in _rows(db, 'local_drive_nodes', [
      'path',
      'parent_path',
      'name',
      'directory',
      'file_size',
      'file_hash',
      'blob_key',
    ])) {
      final path = row['path'] as String;
      if (path.isEmpty ||
          drivePath(path) != path ||
          driveBasename(path) != row['name'] ||
          driveParent(path) != row['parent_path']) {
        throw const FormatException('Invalid backup drive path hierarchy');
      }
      if (row['directory'] == 1) {
        if (row['file_size'] != 0 ||
            row['file_hash'] != '' ||
            row['blob_key'] != '') {
          throw const FormatException('Invalid backup directory metadata');
        }
        continue;
      }
      final key = row['blob_key'] as String;
      if (!RegExp(r'^[a-f0-9]{32}\.blob$').hasMatch(key) ||
          !_hex(row['file_hash'], 64)) {
        throw const FormatException('Invalid backup drive blob identity');
      }
      final file = files['drive-blobs/$key'];
      if (file == null ||
          file.bytes != row['file_size'] ||
          file.sha256 != row['file_hash']) {
        throw const FormatException(
          'Backup drive blob missing or differs from SQL',
        );
      }
    }
  }

  Future<(int, int)> _images(
    Database db,
    Map<String, LocalBackupFile> files,
  ) async {
    var unavailable = 0, cleanup = 0;
    await for (final row in _rows(db, 'local_images', [
      'attachment_id',
      'file_size',
      'file_hash',
      'deleted',
      'file_present',
      'quarantine_name',
    ])) {
      final id = row['attachment_id'] as String,
          quarantine = row['quarantine_name'] as String;
      if (!_hex(id, 32) ||
          row['file_hash'] != '' && !_hex(row['file_hash'], 64)) {
        throw const FormatException('Invalid backup image identity');
      }
      final original = files['attachments/$id'];
      if (row['deleted'] == 0 && row['file_present'] == 1 && original == null) {
        throw const FormatException('Backup image file is missing');
      }
      if (row['deleted'] == 0 && original == null) unavailable++;
      void checkFile(LocalBackupFile? file) {
        if (file != null &&
            (file.bytes != row['file_size'] ||
                row['file_hash'] != '' && file.sha256 != row['file_hash'])) {
          throw const FormatException('Backup image file differs from SQL');
        }
      }

      checkFile(original);
      if (quarantine.isNotEmpty) {
        if (row['deleted'] != 1 ||
            !RegExp(
              r'^\.image-delete-' + id + r'-[a-f0-9]{32}$',
            ).hasMatch(quarantine)) {
          throw const FormatException('Invalid backup image quarantine');
        }
        cleanup++;
        checkFile(files['attachments/$quarantine']);
      }
    }
    return (unavailable, cleanup);
  }

  Future<int> _bindings(Database db) async {
    await _reject(
      db,
      'SELECT COUNT(*) AS n FROM (SELECT note_id FROM html_preview_resources GROUP BY note_id HAVING COUNT(*)>32)',
    );
    var last = 0, disabled = 0;
    while (true) {
      final rows = await db.rawQuery(
        '''SELECT r.rowid AS cursor_id,r.resource_path,r.approved_hash,
        n.id AS owner,n.editor_type,d.node_id AS node,d.directory,d.file_hash,d.mime_type
        FROM html_preview_resources r LEFT JOIN notes n ON n.id=r.note_id
        LEFT JOIN local_drive_nodes d ON d.node_id=r.node_id
        WHERE r.rowid>? ORDER BY r.rowid LIMIT 64''',
        [last],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        last = row['cursor_id'] as int;
        if (row['owner'] == null ||
            row['editor_type'] != 'html' ||
            !validLocalHtmlResourcePath(row['resource_path'] as String) ||
            row['resource_path'] == 'index.html' ||
            !_hex(row['approved_hash'], 64)) {
          throw const FormatException(
            'Invalid backup HTML resource owner or path',
          );
        }
        if (row['node'] == null ||
            row['directory'] == 1 ||
            row['file_hash'] != row['approved_hash'] ||
            !localHtmlResourceMimes.contains(row['mime_type'])) {
          disabled++;
        }
      }
    }
    return disabled;
  }
}
