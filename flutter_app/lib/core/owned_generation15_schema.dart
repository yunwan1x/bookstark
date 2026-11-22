import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'local_legacy_candidate_schema.dart';
import 'local_legacy_import_records.dart';

/// Structural gate only; activation additionally requires complete schema15
/// archive/content/provenance validation. Never migrates an input database.
final class OwnedGeneration15SchemaGate {
  Future<void> verify(
    Database actual, {
    required DatabaseFactory factory,
    required Directory workspace,
  }) async {
    final path = '${workspace.path}/owned15-template-${attachmentId()}.db';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FormatException('Schema workspace identity collision');
    }
    Database? trusted;
    try {
      trusted = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 15,
          onCreate: (db, _) => createLegacyCandidateSchema15(db),
        ),
      );
      final expected = await _schema(trusted), found = await _schema(actual);
      // Android's RW open may rewrite/create locale bookkeeping. Prove it is
      // already exactly what THIS factory/runtime expects before any RW open.
      final nativeLocale = await trusted.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='android_metadata'",
      );
      if (nativeLocale.isNotEmpty) {
        final actualLocale = await actual.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='android_metadata'",
        );
        if (actualLocale.length != 1 ||
            jsonEncode(
                  await actual.rawQuery('PRAGMA table_info(android_metadata)'),
                ) !=
                jsonEncode(
                  await trusted.rawQuery('PRAGMA table_info(android_metadata)'),
                ) ||
            jsonEncode(
                  await actual.rawQuery(
                    'SELECT rowid,locale,typeof(locale) AS storage_type FROM android_metadata ORDER BY rowid',
                  ),
                ) !=
                jsonEncode(
                  await trusted.rawQuery(
                    'SELECT rowid,locale,typeof(locale) AS storage_type FROM android_metadata ORDER BY rowid',
                  ),
                )) {
          throw const FormatException(
            'Owned locale requires explicit staging before activation',
          );
        }
      }
      if (expected.length != found.length ||
          expected.entries.any((e) => found[e.key] != e.value)) {
        throw const FormatException('Untrusted owned generation15 structure');
      }
      final version = await actual.rawQuery('PRAGMA user_version');
      if (version.length != 1 || version.single.values.single != 15) {
        throw const FormatException('Owned generation15 required');
      }
      final check = await actual.rawQuery('PRAGMA quick_check');
      if (check.length != 1 ||
          check.single.values.single != 'ok' ||
          (await actual.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('Owned generation15 integrity failed');
      }
    } finally {
      await trusted?.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File(path + suffix);
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          await file.delete();
        } else if (type != FileSystemEntityType.notFound) {
          throw const FormatException(
            'Unexpected schema verification artifact',
          );
        }
      }
    }
  }

  /// Every table, including NULL/blob distinctions, sequence and locale.
  /// No row contents or digests are printed or persisted.
  Future<Map<String, String>> rowDigests(
    Database db, {
    bool Function()? isCurrent,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Positive digest deadline required');
    }
    final clock = Stopwatch()..start();
    void guard() {
      if (clock.elapsed >= timeout || !(isCurrent?.call() ?? true)) {
        throw const FormatException(
          'Owned row verification cancelled or expired',
        );
      }
    }

    final result = <String, String>{};
    try {
      // Await transaction rollback on timeout/cancel before the caller closes
      // this read-only DB. Never return partial digests or start a RW open.
      await db.transaction((tx) async {
        guard();
        final names = await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name LIMIT 65",
        );
        guard();
        if (names.length > 64) {
          throw const FormatException('Owned table count bound');
        }
        for (final item in names) {
          guard();
          final name = item['name'];
          if (name is! String ||
              !RegExp(r'^[a-z_][a-z0-9_]{0,127}$').hasMatch(name)) {
            throw const FormatException('Owned table identity');
          }
          final info = await tx.rawQuery('PRAGMA table_info("$name")');
          guard();
          if (info.isEmpty || info.length > 128) {
            throw const FormatException('Owned column bound');
          }
          final columns = <String>[];
          for (final field in info) {
            final col = field['name'];
            if (col is! String ||
                !RegExp(r'^[a-z_][a-z0-9_]{0,127}$').hasMatch(col)) {
              throw const FormatException('Owned column identity');
            }
            columns.add(col);
          }
          // Existing15 provenance payloads may legitimately reach64MiB.
          // Keep that source contract; bound one large original row separately.
          final rowLimit = LegacyImportRecords.maxPayloadBytes + 1024 * 1024;
          final sizes = columns
              .map((c) => 'coalesce(length(CAST("$c" AS BLOB)),0)')
              .join('+');
          final projection = <String>[];
          for (var i = 0; i < columns.length; i++) {
            final c = '"${columns[i]}"', n = i.toString();
            projection.add('typeof($c) AS _kind$n');
            projection.add(
              "CASE WHEN typeof($c) IN ('text','blob') THEN CAST($c AS BLOB) ELSE $c END AS _value$n",
            );
          }
          final sink = _Digest(), hash = sha256.startChunkedConversion(sink);
          var count = 0;
          int? cursor;
          while (true) {
            guard();
            // Metadata is bounded to 128 IDs/sizes, never 128 large bodies.
            final metadata = await tx.rawQuery(
              'SELECT rowid AS _rowid,($sizes) AS _bytes FROM "$name" ${cursor == null ? '' : 'WHERE rowid>? '}ORDER BY rowid LIMIT 128',
              cursor == null ? const [] : [cursor],
            );
            guard();
            if (metadata.isEmpty) break;
            var at = 0;
            while (at < metadata.length) {
              guard();
              var last = at, total = 0;
              while (last < metadata.length) {
                final rowid = metadata[last]['_rowid'],
                    bytes = metadata[last]['_bytes'];
                if (rowid is! int ||
                    bytes is! int ||
                    bytes < 0 ||
                    bytes > rowLimit ||
                    (cursor != null && rowid <= cursor)) {
                  throw const FormatException(
                    'Owned row byte or identity bound',
                  );
                }
                if (last > at && total + bytes > 256 * 1024) break;
                total += bytes;
                last++;
                if (total > 256 * 1024) {
                  break; // one bounded large row, never trim
                }
              }
              final firstId = metadata[at]['_rowid'],
                  lastId = metadata[last - 1]['_rowid'];
              final rows = await tx.rawQuery(
                'SELECT rowid AS _rowid,${projection.join(',')} FROM "$name" WHERE rowid>=? AND rowid<=? ORDER BY rowid',
                [firstId, lastId],
              );
              guard();
              if (rows.length != last - at) {
                throw const FormatException('Owned rows changed');
              }
              for (var offset = 0; offset < rows.length; offset++) {
                guard();
                final row = rows[offset];
                if (row['_rowid'] != metadata[at + offset]['_rowid']) {
                  throw const FormatException('Owned row identity changed');
                }
                final fields = <Object?>[
                  ['rowid', row['_rowid']],
                ];
                for (var i = 0; i < columns.length; i++) {
                  final kind = row['_kind$i'], value = row['_value$i'];
                  if ((kind == 'text' || kind == 'blob') &&
                      value is Uint8List) {
                    fields.add([columns[i], kind, base64Encode(value)]);
                  } else if (kind == 'null' && value == null) {
                    fields.add([columns[i], 'null']);
                  } else if (kind == 'integer' && value is int) {
                    fields.add([columns[i], 'integer', value.toString()]);
                  } else if (kind == 'real' &&
                      value is double &&
                      value.isFinite) {
                    fields.add([columns[i], 'real', value.toString()]);
                  } else {
                    throw const FormatException(
                      'Unexpected owned SQLite storage type',
                    );
                  }
                }
                hash.add(utf8.encode(jsonEncode(fields)));
                hash.add([10]);
                count++;
                if (count > 100000000) {
                  throw const FormatException('Owned row count bound');
                }
              }
              at = last;
              await Future<void>.delayed(Duration.zero);
              guard();
            }
            cursor = metadata.last['_rowid'] as int;
          }
          hash.close();
          result[name] = sink.value!.toString();
        }
      }, exclusive: false);
      guard();
      return result;
    } finally {
      clock.stop();
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

class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) {
    if (value != null) throw StateError('Digest duplicated');
    value = digest;
  }

  @override
  void close() {}
}
