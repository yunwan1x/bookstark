import 'package:file_selector/file_selector.dart';
import 'package:mime/mime.dart';
import 'attachments.dart' show attachmentId, attachmentName;
import 'drive_source.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'drive_models.dart';
import 'local_drive_repository.dart';
import 'local_store.dart';
import 'local_html_preview_document.dart';

class HtmlResourceBinding {
  const HtmlResourceBinding({
    required this.path,
    required this.nodeId,
    required this.hash,
  });
  final String path, hash;
  final int nodeId;
  bool same(HtmlResourceBinding other) =>
      path == other.path && nodeId == other.nodeId && hash == other.hash;
}

class HtmlResourceChoice {
  const HtmlResourceChoice({required this.path, required this.node});
  final String path;
  final DriveNode node;
}

class HtmlBoundResource {
  const HtmlBoundResource(this.binding, this.node);
  final HtmlResourceBinding binding;
  final DriveNode? node;
  bool get changed => node != null && node!.etag != binding.hash;
}

class HtmlResourceConflict implements Exception {
  const HtmlResourceConflict();
}

class HtmlResourceUnavailable implements Exception {
  const HtmlResourceUnavailable(this.path);
  final String path;
}

/// Resource IDs bind to immutable private drive blobs, never arbitrary paths.
/// A file change requires another explicit approval before scripts can read it.
class LocalHtmlResourcesRepository {
  LocalHtmlResourcesRepository(
    this.store,
    this.drive, {
    required this.collection,
  }) {
    if (store.path != drive.store.path ||
        !{'note', 'article'}.contains(collection)) {
      throw const FormatException('Local HTML resource scope mismatch');
    }
  }
  final LocalStore store;
  final LocalDriveRepository drive;
  final String collection;
  Future<void> _owned(DatabaseExecutor db, int id) =>
      store.maintenance.use(() async {
        if (id <= 0) {
          throw const FormatException('Invalid local HTML resource owner');
        }
        final rows = await db.query(
          'notes',
          columns: ['id'],
          where: 'id=? AND collection=? AND editor_type=? AND deleted=0',
          whereArgs: [id, collection, 'html'],
        );
        if (rows.length != 1) {
          throw const FormatException('Active local HTML note required');
        }
      });

  DriveNode _node(Map<String, Object?> row) => DriveNode(
    id: row['node_id'] as int,
    name: row['name'] as String,
    path: drivePath(row['path'] as String),
    directory: row['directory'] == 1,
    size: row['file_size'] as int,
    etag: row['file_hash'] as String,
    mime: row['mime_type'] as String,
    modified: row['modify_time'] as String,
    created: row['create_time'] as String,
  );
  Future<List<HtmlResourceBinding>> _bindings(DatabaseExecutor db, int id) =>
      store.maintenance.use(
        () async =>
            (await db.query(
              'html_preview_resources',
              where: 'note_id=?',
              whereArgs: [id],
              orderBy: 'resource_path',
            )).map((row) {
              final path = row['resource_path'] as String,
                  hash = row['approved_hash'] as String;
              final nodeId = row['node_id'] as int;
              if (!validLocalHtmlResourcePath(path) ||
                  path == 'index.html' ||
                  nodeId <= 0 ||
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
                throw const FormatException('Invalid HTML resource binding');
              }
              return HtmlResourceBinding(
                path: path,
                nodeId: nodeId,
                hash: hash,
              );
            }).toList(),
      );
  bool _same(List<HtmlResourceBinding> a, List<HtmlResourceBinding> b) =>
      a.length == b.length &&
      a.map((row) => row.path).toSet().length == a.length &&
      a.every((row) => b.any(row.same));

  Future<List<HtmlBoundResource>> list(int noteId) => store.maintenance.use(
    () async {
      final db = await store.database;
      await _owned(db, noteId);
      final bindings = await _bindings(db, noteId);
      final result = <HtmlBoundResource>[];
      for (final binding in bindings) {
        final rows = await db.query(
          'local_drive_nodes',
          where: 'node_id=? AND directory=0',
          whereArgs: [binding.nodeId],
        );
        result.add(
          HtmlBoundResource(binding, rows.isEmpty ? null : _node(rows.single)),
        );
      }
      await _owned(db, noteId);
      return result;
    },
  );

  /// Imported attachments remain visible in the local file library even if
  /// the resource-selection sheet is cancelled; binding is a separate action.
  Future<DriveNode> importFile(int noteId, XFile file) =>
      store.maintenance.use(() async {
        await _owned(await store.database, noteId);
        final mime = lookupMimeType(file.name) ?? 'application/octet-stream';
        final normalized =
            {'text/javascript', 'application/x-javascript'}.contains(mime)
            ? 'application/javascript'
            : mime;
        if (!localHtmlResourceMimes.contains(normalized)) {
          throw const FormatException('Unsupported HTML attachment type');
        }
        final snapshot = await DriveSourceSnapshot.prepare(
          file,
          maxBytes: 5 * 1024 * 1024,
        );
        await _owned(await store.database, noteId);
        const folder = 'HTML附件';
        if (await drive.lookup(folder) == null) await drive.mkdir('', folder);
        final target = driveChild(
          folder,
          '${attachmentId()}-${attachmentName(file.name)}',
        );
        return (await drive.upload(snapshot, target: target)).node;
      });

  Future<List<DriveNode>> available({String keyword = '', int page = 1}) =>
      store.maintenance.use(() async {
        if (page < 1 || page > 1000 || keyword.length > 200) {
          throw const FormatException('Invalid HTML resource query');
        }
        final db = await store.database;
        final rows = await db.query(
          'local_drive_nodes',
          where: 'directory=0 AND instr(lower(path),lower(?))>0',
          whereArgs: [keyword],
          orderBy: 'path',
          limit: 50,
          offset: (page - 1) * 50,
        );
        return rows.map(_node).toList();
      });

  String _mime(DriveNode node) {
    final mime = node.mime.split(';').first.trim().toLowerCase();
    final normalized =
        {'text/javascript', 'application/x-javascript'}.contains(mime)
        ? 'application/javascript'
        : mime;
    if (!localHtmlResourceMimes.contains(normalized)) {
      throw HtmlResourceUnavailable(node.name);
    }
    return normalized;
  }

  bool supports(DriveNode node) {
    if (node.directory || node.size > 5 * 1024 * 1024) return false;
    try {
      _mime(node);
      return true;
    } on HtmlResourceUnavailable {
      return false;
    }
  }

  Future<LocalHtmlPreviewResource> _bytes(
    String path,
    DriveNode node,
    String hash,
  ) => store.maintenance.use(() async {
    if (node.directory ||
        node.size > 5 * 1024 * 1024 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw HtmlResourceUnavailable(path);
    }
    final bytes = await drive.bytes(node, maxBytes: 5 * 1024 * 1024);
    if (sha256.convert(bytes).toString() != hash) {
      throw HtmlResourceUnavailable(path);
    }
    return LocalHtmlPreviewResource(
      path: path,
      mime: _mime(node),
      bytes: bytes,
    );
  });

  Future<LocalHtmlPreviewDocument> load(int noteId, String source) =>
      store.maintenance.use(() async {
        final bindings = await list(noteId);
        if (bindings.length > 32) {
          throw const FormatException('Too many HTML resources');
        }
        final resources = <LocalHtmlPreviewResource>[];
        var total = 0;
        for (final value in bindings) {
          final node = value.node;
          if (node == null || value.changed) {
            throw HtmlResourceUnavailable(value.binding.path);
          }
          final resource = await _bytes(
            value.binding.path,
            node,
            value.binding.hash,
          );
          total += resource.bytes.length;
          if (total > 20 * 1024 * 1024) {
            throw const FormatException('HTML resource total exceeds bound');
          }
          resources.add(resource);
        }
        final db = await store.database;
        await _owned(db, noteId);
        if (!_same(
          bindings.map((r) => r.binding).toList(),
          await _bindings(db, noteId),
        )) {
          throw const HtmlResourceConflict();
        }
        // Detect a replacement after reading the immutable selected bytes.
        for (final value in bindings) {
          final rows = await db.query(
            'local_drive_nodes',
            columns: ['file_hash'],
            where: 'node_id=?',
            whereArgs: [value.binding.nodeId],
          );
          if (rows.length != 1 ||
              rows.single['file_hash'] != value.binding.hash) {
            throw HtmlResourceUnavailable(value.binding.path);
          }
        }
        return LocalHtmlPreviewDocument(source, resources);
      });

  Future<List<HtmlResourceBinding>> replace(
    int noteId,
    List<HtmlResourceChoice> choices, {
    required List<HtmlResourceBinding> baseline,
  }) => store.maintenance.use(() async {
    choices = List<HtmlResourceChoice>.unmodifiable(choices);
    baseline = List<HtmlResourceBinding>.unmodifiable(baseline);
    final paths = <String>{};
    var total = 0;
    if (choices.length > 32) {
      throw const FormatException('Too many HTML resources');
    }
    for (final choice in choices) {
      if (!validLocalHtmlResourcePath(choice.path) ||
          choice.path == 'index.html' ||
          !paths.add(choice.path)) {
        throw const FormatException('Invalid or duplicate HTML resource path');
      }
      total += choice.node.size;
      if (total > 20 * 1024 * 1024) {
        throw const FormatException('HTML resource total exceeds bound');
      }
      await _bytes(choice.path, choice.node, choice.node.etag);
    }
    final db = await store.database;
    return db.transaction((tx) async {
      await _owned(tx, noteId);
      if (!_same(baseline, await _bindings(tx, noteId))) {
        throw const HtmlResourceConflict();
      }
      for (final choice in choices) {
        final rows = await tx.query(
          'local_drive_nodes',
          where: 'node_id=? AND directory=0',
          whereArgs: [choice.node.id],
        );
        if (rows.length != 1 ||
            rows.single['file_hash'] != choice.node.etag ||
            rows.single['path'] != choice.node.path ||
            rows.single['file_size'] != choice.node.size) {
          throw const HtmlResourceConflict();
        }
      }
      await tx.delete(
        'html_preview_resources',
        where: 'note_id=?',
        whereArgs: [noteId],
      );
      final bindings = <HtmlResourceBinding>[];
      for (final choice in choices) {
        final binding = HtmlResourceBinding(
          path: choice.path,
          nodeId: choice.node.id,
          hash: choice.node.etag,
        );
        await tx.insert('html_preview_resources', {
          'note_id': noteId,
          'resource_path': binding.path,
          'node_id': binding.nodeId,
          'approved_hash': binding.hash,
        });
        bindings.add(binding);
      }
      return bindings;
    });
  });
}
