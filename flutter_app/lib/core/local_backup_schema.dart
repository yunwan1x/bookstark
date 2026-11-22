import 'local_legacy_candidate_schema.dart';
import 'local_store_schema16.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'local_backup_codec.dart';
import 'local_store.dart';
import 'attachments.dart';

class LocalBackupDatabaseFacts {
  const LocalBackupDatabaseFacts({
    required this.readerSQLiteVersion,
    required this.tables,
    this.databaseSchema = 14,
  });
  final String readerSQLiteVersion;
  final int databaseSchema;
  final Map<String, int> tables;
}

/// Checks storage structure and SQLite integrity, not application-level resource
/// references. Import still requires the separate content/blob validator.
class LocalBackupSchemaVerifier {
  LocalBackupSchemaVerifier({required this.factory, required this.workspace});
  final DatabaseFactory factory;
  final Directory workspace;

  Future<LocalBackupDatabaseFacts> verify(
    File input, {
    Map<String, int>? declaredRows,
    int expectedSchema = 14,
  }) async {
    if (!{14, 15, 16}.contains(expectedSchema)) {
      throw const FormatException('Unsupported trusted schema');
    }
    final requiredTables = LocalBackupManifest.requiredTablesFor(
      expectedSchema,
    );
    if (await FileSystemEntity.type(input.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await input.length() > LocalBackupManifest.maxFileBytes) {
      throw const FormatException('Invalid backup database file');
    }
    await workspace.create(recursive: true);
    if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Invalid database verification workspace');
    }
    final scratch = File('${workspace.path}/schema-${attachmentId()}.db');
    Database? trusted, imported;
    try {
      // Never derive an old-format template from the current store version:
      // that could silently upgrade the template when LocalStore advances.
      trusted = await factory.openDatabase(
        scratch.path,
        options: OpenDatabaseOptions(
          version: expectedSchema,
          singleInstance: false,
          onCreate: (db, version) => expectedSchema == 14
              ? createLocalSchema14(db)
              : expectedSchema == 15
              ? createLegacyCandidateSchema15(db)
              : createLocalSchema16(db),
        ),
      );
      final expected = await _schema(trusted);
      imported = await factory.openDatabase(
        input.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await imported.execute('PRAGMA trusted_schema = OFF');
      final trust = await imported.rawQuery('PRAGMA trusted_schema');
      if (trust.length != 1 || trust.single.values.single != 0) {
        throw const FormatException(
          'SQLite trusted-schema restriction unavailable',
        );
      }
      final version = await imported.rawQuery('PRAGMA user_version');
      if (version.length != 1 ||
          version.single.values.single != expectedSchema) {
        throw const FormatException(
          'Unsupported local database schema version',
        );
      }
      final actual = await _schema(imported);
      if (actual.length != expected.length ||
          expected.entries.any((entry) => actual[entry.key] != entry.value)) {
        throw const FormatException(
          'Backup contains an untrusted database structure',
        );
      }
      final integrity = await imported.rawQuery('PRAGMA quick_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('Backup database integrity check failed');
      }
      if ((await imported.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('Backup database foreign keys are invalid');
      }
      final tableNames = (await imported.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      )).map((row) => row['name'] as String).toSet();
      if (!tableNames.containsAll(requiredTables) ||
          tableNames.any(
            (name) =>
                !requiredTables.contains(name) && name != 'android_metadata',
          )) {
        throw const FormatException('Unexpected backup database tables');
      }
      final rows = <String, int>{};
      for (final name in tableNames) {
        // Names have just been checked against application constants.
        final count = await imported.rawQuery(
          'SELECT COUNT(*) AS n FROM "$name"',
        );
        final value = count.single['n'];
        if (value is! int || value < 0 || value > 100000000) {
          throw const FormatException('Invalid backup table count');
        }
        rows[name] = value;
      }
      if (declaredRows != null &&
          (rows.length != declaredRows.length ||
              rows.entries.any(
                (entry) => declaredRows[entry.key] != entry.value,
              ))) {
        throw const FormatException(
          'Backup table counts do not match manifest',
        );
      }
      final engine = await imported.rawQuery(
        'SELECT sqlite_version() AS version',
      );
      return LocalBackupDatabaseFacts(
        databaseSchema: expectedSchema,
        readerSQLiteVersion: engine.single['version'] as String,
        tables: Map.unmodifiable(rows),
      );
    } finally {
      await imported?.close();
      await trusted?.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('${scratch.path}$suffix');
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file) {
          await file.delete();
        }
      }
    }
  }

  Future<Map<String, String>> _schema(Database database) async {
    final rows = await database.rawQuery(
      'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name LIMIT 129',
    );
    if (rows.length > 128) {
      throw const FormatException('Too many backup schema objects');
    }
    final result = <String, String>{};
    for (final row in rows) {
      final type = row['type'], name = row['name'], table = row['tbl_name'];
      if (type is! String ||
          name is! String ||
          table is! String ||
          !{'table', 'index', 'trigger'}.contains(type)) {
        throw const FormatException('Unsupported backup schema object');
      }
      final sql = row['sql'];
      if (name.length > 128 ||
          table.length > 128 ||
          (sql != null && (sql is! String || sql.length > 65536))) {
        throw const FormatException('Invalid backup schema definition');
      }
      if (name == 'android_metadata') {
        // Android's locale bookkeeping is optional in cross-platform exports.
        if (type != 'table' ||
            _normalize(sql as String? ?? '') !=
                _normalize('CREATE TABLE android_metadata (locale TEXT)')) {
          throw const FormatException('Unexpected Android metadata schema');
        }
        continue;
      }
      result['$type/$name/$table'] = sql == null
          ? '<automatic>'
          : _normalize(sql as String);
    }
    return result;
  }

  String _normalize(String sql) {
    final tokens =
        RegExp(
          r"""'(?:[^']|'')*'|"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[^\s]""",
        ).allMatches(sql).map((match) {
          final token = match.group(0)!;
          if (token.startsWith("'")) return token;
          if (token.startsWith('"')) {
            final identifier = token.substring(1, token.length - 1);
            if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(identifier)) {
              return identifier.toLowerCase();
            }
            return token;
          }
          return token.toLowerCase();
        });
    return tokens.join(' ');
  }
}
