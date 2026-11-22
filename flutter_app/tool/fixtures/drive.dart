// Isolated UI fixture. Never imported by lib/main.dart.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_repository.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import '../../test/fixtures/native_pdf.dart';

class DriveFixture extends DriveRepository {
  DriveFixture({this.local = false, bool seed = true}) {
    if (seed) {
      addDirectory('阅读资料');
      addDirectory('插图');
      addFile(
        '阅读清单.md',
        utf8.encode(
          '# 本周阅读清单\n\n- [x] 阅读《深度工作》\n- [ ] 整理重点摘录\n- [ ] 写下一个行动\n\n## 阅读后的问题\n\n这个观点可以如何应用到工作中？',
        ),
        'text/markdown',
      );
      addFile('阅读资料/学习资料.pdf', nativePdfFixture(), 'application/pdf');
      addFile(
        '插图/知识框架.svg',
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 300"><rect width="480" height="300" fill="#eff6ff"/><rect x="40" y="90" width="100" height="80" rx="8" fill="#2563eb"/><rect x="190" y="90" width="100" height="80" rx="8" fill="#60a5fa"/><rect x="340" y="90" width="100" height="80" rx="8" fill="#2563eb"/><path d="M140 130H190M290 130H340" stroke="#0f172a" stroke-width="4"/></svg>',
        ),
        'image/svg+xml',
        isPublic: true,
      );
    }
  }
  @override
  final bool local;
  final nodes = <String, DriveNode>{};
  final data = <String, Uint8List>{};
  int _next = 1;
  int uploads = 0, removals = 0, saves = 0, publishes = 0;
  bool closed = false;
  DriveNode addDirectory(String path) {
    final value = drivePath(path);
    return nodes[value] = DriveNode(
      id: _next++,
      name: driveBasename(value),
      path: value,
      directory: true,
      size: 0,
      etag: '',
      mime: 'inode/directory',
      modified: '2026-11-04 10:20',
    );
  }

  DriveNode addFile(
    String path,
    List<int> bytes,
    String mime, {
    bool isPublic = false,
  }) {
    final value = drivePath(path),
        body = Uint8List.fromList(bytes),
        old = nodes[path];
    data[value] = body;
    return nodes[value] = DriveNode(
      id: old?.id ?? _next++,
      name: driveBasename(value),
      path: value,
      directory: false,
      size: body.length,
      etag: crypto.sha256.convert(body).toString(),
      mime: mime,
      modified: '2026-11-04 10:20',
      isPublic: isPublic,
      publicPath: isPublic
          ? (old?.publicPath.isNotEmpty == true
                ? old!.publicPath
                : 'diagrams/${driveBasename(value)}')
          : '',
    );
  }

  @override
  Future<DriveProfile> profile({AttachmentCancellation? cancellation}) async {
    cancellation?.check();
    final files = nodes.values.where((node) => !node.directory).toList(),
        unique = <String, int>{for (final node in files) node.etag: node.size};
    final logical = files.fold<int>(0, (sum, node) => sum + node.size),
        stored = unique.values.fold<int>(0, (sum, size) => sum + size);
    return DriveProfile(
      usage: DriveUsage(
        files: files.length,
        directories: nodes.length - files.length,
        logicalBytes: logical,
        storedBytes: stored,
        deduplicatedBytes: logical - stored,
        compressionSavedBytes: 0,
        quotaBytes: local ? 0 : 2 * 1024 * 1024 * 1024,
      ),
      fileMaxBytes: 20 * 1024 * 1024,
      publicMaxBytes: 20 * 1024 * 1024,
      publicBase: local
          ? null
          : Uri.parse('https://fixture.invalid/dav-public/reader'),
      endpoint: local ? null : Uri.parse('https://fixture.invalid/dav'),
      account: local ? '' : 'reader',
      local: local,
    );
  }

  @override
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    final parent = drivePath(path);
    if (parent.isNotEmpty && nodes[parent]?.directory != true) {
      throw const ApiFailure(404, 'Directory not found');
    }
    return nodes.values
        .where((node) => driveParent(node.path) == parent)
        .toList();
  }

  @override
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    await verify(file, cancellation: cancellation);
    final bytes = data[file.path]!;
    var start = 0, end = bytes.length, status = 200;
    if (range != null && (ifRange == null || ifRange == '"${file.etag}"')) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match == null) throw const ApiFailure(416, 'Invalid byte range');
      start = int.parse(match[1]!);
      end = match[2]!.isEmpty ? bytes.length : int.parse(match[2]!) + 1;
      if (start >= bytes.length || end <= start) {
        throw const ApiFailure(416, 'Range outside file');
      }
      end = end.clamp(0, bytes.length);
      status = 206;
    }
    return DriveRead(
      stream: Stream.value(Uint8List.sublistView(bytes, start, end)),
      status: status,
      headers: {
        'etag': '"${file.etag}"',
        if (status == 206)
          'content-range': 'bytes $start-${end - 1}/${bytes.length}',
      },
      length: end - start,
    );
  }

  @override
  Future<DriveNode> mkdir(
    String parent,
    String name, {
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    final target = driveChild(parent, name);
    if (nodes.containsKey(target)) throw const ApiFailure(409, 'Target exists');
    return addDirectory(target);
  }

  Future<void> _relocate(
    DriveNode source,
    String target,
    bool copy,
    AttachmentCancellation? cancellation,
  ) async {
    await verify(source, cancellation: cancellation);
    final path = drivePath(target);
    if (path == source.path ||
        path.startsWith('${source.path}/') ||
        nodes.containsKey(path)) {
      throw const ApiFailure(409, 'Target exists or is inside source');
    }
    for (final item
        in nodes.values
            .where(
              (node) =>
                  node.path == source.path ||
                  node.path.startsWith('${source.path}/'),
            )
            .toList()) {
      final next = '$path${item.path.substring(source.path.length)}';
      final replacement = DriveNode(
        id: copy ? _next++ : item.id,
        name: driveBasename(next),
        path: next,
        directory: item.directory,
        size: item.size,
        etag: item.etag,
        mime: item.mime,
        modified: item.modified,
        isPublic: copy ? false : item.isPublic,
        publicPath: copy ? '' : item.publicPath,
      );
      nodes[next] = replacement;
      if (!item.directory) data[next] = data[item.path]!;
      if (!copy) {
        nodes.remove(item.path);
        data.remove(item.path);
      }
    }
  }

  @override
  Future<void> rename(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => _relocate(source, target, false, cancellation);
  @override
  Future<void> copy(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => _relocate(source, target, true, cancellation);
  @override
  Future<void> remove(
    DriveNode source, {
    AttachmentCancellation? cancellation,
  }) async {
    await verify(source, cancellation: cancellation);
    removals++;
    final paths = nodes.keys
        .where(
          (path) => path == source.path || path.startsWith('${source.path}/'),
        )
        .toList();
    for (final path in paths) {
      nodes.remove(path);
      data.remove(path);
    }
  }

  @override
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) async {
    cancellation?.check();
    final path = drivePath(target), old = nodes[path];
    if (old != null &&
        (expected == null ||
            old.id != expected.id ||
            old.etag != expected.etag)) {
      throw DriveConflict(expected, old);
    }
    if (old == null && expected != null) throw DriveConflict(expected, null);
    final bytes = BytesBuilder(copy: false);
    await for (final part in source.verifiedStream(
      cancellation: cancellation,
      onSent: onSent,
    )) {
      bytes.add(part);
    }
    final reused = nodes.values.any((node) => node.etag == source.hash);
    uploads++;
    final node = addFile(path, bytes.takeBytes(), 'application/octet-stream');
    return DriveUploadResult(node, deduplicated: reused);
  }

  @override
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  }) async {
    await verify(document.node, cancellation: cancellation);
    saves++;
    return addFile(
      document.node.path,
      document.encode(content),
      document.node.mime,
      isPublic: document.node.isPublic,
    );
  }

  @override
  Future<Uri> publish(
    DriveNode file,
    String publicPath, {
    AttachmentCancellation? cancellation,
  }) async {
    if (local) throw StateError('Local files have no public service');
    await verify(file, cancellation: cancellation);
    final path = drivePublicPath(publicPath);
    publishes++;
    nodes[file.path] = DriveNode(
      id: file.id,
      name: file.name,
      path: file.path,
      directory: false,
      size: file.size,
      etag: file.etag,
      mime: file.mime,
      modified: file.modified,
      isPublic: true,
      publicPath: path,
    );
    return Uri(
      scheme: 'https',
      host: 'fixture.invalid',
      pathSegments: ['dav-public', 'reader', ...path.split('/')],
    );
  }

  @override
  Future<void> unpublish(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  }) async {
    await verify(file, cancellation: cancellation);
    nodes[file.path] = DriveNode(
      id: file.id,
      name: file.name,
      path: file.path,
      directory: false,
      size: file.size,
      etag: file.etag,
      mime: file.mime,
      modified: file.modified,
    );
  }

  @override
  void dispose() {
    closed = true;
  }
}
