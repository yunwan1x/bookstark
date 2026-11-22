part of 'local_store.dart';

/// Frozen schema14 contract. Keep stable when the active store advances.
/// Called only by a fresh database factory's onCreate callback.
Future<void> createLocalSchema14(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'title TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, '
    "deleted INTEGER NOT NULL DEFAULT 0, labels TEXT NOT NULL DEFAULT '[]', collection TEXT NOT NULL DEFAULT 'note', editor_type TEXT NOT NULL DEFAULT 'markdown')",
  );
  await db.execute(
    "CREATE UNIQUE INDEX notes_article_title ON notes(title) WHERE collection = 'article' AND deleted = 0",
  );
  await _createTaskTables(db);
  await _createBookTables(db);
  await _createDocumentTables(db);
  await _createBookmarkTables(db);
  await _createTopicTables(db);
  await _createLabelTables(db);
  await _createImageTables(db);
  await _createDriveTables(db);
  await _createHtmlCreationTables(db);
  await _createHtmlResourceTables(db);
}

Future<void> _createHtmlResourceTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE html_preview_resources (note_id INTEGER NOT NULL CHECK(note_id > 0), resource_path TEXT NOT NULL, node_id INTEGER NOT NULL CHECK(node_id > 0), approved_hash TEXT NOT NULL CHECK(length(approved_hash) = 64), PRIMARY KEY(note_id, resource_path))',
  );
  await db.execute(
    'CREATE TRIGGER html_preview_resources_note_delete AFTER DELETE ON notes BEGIN DELETE FROM html_preview_resources WHERE note_id=OLD.id; END',
  );
}

Future<void> _createHtmlCreationTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE html_creation_receipts (creation_key TEXT PRIMARY KEY NOT NULL CHECK(length(creation_key) = 32), note_id INTEGER NOT NULL CHECK(note_id > 0), collection TEXT NOT NULL CHECK(collection IN ('note','article')), input_hash TEXT NOT NULL CHECK(length(input_hash) = 64), created_at INTEGER NOT NULL CHECK(created_at > 0))",
  );
}

Future<void> _createDriveTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE local_drive_nodes (node_id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, parent_path TEXT NOT NULL, name TEXT NOT NULL, directory INTEGER NOT NULL CHECK(directory IN (0,1)), file_size INTEGER NOT NULL DEFAULT 0 CHECK(file_size >= 0), file_hash TEXT NOT NULL DEFAULT '', mime_type TEXT NOT NULL, blob_key TEXT NOT NULL DEFAULT '', create_time TEXT NOT NULL, modify_time TEXT NOT NULL)",
  );
  await db.execute(
    'CREATE INDEX local_drive_parent ON local_drive_nodes(parent_path, name)',
  );
  await db.execute(
    'CREATE INDEX local_drive_blob ON local_drive_nodes(blob_key)',
  );
}

Future<void> _createImageTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE local_images (image_id INTEGER PRIMARY KEY AUTOINCREMENT, attachment_id TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'editor', mime_type TEXT NOT NULL, file_hash TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL, width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL DEFAULT '', modify_time TEXT NOT NULL, file_present INTEGER NOT NULL DEFAULT 1, deleted INTEGER NOT NULL DEFAULT 0, quarantine_name TEXT NOT NULL DEFAULT '')",
  );
  await db.execute(
    'CREATE INDEX local_images_hash ON local_images(file_hash, deleted)',
  );
}

Future<void> _createLabelTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE local_labels (label_id INTEGER PRIMARY KEY AUTOINCREMENT, label_name TEXT NOT NULL UNIQUE)',
  );
  await db.execute(
    'CREATE TABLE label_recommendation_settings (id INTEGER PRIMARY KEY CHECK(id = 1), settings TEXT NOT NULL)',
  );
  await db.execute(
    "ALTER TABLE documents ADD COLUMN labels TEXT NOT NULL DEFAULT '[]'",
  );
}

Future<void> _createTopicTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE topics (topic_id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, question TEXT NOT NULL DEFAULT '', is_pinned INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL, modify_time TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)",
  );
  await db.execute(
    "CREATE TABLE topic_summaries (summary_id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL, content TEXT NOT NULL, summary_type TEXT NOT NULL DEFAULT 'manual', order_sort INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL, modify_time TEXT NOT NULL)",
  );
  await db.execute(
    'CREATE INDEX topic_summaries_topic ON topic_summaries(topic_id, order_sort)',
  );
  await db.execute(
    "CREATE TABLE topic_resources (topic_resource_id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL, resource_type TEXT NOT NULL, target_id INTEGER NOT NULL, title_snapshot TEXT NOT NULL, desc_snapshot TEXT NOT NULL DEFAULT '', order_sort INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL, UNIQUE(topic_id, resource_type, target_id))",
  );
  await db.execute(
    'CREATE TABLE topic_comments (comment_id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL, target_type TEXT NOT NULL, target_id INTEGER NOT NULL, content TEXT NOT NULL, create_time TEXT NOT NULL, modify_time TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE INDEX topic_comments_target ON topic_comments(topic_id, target_type, target_id)',
  );
}

Future<void> _createBookmarkTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE bookmarks (bookmark_id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, url TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', favicon TEXT NOT NULL DEFAULT '', labels TEXT NOT NULL DEFAULT '[]', is_public INTEGER NOT NULL DEFAULT 0, is_pinned INTEGER NOT NULL DEFAULT 0, nav_visible INTEGER NOT NULL DEFAULT 0, order_sort INTEGER NOT NULL DEFAULT 0, create_time INTEGER NOT NULL, modify_time INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)",
  );
  await db.execute(
    'CREATE UNIQUE INDEX bookmarks_active_url ON bookmarks(url) WHERE deleted = 0',
  );
  await db.execute(
    'CREATE INDEX bookmarks_listing ON bookmarks(deleted, is_pinned, modify_time)',
  );
}

Future<void> _createDocumentTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE documents (document_id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL, document_name TEXT NOT NULL, identify TEXT NOT NULL UNIQUE, parent_id INTEGER NOT NULL DEFAULT 0, order_sort INTEGER NOT NULL DEFAULT 0, doc_type TEXT NOT NULL DEFAULT 'markdown', markdown TEXT NOT NULL DEFAULT '', create_time TEXT NOT NULL, modify_time TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)",
  );
  await db.execute(
    'CREATE INDEX documents_book_parent ON documents(book_id, deleted, parent_id, order_sort)',
  );
}

Future<void> _createBookTables(DatabaseExecutor db) async {
  await db.execute(
    "CREATE TABLE books (book_id INTEGER PRIMARY KEY AUTOINCREMENT, book_name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', identify TEXT NOT NULL UNIQUE, labels TEXT NOT NULL DEFAULT '[]', doc_count INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL, modify_time TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)",
  );
  await db.execute(
    'CREATE UNIQUE INDEX books_active_name ON books(book_name) WHERE deleted = 0',
  );
}

Future<void> _createTaskTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE tasks (task_id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, due_date TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0, 1)), parent_id INTEGER NOT NULL DEFAULT 0 CHECK(parent_id >= 0), topic_id INTEGER NOT NULL DEFAULT 0, create_time TEXT NOT NULL, modify_time TEXT NOT NULL, complete_time TEXT, deleted INTEGER NOT NULL DEFAULT 0)',
  );
  await db.execute('CREATE INDEX tasks_parent ON tasks(parent_id, deleted)');
  await db.execute('CREATE INDEX tasks_due ON tasks(deleted, done, due_date)');
  await db.execute(
    'CREATE TABLE trash_entries (trash_id INTEGER PRIMARY KEY AUTOINCREMENT, resource_type TEXT NOT NULL, resource_id INTEGER NOT NULL, name TEXT NOT NULL, payload TEXT NOT NULL, deleted_at TEXT NOT NULL)',
  );
}
