import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as paths;
import 'local_data_maintenance.dart';
import 'bounded_note_text_reader.dart';
import 'local_data_paths.dart';
import 'local_store_schema16.dart';
import 'local_assistant_creation_receipts.dart';

part 'local_store_schema14.dart';

class LocalStore {
  LocalStore({
    required this.path,
    this.dataPaths,
    DatabaseFactory? factory,
    LocalDataMaintenance? maintenance,
  }) : factory = factory ?? databaseFactory,
       maintenance =
           maintenance ??
           (path == inMemoryDatabasePath
               ? LocalDataMaintenance()
               : LocalDataMaintenance.forStorage(
                   paths.normalize(paths.absolute(path)),
                 )) {
    if (dataPaths != null &&
        paths.normalize(paths.absolute(path)) != dataPaths!.databasePath) {
      throw ArgumentError('Local database and resource layout do not match');
    }
  }
  final String path;
  final LocalDataPaths? dataPaths;
  final DatabaseFactory factory;
  final LocalDataMaintenance maintenance;
  Future<Database>? _database;
  Future<Database> get database => maintenance.use(
    () async => _database ??= factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: assistantActiveSchemaVersion,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 1 ||
              oldVersion > 14 ||
              newVersion != assistantActiveSchemaVersion) {
            throw const FormatException(
              'Unsupported active local database upgrade',
            );
          }
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE notes ADD COLUMN labels TEXT NOT NULL DEFAULT '[]'",
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE notes ADD COLUMN collection TEXT NOT NULL DEFAULT 'note'",
            );
            await db.execute(
              "CREATE UNIQUE INDEX notes_article_title ON notes(title) WHERE collection = 'article' AND deleted = 0",
            );
          }
          if (oldVersion < 4) await _createTaskTables(db);
          if (oldVersion < 5) await _createBookTables(db);
          if (oldVersion < 6) await _createDocumentTables(db);
          if (oldVersion < 7) await _createBookmarkTables(db);
          if (oldVersion < 8) await _createTopicTables(db);
          if (oldVersion < 9) await _createLabelTables(db);
          if (oldVersion < 10) await _createImageTables(db);
          if (oldVersion < 11) await _createDriveTables(db);
          if (oldVersion < 13) await _createHtmlCreationTables(db);
          if (oldVersion < 14) await _createHtmlResourceTables(db);
          if (oldVersion < 12) {
            await db.execute(
              "ALTER TABLE notes ADD COLUMN editor_type TEXT NOT NULL DEFAULT 'markdown'",
            );
          }
          // Historical migrations above first establish the frozen14 shape.
          // sqflite owns this transaction and sets user_version only on commit.
          await db.execute(assistantCreationReceiptSchema);
        },
        onDowngrade: (db, oldVersion, newVersion) {
          throw const FormatException('Unsupported newer local database');
        },
        onCreate: (db, version) => createLocalSchema16(db),
      ),
    ),
  );
  Future<int> createNote(
    String title,
    String content, {
    List<String> labels = const [],
    String collection = 'note',
  }) => maintenance.use(
    () async => (await database).rawInsert(
      'INSERT INTO notes (collection,title,content,labels,updated_at) '
      'VALUES (?,CAST(? AS TEXT),CAST(? AS TEXT),?,?)',
      [
        _collection(collection),
        Uint8List.fromList(utf8.encode(title)),
        Uint8List.fromList(utf8.encode(content)),
        jsonEncode(labels),
        DateTime.now().millisecondsSinceEpoch,
      ],
    ),
  );
  Future<void> updateNote(
    int id,
    String title,
    String content, {
    List<String> labels = const [],
    String collection = 'note',
  }) => maintenance.use(() async {
    final rows = await (await database).rawUpdate(
      'UPDATE notes SET title=CAST(? AS TEXT),content=CAST(? AS TEXT),'
      'labels=?,updated_at=? '
      "WHERE id = ? AND deleted = 0 AND collection = ? AND editor_type = 'markdown'",
      [
        Uint8List.fromList(utf8.encode(title)),
        Uint8List.fromList(utf8.encode(content)),
        jsonEncode(labels),
        DateTime.now().millisecondsSinceEpoch,
        id,
        _collection(collection),
      ],
    );
    if (rows != 1) throw StateError('Note no longer exists');
  });

  Future<List<Map<String, Object?>>> notes({
    int limit = 20,
    int offset = 0,
    String keyword = '',
    String collection = 'note',
    String label = '',
  }) => maintenance.use(
    () async => (await database).query(
      'notes',
      where:
          'deleted = 0 AND collection = ? AND (? = \'\' OR instr(labels, ?) > 0) AND (title LIKE ? ESCAPE \'\\\' OR content LIKE ? ESCAPE \'\\\')',
      whereArgs: [
        _collection(collection),
        label,
        jsonEncode(label),
        for (var i = 0; i < 2; i++)
          '%${keyword.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%',
      ],
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
      offset: offset,
    ),
  );

  /// Returns bounded list rows without materializing full note bodies.
  /// SQLite substr counts Unicode code points, so the preview is at most
  /// [previewRunes] runes even for supplementary characters.
  Future<List<Map<String, Object?>>> notesForList({
    int limit = 20,
    int offset = 0,
    String keyword = '',
    String collection = 'note',
    String label = '',
    int previewRunes = 512,
  }) => maintenance.use(() async {
    if (previewRunes < 0 || previewRunes > 512) {
      throw ArgumentError.value(previewRunes);
    }
    final escapedKeyword = keyword
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await (await database).rawQuery(
      'SELECT id, title, CAST(substr(content, 1, ?) AS BLOB) AS content_preview_bytes, updated_at, labels '
      'FROM notes WHERE deleted = 0 AND collection = ? '
      "AND (? = '' OR instr(labels, ?) > 0) "
      "AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\') "
      'ORDER BY updated_at DESC, id DESC LIMIT ? OFFSET ?',
      [
        previewRunes,
        _collection(collection),
        label,
        jsonEncode(label),
        '%$escapedKeyword%',
        '%$escapedKeyword%',
        limit,
        offset,
      ],
    );
    return rows.map((row) {
      final bytes = row['content_preview_bytes'];
      if (bytes is! List<int> || bytes.length > previewRunes * 4) {
        throw const FormatException('Invalid bounded note preview bytes');
      }
      return Map<String, Object?>.from(row)
        ..remove('content_preview_bytes')
        ..['content_preview'] = BoundedNoteTextReader.decodeUtf8PreservingBom(
          Uint8List.fromList(bytes),
        );
    }).toList();
  });

  Future<Map<String, Object?>> readNote(int id, {String collection = 'note'}) =>
      maintenance.use(() async {
        final db = await database;
        return db.transaction((tx) async {
          final rows = await tx.rawQuery(
            'SELECT id,collection,editor_type,labels,updated_at,deleted,'
            'CAST(title AS BLOB) AS title_bytes FROM notes '
            'WHERE id = ? AND deleted = 0 AND collection = ?',
            [id, _collection(collection)],
          );
          if (rows.length != 1) throw StateError('Note no longer exists');
          final row = Map<String, Object?>.from(rows.single);
          row['title'] = BoundedNoteTextReader.decodeUtf8PreservingBom(
            row.remove('title_bytes') as Uint8List,
          );
          row['content'] = await BoundedNoteTextReader.readNoteContent(
            tx,
            id: id,
            collection: _collection(collection),
            editorType: row['editor_type'] as String,
            // Legacy Markdown reads were unbounded; only chunk the transport.
            maxRecordBytes: row['editor_type'] == 'markdown'
                ? null
                : BoundedNoteTextReader.maxBytes,
          );
          return row;
        });
      });

  Future<void> deleteNote(int id, {String collection = 'note'}) =>
      maintenance.use(() async {
        final count = await (await database).update(
          'notes',
          {'deleted': 1},
          where: 'id = ? AND deleted = 0 AND collection = ?',
          whereArgs: [id, _collection(collection)],
        );
        if (count != 1) throw StateError('Note no longer exists');
      });

  String _collection(String value) {
    if (!['note', 'article'].contains(value)) throw ArgumentError.value(value);
    return value;
  }

  Future<Map<String, Object?>> homeSummary() => maintenance.use(
    () async => (await database).transaction((db) async {
      // Each source contributes at most twenty candidates; the global top
      // twenty cannot contain a source's twenty-first most recent row.
      final notes = await db.query(
        'notes',
        columns: ['id', 'title', 'updated_at'],
        where: 'deleted = 0',
        orderBy: 'updated_at DESC, id DESC',
        limit: 20,
      );
      final books = await db.query(
        'books',
        columns: ['book_id', 'book_name', 'modify_time'],
        where: 'deleted = 0',
        orderBy: 'modify_time DESC, book_id DESC',
        limit: 20,
      );
      final documents = await db.rawQuery(
        'SELECT d.document_id, d.document_name, d.modify_time, b.book_name FROM documents d JOIN books b ON b.book_id = d.book_id WHERE d.deleted = 0 AND b.deleted = 0 ORDER BY d.modify_time DESC, d.document_id DESC LIMIT 20',
      );
      int modified(Object? value) {
        if (value is int) return value;
        final parsed = value is String ? DateTime.tryParse(value) : null;
        if (parsed == null) {
          throw const FormatException('Invalid local modification timestamp');
        }
        return parsed.millisecondsSinceEpoch;
      }

      Map<String, Object?> row(
        int id,
        String type,
        String title,
        String context,
        Object? time,
      ) {
        final stamp = modified(time);
        return {
          'id': id,
          'type': type,
          'title': title,
          'context': context,
          'modified_at': stamp,
          'visited_at': stamp,
        };
      }

      final items = <Map<String, Object?>>[
        for (final item in notes)
          row(
            item['id'] as int,
            'blog',
            item['title'] as String,
            '',
            item['updated_at'],
          ),
        for (final item in books)
          row(
            item['book_id'] as int,
            'book',
            item['book_name'] as String,
            '',
            item['modify_time'],
          ),
        for (final item in documents)
          row(
            item['document_id'] as int,
            'document',
            item['document_name'] as String,
            item['book_name'] as String,
            item['modify_time'],
          ),
      ];
      items.sort((a, b) {
        final time = (b['modified_at'] as int).compareTo(
          a['modified_at'] as int,
        );
        if (time != 0) return time;
        final type = (a['type'] as String).compareTo(b['type'] as String);
        return type != 0 ? type : (b['id'] as int).compareTo(a['id'] as int);
      });
      return {'recent': items.take(20).toList()};
    }),
  );

  Future<String> noteCollectionOf(int id) => maintenance.use(() async {
    final rows = await (await database).query(
      'notes',
      columns: ['collection'],
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw StateError('资源已失效 / Resource unavailable');
    }
    return _collection(rows.single['collection'] as String);
  });

  Future<void> close() => maintenance.use(() async {
    if (_database != null) {
      await (await _database!).close();
      _database = null;
    }
  });
}
