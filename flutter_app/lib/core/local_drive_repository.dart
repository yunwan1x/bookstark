import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'dart:math';
import 'api_client.dart';
import 'attachments.dart';
import 'drive_models.dart';
import 'drive_repository.dart';
import 'drive_source.dart';
import 'local_store.dart';

/// Logical names live in SQLite. Immutable private blob files make tree moves
/// atomic SQL operations and keep user paths out of filesystem resolution.
class LocalDriveRepository extends DriveRepository {
  LocalDriveRepository(this.store, this.root, {this.deleteBlob});
  final LocalStore store;
  final Directory root;
  final Future<void> Function(File file)? deleteBlob;
  final _random = Random.secure();
  String _key() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  bool _closed = false;
  Future<void>? _initialized;
  final _cleanupErrors = <String>[];
  List<String> get cleanupErrors => List.unmodifiable(_cleanupErrors);
  @override
  bool get local => true;
  void _check(AttachmentCancellation? cancellation) {
    if (_closed) throw StateError('File space closed');
    cancellation?.check();
  }

  Future<void> _boundary() => store.maintenance.use(() async {
    var cursor = p.normalize(root.absolute.path);
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException(
          'Private file directory contains a symbolic link',
        );
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
    await root.create(recursive: true);
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Invalid private file directory');
    }
  });

  File _blob(String key) {
    if (!RegExp(r'^[0-9a-f]{32}\.blob$').hasMatch(key)) {
      throw const FormatException('Invalid private blob identity');
    }
    return File(p.join(root.path, key));
  }

  Future<File> _existing(String key, {int? size}) =>
      store.maintenance.use(() async {
        final file = _blob(key);
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FormatException(
            'Private file is missing or is a symbolic link',
          );
        }
        if (size != null && await file.length() != size) {
          throw const FormatException(
            'Private file size does not match metadata',
          );
        }
        return file;
      });

  Future<void> _ready(AttachmentCancellation? cancellation) =>
      store.maintenance.use(() async {
        _check(cancellation);
        try {
          await (_initialized ??= _initialize());
        } catch (_) {
          _initialized = null;
          rethrow;
        }
        _check(cancellation);
        await _boundary();
      });

  Future<void> _initialize() => store.maintenance.use(() async {
    await _boundary();
    await recoverCleanup();
  });

  Future<void> _cleanupAfterCommit() => store.maintenance.use(() async {
    try {
      await recoverCleanup();
    } catch (e) {
      _cleanupErrors.add('Cleanup needs retry: $e');
    }
  });

  Future<void> recoverCleanup() => store.maintenance.use(() async {
    await _boundary();
    final db = await store.database;
    _cleanupErrors.clear();
    // A publication and its SQLite reference are performed within a database
    // write transaction, so recovery cannot see its pre-commit orphan window.
    await db.transaction((tx) async {
      final referenced = (await tx.query(
        'local_drive_nodes',
        columns: ['blob_key'],
        where: 'directory=0',
      )).map((r) => r['blob_key']).toSet();
      await for (final entry in root.list(followLinks: false)) {
        final key = p.basename(entry.path);
        if (!RegExp(
              r'^(?:[0-9a-f]{32}\.blob|\.tmp-[0-9a-f]{32})$',
            ).hasMatch(key) ||
            referenced.contains(key)) {
          continue;
        }
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          _cleanupErrors.add(key);
          continue;
        }
        try {
          final file = File(entry.path);
          if (deleteBlob != null) {
            await deleteBlob!(file);
          } else {
            await file.delete();
          }
        } catch (_) {
          _cleanupErrors.add(key);
        }
      }
    });
  });

  DriveNode _node(Map<String, Object?> row) => DriveNode(
    id: row['node_id'] as int,
    name: row['name'] as String,
    path: row['path'] as String,
    directory: row['directory'] == 1,
    size: row['file_size'] as int,
    etag: row['file_hash'] as String,
    mime: row['mime_type'] as String,
    modified: row['modify_time'] as String,
    created: row['create_time'] as String,
  );
  Future<Map<String, Object?>?> _row(DatabaseExecutor db, String path) =>
      store.maintenance.use(() async {
        final rows = await db.query(
          'local_drive_nodes',
          where: 'path=?',
          whereArgs: [path],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.single;
      });

  Future<void> _parent(DatabaseExecutor db, String path) =>
      store.maintenance.use(() async {
        if (path.isNotEmpty && (await _row(db, path))?['directory'] != 1) {
          throw const ApiFailure(404, '目录不存在 / Directory not found');
        }
      });

  Future<Map<String, Object?>> _expect(DatabaseExecutor db, DriveNode source) =>
      store.maintenance.use(() async {
        final actual = await _row(db, source.path);
        if (actual == null) throw DriveConflict(source, null);
        final node = _node(actual);
        if (node.id != source.id ||
            node.directory != source.directory ||
            node.etag != source.etag ||
            source.isPublic ||
            source.publicPath.isNotEmpty) {
          throw DriveConflict(source, node);
        }
        return actual;
      });

  Map<String, Object?> _values(
    String path, {
    required bool directory,
    required String now,
    String hash = '',
    int size = 0,
    String mime = 'inode/directory',
    String blob = '',
  }) => {
    'path': path,
    'parent_path': driveParent(path),
    'name': driveBasename(path),
    'directory': directory ? 1 : 0,
    'file_size': size,
    'file_hash': hash,
    'mime_type': mime,
    'blob_key': blob,
    'create_time': now,
    'modify_time': now,
  };
  @override
  Future<DriveProfile> profile({AttachmentCancellation? cancellation}) =>
      store.maintenance.use(() async {
        await _ready(cancellation);
        final rows = await (await store.database).query('local_drive_nodes');
        final files = rows.where((r) => r['directory'] == 0).toList();
        final blobs = <String, int>{};
        var logical = 0;
        for (final row in files) {
          final size = row['file_size'] as int;
          logical += size;
          blobs[row['blob_key'] as String] = size;
        }
        final stored = blobs.values.fold<int>(0, (a, b) => a + b);
        return DriveProfile(
          local: true,
          usage: DriveUsage(
            files: files.length,
            directories: rows.length - files.length,
            logicalBytes: logical,
            storedBytes: stored,
            deduplicatedBytes: logical - stored,
            compressionSavedBytes: 0,
            quotaBytes: 0,
          ),
          fileMaxBytes: 1024 * 1024 * 1024,
          publicMaxBytes: 0,
          publicBase: null,
        );
      });

  @override
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final parent = drivePath(path), db = await store.database;
    return db.transaction((tx) async {
      await _parent(tx, parent);
      return (await tx.query(
        'local_drive_nodes',
        where: 'parent_path=?',
        whereArgs: [parent],
        orderBy: 'directory DESC, name',
      )).map(_node).toList();
    });
  });

  @override
  Future<DriveNode> mkdir(
    String parent,
    String name, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final target = driveChild(parent, name), db = await store.database;
    return db.transaction((tx) async {
      await _parent(tx, driveParent(target));
      if (await _row(tx, target) != null) {
        throw const ApiFailure(409, '目标已存在 / Target exists');
      }
      cancellation?.check();
      final id = await tx.insert(
        'local_drive_nodes',
        _values(
          target,
          directory: true,
          now: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      return _node(
        (await tx.query(
          'local_drive_nodes',
          where: 'node_id=?',
          whereArgs: [id],
        )).single,
      );
    });
  });

  @override
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    if (file.directory) {
      throw const FormatException('Cannot download a directory');
    }
    final db = await store.database;
    return db.transaction((tx) async {
      final row = await _expect(tx, file),
          physical = await _existing(
            row['blob_key'] as String,
            size: file.size,
          );
      var start = 0, end = file.size, status = 200;
      if (range != null && (ifRange == null || ifRange == '"${file.etag}"')) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || match[1]!.isEmpty && match[2]!.isEmpty) {
          throw const ApiFailure(416, 'Invalid byte range');
        }
        if (match[1]!.isEmpty) {
          final suffix = int.parse(match[2]!);
          if (suffix <= 0 || file.size == 0) {
            throw const ApiFailure(416, 'Invalid suffix range');
          }
          start = (file.size - suffix).clamp(0, file.size);
        } else {
          start = int.parse(match[1]!);
          end = match[2]!.isEmpty
              ? file.size
              : (int.parse(match[2]!) + 1).clamp(0, file.size);
        }
        if (start >= file.size || end <= start) {
          throw const ApiFailure(416, 'Range outside file');
        }
        status = 206;
      }
      final handle = await physical.open(mode: FileMode.read);
      await handle.setPosition(start);
      Stream<List<int>> bytes() async* {
        var remaining = end - start;
        try {
          while (remaining > 0) {
            cancellation?.check();
            final chunk = await handle.read(remaining.clamp(1, 256 * 1024));
            if (chunk.isEmpty) {
              throw const FormatException('Incomplete private file');
            }
            remaining -= chunk.length;
            yield chunk;
          }
        } finally {
          await handle.close();
        }
      }

      return DriveRead(
        stream: bytes(),
        status: status,
        length: end - start,
        headers: {
          'etag': '"${file.etag}"',
          'content-length': '${end - start}',
          'accept-ranges': 'bytes',
          if (status == 206)
            'content-range': 'bytes $start-${end - 1}/${file.size}',
        },
      );
    });
  });

  Future<DriveNode> _writeBytes(
    Stream<List<int>> bytes, {
    required String target,
    required String hash,
    required int size,
    required String mime,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    if (size > 1024 * 1024 * 1024) {
      throw const ApiFailure(413, 'File exceeds local file bound');
    }
    final db = await store.database;
    File? published, staged;
    try {
      return await db.transaction((tx) async {
        await _parent(tx, driveParent(target));
        final old = await _row(tx, target);
        if (expected == null) {
          if (old != null) throw DriveConflict(null, _node(old));
        } else {
          await _expect(tx, expected);
          if (expected.path != target || expected.directory) {
            throw DriveConflict(expected, old == null ? null : _node(old));
          }
        }
        final key = '${_key()}.blob';
        staged = File(p.join(root.path, '.tmp-${_key()}'));
        final sink = await staged!.open(mode: FileMode.writeOnly);
        var count = 0;
        try {
          await for (final chunk in bytes) {
            _check(cancellation);
            count += chunk.length;
            if (count > size) {
              throw const FormatException('Source exceeds declared length');
            }
            await sink.writeFrom(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (count != size ||
            (await crypto.sha256.bind(staged!.openRead()).first).toString() !=
                hash) {
          throw const FormatException('Source hash does not match');
        }
        _check(cancellation);
        published = await staged!.rename(_blob(key).path);
        staged = null;
        final now = DateTime.now().toUtc().toIso8601String(),
            values = _values(
              target,
              directory: false,
              now: now,
              hash: hash,
              size: size,
              mime: mime,
              blob: key,
            );
        if (old == null) {
          await tx.insert('local_drive_nodes', values);
        } else {
          values.remove('create_time');
          await tx.update(
            'local_drive_nodes',
            values,
            where: 'node_id=?',
            whereArgs: [old['node_id']],
          );
        }
        return _node((await _row(tx, target))!);
      });
    } catch (_) {
      for (final file in [staged, published]) {
        if (file != null) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      rethrow;
    }
  });

  @override
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final path = drivePath(target);
    if (path.isEmpty) throw const FormatException('Missing file path');
    final node = await _writeBytes(
      source.verifiedStream(cancellation: cancellation, onSent: onSent),
      target: path,
      hash: source.hash,
      size: source.size,
      mime: lookupMimeType(source.file.name) ?? 'application/octet-stream',
      expected: expected,
      cancellation: cancellation,
    );
    // Local writes do not claim compression or hash reuse without actually
    // sharing a physical blob. Copies below genuinely share immutable bytes.
    await _cleanupAfterCommit();
    return DriveUploadResult(node, deduplicated: false);
  });

  @override
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final bytes = document.encode(content);
    if (bytes.length > maxDriveTextBytes) {
      throw const ApiFailure(413, 'Text exceeds editor bound');
    }
    final node = await _writeBytes(
      Stream.value(bytes),
      target: document.node.path,
      hash: crypto.sha256.convert(bytes).toString(),
      size: bytes.length,
      mime: document.node.mime,
      expected: document.node,
      cancellation: cancellation,
    );
    await _cleanupAfterCommit();
    return node;
  });

  Future<void> _relocate(
    DriveNode source,
    String target, {
    required bool copy,
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final destination = drivePath(target);
    if (destination.isEmpty ||
        destination == source.path ||
        destination.startsWith('${source.path}/')) {
      throw const FormatException('Invalid move or copy destination');
    }
    final db = await store.database;
    await db.transaction((tx) async {
      await _expect(tx, source);
      await _parent(tx, driveParent(destination));
      if (await _row(tx, destination) != null) {
        throw const ApiFailure(409, 'Target exists');
      }
      final tree = await tx.query(
        'local_drive_nodes',
        where: 'path=? OR substr(path,1,length(?)+1)=?',
        whereArgs: [source.path, source.path, '${source.path}/'],
        orderBy: 'length(path)',
      );
      for (final row in tree) {
        cancellation?.check();
        final oldPath = row['path'] as String,
            newPath = '$destination${oldPath.substring(source.path.length)}';
        if (copy) {
          if (row['directory'] == 0) {
            await _existing(
              row['blob_key'] as String,
              size: row['file_size'] as int,
            );
          }
          final values = Map<String, Object?>.from(row)..remove('node_id');
          values['path'] = newPath;
          values['parent_path'] = driveParent(newPath);
          values['name'] = driveBasename(newPath);
          values['create_time'] = DateTime.now().toUtc().toIso8601String();
          values['modify_time'] = values['create_time'];
          await tx.insert('local_drive_nodes', values);
        } else {
          await tx.update(
            'local_drive_nodes',
            {
              'path': newPath,
              'parent_path': driveParent(newPath),
              'name': driveBasename(newPath),
              'modify_time': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'node_id=?',
            whereArgs: [row['node_id']],
          );
        }
      }
    });
  });

  @override
  Future<void> rename(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(
    () async =>
        _relocate(source, target, copy: false, cancellation: cancellation),
  );
  @override
  Future<void> copy(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(
    () async =>
        _relocate(source, target, copy: true, cancellation: cancellation),
  );
  @override
  Future<void> remove(
    DriveNode source, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(() async {
    await _ready(cancellation);
    final db = await store.database;
    await db.transaction((tx) async {
      await _expect(tx, source);
      cancellation?.check();
      await tx.delete(
        'local_drive_nodes',
        where: 'path=? OR substr(path,1,length(?)+1)=?',
        whereArgs: [source.path, source.path, '${source.path}/'],
      );
    });
    await _cleanupAfterCommit();
  });

  @override
  Future<Uri> publish(
    DriveNode file,
    String publicPath, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(
    () async => throw UnsupportedError('Local files cannot be publicly served'),
  );
  @override
  Future<void> unpublish(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  }) => store.maintenance.use(
    () async => throw UnsupportedError('Local files cannot be publicly served'),
  );
  @override
  void dispose() {
    _closed = true;
  }
}
