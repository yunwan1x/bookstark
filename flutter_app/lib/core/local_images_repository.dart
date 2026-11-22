import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'api_client.dart';
import 'attachments.dart';
import 'image_content.dart';
import 'images_repository.dart';
import 'local_attachments.dart';
import 'local_store.dart';

typedef ImageDimensionsReader = Future<(int, int)> Function(Uint8List bytes);

class LocalImagesRepository extends ImagesRepository {
  LocalImagesRepository(
    this.store,
    this.attachments, {
    this.dimensionsReader,
    this.isCurrentScope,
    DateTime Function()? clock,
    Future<void> Function(File file)? cleanupFile,
  }) : clock = clock ?? DateTime.now,
       _cleanupFile =
           cleanupFile ??
           ((file) async {
             await file.delete();
           });
  final LocalStore store;
  final bool Function()? isCurrentScope;
  final LocalAttachments attachments;
  final ImageDimensionsReader? dimensionsReader;
  final DateTime Function() clock;
  final Future<void> Function(File file) _cleanupFile;
  Future<void>? _discovery;
  bool _closed = false;
  @override
  bool get publicLinks => false;
  void _open() {
    bool current;
    try {
      current = isCurrentScope?.call() ?? true;
    } catch (_) {
      current = false;
    }
    if (_closed || !current) throw StateError('Image library retired');
  }

  String _id(Uri uri) {
    if (!attachments.owns(uri)) {
      throw const FormatException('Invalid local image reference');
    }
    return uri.pathSegments.first;
  }

  File _file(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid local image ID');
    }
    return File('${attachments.directory.path}/$id');
  }

  Uri _uri(String id, String name) =>
      Uri.parse('bookstark-attachment:///$id/${Uri.encodeComponent(name)}');
  ManagedImage _image(Map row) => ManagedImage(
    id: row['image_id'] as int,
    name: row['file_name'] as String,
    uri: _uri(row['attachment_id'] as String, row['file_name'] as String),
    category: row['category'] as String,
    mime: row['mime_type'] as String,
    size: row['file_size'] as int,
    width: row['width'] as int,
    height: row['height'] as int,
    createdOn: row['create_time'] as String,
  );
  UploadedImageReference _reference(Map row) {
    final image = _image(row);
    return UploadedImageReference(
      id: image.id,
      name: image.name,
      uri: image.uri,
      size: image.size,
      width: image.width,
      height: image.height,
    );
  }

  Future<Map<String, String>> _names(
    Set<String> ids,
  ) => store.maintenance.use(() async {
    if (ids.isEmpty) return {};
    final db = await store.database;
    final rows = await db.rawQuery(
      "SELECT content AS body FROM notes WHERE deleted=0 AND content LIKE '%bookstark-attachment:%' UNION ALL SELECT markdown AS body FROM documents WHERE deleted=0 AND markdown LIKE '%bookstark-attachment:%'",
    );
    final result = <String, String>{};
    for (final row in rows) {
      for (final item in noteAttachments(
        row['body'] as String,
        attachments.owns,
      )) {
        if (!attachments.owns(item.uri)) continue;
        final id = _id(item.uri);
        if (!ids.contains(id) || result.containsKey(id)) continue;
        try {
          result[id] = attachmentName(item.uri.pathSegments.last);
        } on FormatException {
          continue;
        }
      }
    }
    return result;
  });

  Future<String> _hash(File file) => store.maintenance.use(() async {
    var length = 0;
    final chunks = file.openRead().map((chunk) {
      length += chunk.length;
      if (length > maxImageTransferBytes) {
        throw const ApiFailure(
          413,
          '图片超过哈希读取上限 / Image exceeds hash read bound',
        );
      }
      return chunk;
    });
    return (await crypto.sha256.bind(chunks).first).toString();
  });

  Future<void> _discover() => store.maintenance.use(() async {
    _open();
    final pending = _discovery;
    if (pending != null) return pending;
    final future = _scan();
    _discovery = future;
    try {
      await future;
    } finally {
      if (identical(_discovery, future)) _discovery = null;
    }
  });

  Future<void> _scan() => store.maintenance.use(() async {
    _open();
    await attachments.directory.create(recursive: true);
    final db = await store.database;
    final rows = await db.query('local_images');
    final known = {for (final row in rows) row['attachment_id'] as String: row};
    final files = <String, File>{};
    await for (final entry in attachments.directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final id = entry.uri.pathSegments.last;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      files[id] = entry;
    }
    final names = await _names({
      for (final id in files.keys)
        if (known[id] == null || known[id]!['file_name'] == id) id,
    });
    final present = <String>{};
    for (final entry in files.entries) {
      _open();
      final id = entry.key, file = entry.value, old = known[entry.key];
      if (old?['deleted'] == 1) continue;
      try {
        final stat = await file.stat();
        final modified = stat.modified.toIso8601String();
        if (old != null &&
            old['file_present'] == 1 &&
            old['file_size'] == stat.size &&
            old['modify_time'] == modified &&
            !(old['file_name'] == id && names.containsKey(id))) {
          present.add(id);
          continue;
        }
        final header = BytesBuilder(copy: false);
        await for (final chunk in file.openRead(
          0,
          stat.size < 4096 ? stat.size : 4096,
        )) {
          header.add(chunk);
        }
        final mime = imageContentMime(header.takeBytes());
        if (mime == null) continue;
        final hash = stat.size <= maxImageTransferBytes
            ? await _hash(file)
            : '';
        var width = 0, height = 0;
        final name = names[id] ?? old?['file_name'] as String? ?? id;
        if (mime != 'image/svg+xml' &&
            dimensionsReader != null &&
            stat.size <= maxImageTransferBytes) {
          try {
            final bytes = await attachments.read(
              _uri(id, name),
              maxBytes: maxImageTransferBytes,
            );
            final dimensions = await dimensionsReader!(bytes);
            width = dimensions.$1;
            height = dimensions.$2;
          } catch (_) {
            /* Unknown dimensions are kept explicit. */
          }
        }
        final after = await file.stat();
        if (after.size != stat.size || after.modified != stat.modified) {
          continue;
        }
        final current = await db.query(
          'local_images',
          where: 'attachment_id = ?',
          whereArgs: [id],
        );
        final row = current.isEmpty ? null : current.single;
        if (row?['deleted'] == 1) continue;
        final values = <String, Object?>{
          'attachment_id': id,
          'file_name': row != null && row['file_name'] != id
              ? row['file_name']
              : name,
          'category': row?['category'] ?? '',
          'mime_type': mime,
          'file_hash': hash,
          'file_size': stat.size,
          'width': width,
          'height': height,
          'create_time': row?['create_time'] ?? '',
          'modify_time': modified,
          'file_present': 1,
        };
        if (row == null) {
          _open();
          await db.insert('local_images', values);
        } else {
          _open();
          await db.update(
            'local_images',
            values,
            where: 'image_id = ?',
            whereArgs: [row['image_id']],
          );
        }
        present.add(id);
      } on FileSystemException {
        continue;
      }
    }
    for (final row in rows) {
      if (row['deleted'] == 0 &&
          row['file_present'] == 1 &&
          !present.contains(row['attachment_id'])) {
        _open();
        await db.update(
          'local_images',
          {'file_present': 0},
          where: 'image_id = ? AND deleted = 0',
          whereArgs: [row['image_id']],
        );
      }
    }
  });

  @override
  Future<ImagesPageResult> list(
    ImagesQuery query,
  ) => store.maintenance.use(() async {
    query.parameters();
    await _discover();
    final db = await store.database;
    final where =
        'deleted = 0 AND file_present = 1${query.keyword.isEmpty ? '' : ' AND file_name LIKE ?'}${query.category == null ? '' : ' AND category = ?'}';
    final args = <Object?>[
      if (query.keyword.isNotEmpty) '%${query.keyword}%',
      if (query.category != null) query.category!.name,
    ];
    final rows = await db.query(
      'local_images',
      where: where,
      whereArgs: args,
      orderBy: 'create_time DESC, image_id DESC',
      limit: 20,
      offset: (query.page - 1) * 20,
    );
    final total =
        (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM local_images WHERE $where',
              args,
            )).single['n']
            as int;
    final size =
        (await db.rawQuery(
              'SELECT COALESCE(SUM(file_size),0) AS n FROM local_images WHERE deleted=0 AND file_present=1',
            )).single['n']
            as int;
    return ImagesPageResult(
      rows.map(_image).toList(),
      total: total,
      page: query.page,
      pageSize: 20,
      totalImageBytes: size,
    );
  });

  @override
  Future<UploadedImageReference?> byHash(String hash) =>
      store.maintenance.use(() async {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('Invalid image hash');
        }
        await _discover();
        final rows = await (await store.database).query(
          'local_images',
          where: 'file_hash = ? AND deleted=0 AND file_present=1',
          whereArgs: [hash],
          limit: 1,
        );
        return rows.isEmpty ? null : _reference(rows.single);
      });

  @override
  Future<UploadedImageReference> upload(
    ImageUploadPayload payload, {
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) => store.maintenance.use(() async {
    _open();
    cancellation?.check();
    final existing = await byHash(payload.hash);
    if (existing != null) return existing;
    final mime = imageContentMime(payload.bytes);
    if (mime == null) {
      throw const FormatException('不支持的图片格式 / Unsupported image format');
    }
    final id = attachmentId(), directory = attachments.directory.path;
    final temporary = File('$directory/.image-upload-$id');
    final target = _file(id);
    var renamed = false, committed = false;
    try {
      final writer = await temporary.open(mode: FileMode.writeOnly);
      try {
        for (var start = 0; start < payload.bytes.length; start += 64 * 1024) {
          cancellation?.check();
          final end = (start + 64 * 1024).clamp(0, payload.bytes.length);
          await writer.writeFrom(payload.bytes, start, end);
          onSent?.call(end, payload.bytes.length);
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      cancellation?.check();
      _open();
      _open();
      await temporary.rename(target.path);
      renamed = true;
      var width = 0, height = 0;
      if (mime != 'image/svg+xml' && dimensionsReader != null) {
        try {
          final dimensions = await dimensionsReader!(payload.bytes);
          width = dimensions.$1;
          height = dimensions.$2;
        } catch (_) {}
      }
      final stat = await target.stat();
      cancellation?.check();
      final db = await store.database;
      _open();
      final imageId = await db.insert('local_images', {
        'attachment_id': id,
        'file_name': payload.name,
        'category': payload.category.name,
        'mime_type': mime,
        'file_hash': payload.hash,
        'file_size': stat.size,
        'width': width,
        'height': height,
        'create_time': clock().toIso8601String(),
        'modify_time': stat.modified.toIso8601String(),
      });
      committed = true;
      return UploadedImageReference(
        id: imageId,
        name: payload.name,
        uri: _uri(id, payload.name),
        size: stat.size,
        width: width,
        height: height,
      );
    } finally {
      if (!committed) {
        try {
          if (renamed && await target.exists()) await target.delete();
          if (await temporary.exists()) await temporary.delete();
        } on FileSystemException {
          /* A subsequent hash verification can discover a retained original. */
        }
      }
    }
  });

  Future<Map<String, Object?>?> _record(ManagedImage item) =>
      store.maintenance.use(() async {
        if (item.id <= 0) throw const FormatException('Invalid image ID');
        final rows = await (await store.database).query(
          'local_images',
          where: 'image_id = ?',
          whereArgs: [item.id],
        );
        if (rows.isEmpty) return null;
        final row = rows.single;
        if (row['attachment_id'] != _id(item.uri)) {
          throw const FormatException('Local image reference mismatch');
        }
        return row;
      });

  File _quarantine(String value) {
    if (!RegExp(
      r'^\.image-delete-[a-f0-9]{32}-[a-f0-9]{32}$',
    ).hasMatch(value)) {
      throw const FormatException('Invalid image cleanup path');
    }
    return File('${attachments.directory.path}/$value');
  }

  @override
  Future<ImageRemovalResult> remove(ManagedImage item) =>
      store.maintenance.use(() async {
        _open();
        final db = await store.database, row = await _record(item);
        if (row == null) return verifyRemoval(item);
        if (row['deleted'] == 1) {
          final name = row['quarantine_name'] as String;
          if (name.isNotEmpty) {
            try {
              final file = _quarantine(name);
              if (await file.exists()) await _cleanupFile(file);
              _open();
              await db.update(
                'local_images',
                {'quarantine_name': ''},
                where: 'image_id = ?',
                whereArgs: [item.id],
              );
            } on FileSystemException {
              return const ImageRemovalResult(
                recordRemoved: true,
                linkAvailable: false,
                cleanupPending: true,
              );
            }
          }
          return const ImageRemovalResult(
            recordRemoved: true,
            linkAvailable: false,
          );
        }
        final id = row['attachment_id'] as String;
        final original = _file(id);
        final name = '.image-delete-$id-${attachmentId()}';
        final staged = _quarantine(name);
        final exists = await FileSystemEntity.type(
          original.path,
          followLinks: false,
        );
        if (exists == FileSystemEntityType.link ||
            exists == FileSystemEntityType.directory) {
          throw const FormatException(
            '图片文件已变为链接或目录，请核对 / Image file became a link or directory',
          );
        }
        var moved = false;
        if (exists == FileSystemEntityType.file) {
          _open();
          await original.rename(staged.path);
          moved = true;
        }
        try {
          _open();
          await db.transaction((tx) async {
            _open();
            await tx.update(
              'local_images',
              {
                'deleted': 1,
                'file_present': 0,
                'quarantine_name': moved ? name : '',
              },
              where: 'image_id = ? AND deleted=0',
              whereArgs: [item.id],
            );
          });
        } catch (_) {
          if (moved) await staged.rename(original.path);
          rethrow;
        }
        if (moved) {
          try {
            await _cleanupFile(staged);
            _open();
            await db.update(
              'local_images',
              {'quarantine_name': ''},
              where: 'image_id = ?',
              whereArgs: [item.id],
            );
          } on FileSystemException {
            return const ImageRemovalResult(
              recordRemoved: true,
              linkAvailable: false,
              cleanupPending: true,
            );
          }
        }
        return const ImageRemovalResult(
          recordRemoved: true,
          linkAvailable: false,
        );
      });

  @override
  Future<List<ManagedImage>> pendingCleanup() =>
      store.maintenance.use(() async {
        _open();
        final rows = await (await store.database).query(
          'local_images',
          where: "deleted=1 AND quarantine_name != ''",
          orderBy: 'image_id',
        );
        return rows.map(_image).toList();
      });

  @override
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item) =>
      store.maintenance.use(() async {
        _open();
        final row = await _record(item);
        final exists = await FileSystemEntity.type(
          _file(_id(item.uri)).path,
          followLinks: false,
        );
        return ImageRemovalResult(
          recordRemoved: row == null || row['deleted'] == 1,
          linkAvailable: exists == FileSystemEntityType.file,
          cleanupPending:
              row != null && (row['quarantine_name'] as String).isNotEmpty,
        );
      });

  @override
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  }) => store.maintenance.use(() async {
    _open();
    final id = _id(uri);
    if (await FileSystemEntity.type(_file(id).path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const ApiFailure(404, '本地图片不存在 / Local image unavailable');
    }
    return attachments.read(uri, maxBytes: maxBytes);
  });

  Future<XFile> localShareFile(ManagedImage item) =>
      store.maintenance.use(() async {
        _open();
        final id = _id(item.uri);
        if (await FileSystemEntity.type(_file(id).path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const ApiFailure(404, '本地图片不存在 / Local image unavailable');
        }
        return XFile(_file(id).path, name: item.name, mimeType: item.mime);
      });

  @override
  void dispose() {
    _closed = true;
  }
}
