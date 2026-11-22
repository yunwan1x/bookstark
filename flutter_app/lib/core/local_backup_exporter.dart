import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'attachments.dart';
import 'local_backup_codec.dart';
import 'local_backup_content.dart';
import 'local_backup_schema.dart';
import 'local_store.dart';
import 'owned_writable_generation15.dart';
import 'owned_generation15_staging.dart';
import 'package:sqflite/sqflite.dart';

class CompletedLocalBackup {
  CompletedLocalBackup._(
    this._temporary, {
    required this.file,
    required this.manifest,
    required this.size,
    required this.sha256,
    required this.contentReport,
  });
  final File file;
  final LocalBackupManifest manifest;
  final int size;
  final String sha256;
  final LocalBackupContentReport contentReport;
  String get manifestSHA256 => crypto.sha256
      .convert(utf8.encode(jsonEncode(manifest.toJson())))
      .toString();
  final Directory _temporary;
  bool _disposed = false;

  /// Only the random task directory owned by this export is removed.
  /// Call after the system file picker/export has finished or been cancelled.
  Future<void> dispose() async {
    if (_disposed) return;
    if (await FileSystemEntity.type(_temporary.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await _temporary.delete(recursive: true);
    }
    _disposed = true;
  }
}

/// Caller supplies fixed application-private roots, never archive/user paths.
/// The pending-recovery preflight must use durable metadata from every local
/// draft store and fail if a draft or uncertain commit still needs attention.
class LocalBackupExporter {
  LocalBackupExporter({
    required this.store,
    required this.attachments,
    required this.driveBlobs,
    required this.workspace,
    required this.checkPendingRecovery,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final LocalStore store;
  final Directory attachments, driveBlobs, workspace;
  final Future<void> Function() checkPendingRecovery;
  final DateTime Function() clock;

  Future<CompletedLocalBackup> create() => store.maintenance.exclusive(
    () => _createBackup(
      obtainDatabase: () => store.database,
      snapshotDatabase: (database, target) =>
          database.execute('VACUUM INTO ?', [target.path]),
      factory: store.factory,
      attachments: attachments,
      driveBlobs: driveBlobs,
      workspace: workspace,
      checkPendingRecovery: checkPendingRecovery,
      clock: clock,
      allowedSchemas: const {14, 16},
    ),
  );
}

/// Separate sealed capability: a read-only candidate cannot construct this
/// exporter. Historical plaintext remains plaintext in the complete backup.
class OwnedGeneration15BackupExporter {
  OwnedGeneration15BackupExporter({
    required this.owner,
    required this.factory,
    required this.workspace,
    required this.checkPendingRecovery,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final OwnedWritableGeneration15 owner;
  final DatabaseFactory factory;
  final Directory workspace;
  final Future<void> Function() checkPendingRecovery;
  final DateTime Function() clock;

  Future<CompletedLocalBackup> create() => owner.exclusiveSnapshot((
    database,
  ) async {
    await owner.content.crypto.drain();
    await owner.confirmCurrent();
    final completed = await _createBackup(
      obtainDatabase: () async => database,
      snapshotDatabase: (database, target) async {
        await owner.confirmCurrent();
        // VACUUM can renumber hidden rowids in provenance tables. Checkpoint
        // under the exclusive writer gate, then copy the original main file.
        final rows = await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        if (rows.length != 1 || rows.single.values.first != 0) {
          throw const FormatException('Owned snapshot checkpoint unavailable');
        }
        final wal = File('${owner.generation.databasePath}-wal');
        final walType = await FileSystemEntity.type(
          wal.path,
          followLinks: false,
        );
        if (walType != FileSystemEntityType.notFound &&
            (walType != FileSystemEntityType.file || await wal.length() != 0)) {
          throw const FormatException('Owned snapshot has uncheckpointed data');
        }
        await owner.confirmCurrent();
        await File(owner.generation.databasePath).copy(target.path);
        await owner.confirmCurrent();
      },
      factory: factory,
      attachments: owner.generation.attachments,
      driveBlobs: owner.generation.driveBlobs,
      workspace: workspace,
      checkPendingRecovery: checkPendingRecovery,
      clock: clock,
      allowedSchemas: const {15},
    );
    try {
      await owner.confirmCurrent();
      return completed;
    } catch (_) {
      await completed.dispose();
      rethrow;
    }
  });
}

/// A complete backup built from a freshly reconstructed closed staging copy.
/// This grants no writer and never consumes an existing review session.
class StagedGeneration15BackupExporter {
  StagedGeneration15BackupExporter({
    required this.stage,
    required this.factory,
    required this.workspace,
    required this.checkPendingRecovery,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final OwnedGeneration15Staging stage;
  final DatabaseFactory factory;
  final Directory workspace;
  final Future<void> Function() checkPendingRecovery;
  final DateTime Function() clock;
  Future<CompletedLocalBackup> create() async {
    CompletedLocalBackup? completed;
    try {
      return await stage.readSnapshot((database) async {
        final result = await _createBackup(
          obtainDatabase: () async => database,
          snapshotDatabase: (database, target) async {
            await File(stage.generation.databasePath).copy(target.path);
          },
          factory: factory,
          attachments: stage.generation.attachments,
          driveBlobs: stage.generation.driveBlobs,
          workspace: workspace,
          checkPendingRecovery: checkPendingRecovery,
          clock: clock,
          allowedSchemas: const {15},
        );
        completed = result;
        return result;
      });
    } catch (_) {
      await completed?.dispose();
      rethrow;
    }
  }
}

Future<CompletedLocalBackup> _createBackup({
  required Future<Database> Function() obtainDatabase,
  required Future<void> Function(Database, File) snapshotDatabase,
  required DatabaseFactory factory,
  required Directory attachments,
  required Directory driveBlobs,
  required Directory workspace,
  required Future<void> Function() checkPendingRecovery,
  required DateTime Function() clock,
  required Set<int> allowedSchemas,
}) async {
  await checkPendingRecovery();
  await workspace.create(recursive: true);
  if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException('Invalid private backup workspace');
  }
  final id = attachmentId();
  final task = Directory('${workspace.path}/export-$id');
  if (await FileSystemEntity.type(task.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Backup task identity already exists');
  }
  await task.create();
  var completed = false;
  try {
    final database = await obtainDatabase();
    final runtime = await database.rawQuery(
      'SELECT sqlite_version() AS version',
    );
    final sqliteVersion = runtime.single['version'] as String;
    final versionRows = await database.rawQuery('PRAGMA user_version');
    final schemaVersion = versionRows.single.values.single;
    if (schemaVersion is! int || !allowedSchemas.contains(schemaVersion)) {
      throw const FormatException('Unsupported active backup schema');
    }
    final snapshot = File('${task.path}/content.db');
    // This is outside a SQL transaction. The operation gate holds every
    // registered repository/blob writer until serialization has finished.
    await snapshotDatabase(database, snapshot);
    final facts = await LocalBackupSchemaVerifier(
      factory: factory,
      workspace: Directory('${task.path}/schema'),
    ).verify(snapshot, expectedSchema: schemaVersion);
    final sources = <String, File>{'database/content.db': snapshot};
    await _collect(attachments, 'attachments', sources);
    await _collect(driveBlobs, 'drive-blobs', sources);
    final declarations = <LocalBackupFile>[];
    var total = 0;
    for (final entry in sources.entries) {
      final size = await entry.value.length();
      total += size;
      if (size > LocalBackupManifest.maxFileBytes ||
          total > LocalBackupManifest.maxTotalBytes) {
        throw const FormatException('Local backup exceeds its size limit');
      }
      final hash = _HashResult();
      final sink = crypto.sha256.startChunkedConversion(hash);
      var read = 0;
      try {
        await for (final chunk in entry.value.openRead()) {
          read += chunk.length;
          if (read > size) {
            throw const FormatException('Private source changed while hashing');
          }
          sink.add(chunk);
        }
      } finally {
        sink.close();
      }
      if (read != size || hash.value == null) {
        throw const FormatException('Private source changed while hashing');
      }
      declarations.add(
        LocalBackupFile(
          path: entry.key,
          bytes: size,
          sha256: hash.value!.toString(),
        ),
      );
    }
    final manifest = LocalBackupManifest(
      databaseSchema: schemaVersion,
      id: id,
      createdAt: clock().toUtc().toIso8601String(),
      sqliteVersion: sqliteVersion,
      tables: facts.tables,
      files: declarations,
    );
    final contentReport = await LocalBackupContentVerifier(
      factory,
    ).verify(snapshot, manifest, facts);
    final archive = File('${task.path}/bookstark-backup.bsbackup');
    final output = archive.openWrite();
    final result = _HashResult();
    final hash = crypto.sha256.startChunkedConversion(result);
    var bytes = 0;
    try {
      final stream =
          LocalBackupCodec.encode(
            manifest,
            (entry) => sources[entry.path]!.openRead(),
          ).map((chunk) {
            hash.add(chunk);
            bytes += chunk.length;
            return chunk;
          });
      await output.addStream(stream);
      await output.flush();
    } finally {
      hash.close();
      await output.close();
    }
    if (result.value == null || await archive.length() != bytes) {
      throw const FormatException('Private backup file did not finish');
    }
    completed = true;
    return CompletedLocalBackup._(
      task,
      file: archive,
      manifest: manifest,
      size: bytes,
      sha256: result.value!.toString(),
      contentReport: contentReport,
    );
  } finally {
    if (!completed &&
        await FileSystemEntity.type(task.path, followLinks: false) ==
            FileSystemEntityType.directory) {
      await task.delete(recursive: true);
    }
  }
}

Future<void> _collect(
  Directory directory,
  String prefix,
  Map<String, File> target,
) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    throw const FormatException('Private backup source is not a directory');
  }
  final files = <File>[];
  await for (final entry in directory.list(followLinks: false)) {
    if (await FileSystemEntity.type(entry.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException(
        'Private backup contains a link or nested directory',
      );
    }
    files.add(File(entry.path));
    if (target.length + files.length > LocalBackupManifest.maxFiles) {
      throw const FormatException('Local backup has too many files');
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    // Validate before opening bytes, even though roots are private/fixed.
    final declaration = LocalBackupFile(
      path: '$prefix/$name',
      bytes: await file.length(),
      sha256: '0' * 64,
    );
    target[declaration.path] = file;
  }
}

class _HashResult implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
