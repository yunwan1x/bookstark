import 'package:sqflite/sqflite.dart';
import 'local_store.dart';

/// Unreleased candidate-only schema. Active LocalStore and backup remain v14.
/// Never open a source database or the active store through these functions.
const legacyCandidateSchemaVersion = 15;

Future<void> createLegacyCandidateSchema15(DatabaseExecutor db) async {
  await createLocalSchema14(db);
  await _addLegacyCandidateTables(db);
}

/// Apply only inside the transaction of an OWNED candidate cloned from trusted
/// schema14. Mark v15 only after all DDL succeeds; no active migration is registered.
Future<void> extendSchema14ForLegacyCandidate15(DatabaseExecutor db) async {
  final version = await db.rawQuery('PRAGMA user_version');
  if (version.length != 1 || version.single.values.single != 14) {
    throw const FormatException('Candidate clone must be schema14');
  }
  await _addLegacyCandidateTables(db);
  await db.execute('PRAGMA user_version = 15');
}

Future<void> _addLegacyCandidateTables(DatabaseExecutor db) async {
  for (final definition in [
    "password_hash TEXT NOT NULL DEFAULT ''",
    'is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0,1))',
    'pin_order INTEGER NOT NULL DEFAULT 0',
    'visibility INTEGER NOT NULL DEFAULT 0',
    'legacy_version INTEGER NOT NULL DEFAULT 0',
    "create_time TEXT NOT NULL DEFAULT ''",
    'revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0)',
  ]) {
    await db.execute('ALTER TABLE notes ADD COLUMN $definition');
  }
  await db.execute(
    'ALTER TABLE documents ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0)',
  );
  await db.execute(
    'ALTER TABLE topic_comments ADD COLUMN '
    'parent_comment_id INTEGER NOT NULL DEFAULT 0 CHECK(parent_comment_id >= 0)',
  );
  await db.execute(
    "CREATE TABLE legacy_import_sources ("
    "source_sha256 TEXT PRIMARY KEY NOT NULL "
    "CHECK(length(source_sha256)=64 AND source_sha256 NOT GLOB '*[^0-9a-f]*'), "
    "source_kind TEXT NOT NULL CHECK(source_kind='go_zip_v1'), "
    "manifest_json TEXT NOT NULL, format_recipe_json TEXT NOT NULL, "
    "imported_at TEXT NOT NULL)",
  );
  await db.execute(
    "CREATE TABLE legacy_import_records ("
    "kind TEXT NOT NULL CHECK(kind IN "
    "('book','document','note','bookmark','task','topic','summary',"
    "'topicResource','comment','label','friendLink','upload')), "
    "local_id INTEGER NOT NULL CHECK(local_id > 0), "
    "source_sha256 TEXT NOT NULL REFERENCES legacy_import_sources(source_sha256), "
    "source_key TEXT NOT NULL, payload TEXT NOT NULL, "
    "payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256)=64 "
    "AND payload_sha256 NOT GLOB '*[^0-9a-f]*'), "
    "PRIMARY KEY(kind,local_id), UNIQUE(source_sha256,kind,source_key), "
    "UNIQUE(source_sha256,kind,local_id))",
  );
  await db.execute(
    "CREATE TABLE legacy_import_label_relations ("
    "relation_id INTEGER PRIMARY KEY CHECK(relation_id > 0), "
    "source_sha256 TEXT NOT NULL REFERENCES legacy_import_sources(source_sha256), "
    "label_id INTEGER NOT NULL CHECK(label_id > 0), "
    "resource_kind TEXT NOT NULL CHECK(resource_kind IN "
    "('book','document','note','bookmark')), "
    "resource_id INTEGER NOT NULL CHECK(resource_id > 0), "
    "payload TEXT NOT NULL, payload_sha256 TEXT NOT NULL "
    "CHECK(length(payload_sha256)=64 AND payload_sha256 NOT GLOB '*[^0-9a-f]*'))",
  );
  await db.execute(
    "CREATE TABLE legacy_friend_links ("
    "link_id INTEGER PRIMARY KEY CHECK(link_id > 0), "
    "source_sha256 TEXT NOT NULL REFERENCES legacy_import_sources(source_sha256), "
    "link_name TEXT NOT NULL, link_url TEXT NOT NULL, group_name TEXT NOT NULL, "
    "group_order INTEGER NOT NULL, qr_code TEXT NOT NULL, description TEXT NOT NULL, "
    "sort_weight INTEGER NOT NULL, is_enabled INTEGER NOT NULL "
    "CHECK(is_enabled IN (0,1)), create_time TEXT NOT NULL, modify_time TEXT NOT NULL)",
  );
  await db.execute(
    "CREATE TABLE legacy_import_upload_blobs ("
    "attachment_id TEXT PRIMARY KEY NOT NULL CHECK(length(attachment_id)=32 "
    "AND attachment_id NOT GLOB '*[^0-9a-f]*'), "
    "source_sha256 TEXT NOT NULL REFERENCES legacy_import_sources(source_sha256), "
    "logical_name TEXT NOT NULL, alias_path TEXT NOT NULL, "
    "file_size INTEGER NOT NULL CHECK(file_size>=0), "
    "file_sha256 TEXT NOT NULL CHECK(length(file_sha256)=64 "
    "AND file_sha256 NOT GLOB '*[^0-9a-f]*'), "
    "UNIQUE(source_sha256,logical_name), UNIQUE(source_sha256,alias_path), "
    "UNIQUE(source_sha256,attachment_id))",
  );
  await db.execute(
    "CREATE TABLE legacy_import_upload_bindings ("
    "source_sha256 TEXT NOT NULL, upload_kind TEXT NOT NULL DEFAULT 'upload' "
    "CHECK(upload_kind='upload'), upload_id INTEGER NOT NULL CHECK(upload_id>0), "
    "role TEXT NOT NULL CHECK(role IN ('original','thumbnail')), "
    "attachment_id TEXT NOT NULL, PRIMARY KEY(source_sha256,upload_id,role), "
    "FOREIGN KEY(source_sha256,upload_kind,upload_id) REFERENCES "
    "legacy_import_records(source_sha256,kind,local_id), "
    "FOREIGN KEY(source_sha256,attachment_id) REFERENCES "
    "legacy_import_upload_blobs(source_sha256,attachment_id))",
  );
}
