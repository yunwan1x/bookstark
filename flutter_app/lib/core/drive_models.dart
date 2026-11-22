import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// API JSON paths are filesystem names, never decoded as URLs.
String drivePath(String raw) {
  var path = raw;
  if (path.startsWith('/')) path = path.substring(1);
  if (path.isEmpty) return '';
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  if (path.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('无效文件路径 / Invalid file path');
  }
  return path;
}

String driveName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
    throw const FormatException('无效文件名 / Invalid file name');
  }
  return name;
}

String driveChild(String parent, String name) {
  final root = drivePath(parent), child = driveName(name);
  return root.isEmpty ? child : '$root/$child';
}

String drivePublicPath(String raw) {
  final path = drivePath(raw);
  if (path.isEmpty ||
      path
          .split('/')
          .any(
            (part) =>
                part.startsWith('.') || part == 'dav' || part == 'dav-public',
          )) {
    throw const FormatException('无效公开路径 / Invalid public path');
  }
  return path;
}

String driveParent(String path) {
  final parts = drivePath(path).split('/');
  return parts.take(parts.length - 1).join('/');
}

String driveBasename(String path) => drivePath(path).split('/').last;
int _number(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0)) {
    throw const FormatException('Invalid file number');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Invalid file text');
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Invalid file flag');
  return value;
}

class DriveNode {
  const DriveNode({
    required this.id,
    required this.name,
    required this.path,
    required this.directory,
    required this.size,
    required this.etag,
    required this.mime,
    required this.modified,
    this.storedSize,
    this.mode = '',
    this.created = '',
    this.isPublic = false,
    this.publicPath = '',
  });
  final int id, size;
  final int? storedSize;
  final String name, path, etag, mime, modified, mode, created, publicPath;
  final bool directory, isPublic;
  factory DriveNode.fromJson(Map row) {
    final name = driveName(_string(row['name'])),
        path = drivePath(_string(row['path']));
    if (driveBasename(path) != name || !{'dir', 'file'}.contains(row['type'])) {
      throw const FormatException('Invalid file identity');
    }
    return DriveNode(
      id: _number(row['id'], positive: true),
      name: name,
      path: path,
      directory: row['type'] == 'dir',
      size: _number(row['size']),
      storedSize: row['stored_size'] == null
          ? null
          : _number(row['stored_size']),
      etag: _string(row['etag']),
      mime: _string(row['mime_type']),
      modified: _string(row['mod_time']),
      created: _string(row['create_time']),
      mode: _string(row['mode']),
      isPublic: _boolean(row['is_public']),
      publicPath: row['public_path'] == null ? '' : _string(row['public_path']),
    );
  }
}

class DriveUsage {
  const DriveUsage({
    required this.files,
    required this.directories,
    required this.logicalBytes,
    required this.storedBytes,
    required this.deduplicatedBytes,
    required this.compressionSavedBytes,
    required this.quotaBytes,
  });
  final int files,
      directories,
      logicalBytes,
      storedBytes,
      deduplicatedBytes,
      compressionSavedBytes,
      quotaBytes;
  bool get unlimited => quotaBytes == 0;
  double? get fraction =>
      unlimited ? null : (storedBytes / quotaBytes).clamp(0, 1);
  factory DriveUsage.fromJson(Map row) => DriveUsage(
    files: _number(row['file_count']),
    directories: _number(row['directory_count']),
    logicalBytes: _number(row['logical_bytes']),
    storedBytes: _number(row['stored_bytes']),
    deduplicatedBytes: _number(row['deduplicated_bytes']),
    compressionSavedBytes: _number(row['compression_saved_bytes']),
    quotaBytes: _number(row['quota_bytes']),
  );
}

class DriveProfile {
  const DriveProfile({
    required this.usage,
    required this.fileMaxBytes,
    required this.publicMaxBytes,
    required this.publicBase,
    this.endpoint,
    this.account = '',
    this.hasAppPassword = false,
    this.local = false,
  });
  final DriveUsage usage;
  final int fileMaxBytes, publicMaxBytes;
  final Uri? endpoint, publicBase;
  final String account;
  final bool hasAppPassword, local;
  Uri publicUri(String path) {
    final base = publicBase;
    if (base == null) throw StateError('This space has no public file service');
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [
        ...base.pathSegments.where((part) => part.isNotEmpty),
        ...drivePublicPath(path).split('/'),
      ],
    );
  }
}

class DriveText {
  const DriveText({
    required this.node,
    required this.content,
    required this.hasBom,
    required this.hash,
  });
  final DriveNode node;
  final String content, hash;
  final bool hasBom;
  String encodedContent(String text) => '${hasBom ? '\ufeff' : ''}$text';
  Uint8List encode(String text) =>
      Uint8List.fromList(utf8.encode(encodedContent(text)));
  factory DriveText.decode(DriveNode node, Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: false);
    if (content.runes.any(
      (rune) => (rune < 32 && !{9, 10, 13}.contains(rune)) || rune == 127,
    )) {
      throw const FormatException(
        '文件不是可编辑的UTF-8文本 / File is not editable UTF-8 text',
      );
    }
    return DriveText(
      node: node,
      content: content,
      hasBom:
          bytes.length >= 3 &&
          bytes[0] == 239 &&
          bytes[1] == 187 &&
          bytes[2] == 191,
      hash: crypto.sha256.convert(bytes).toString(),
    );
  }
}

class DriveConflict implements Exception {
  const DriveConflict(this.expected, this.actual);
  final DriveNode? expected;
  final DriveNode? actual;
  @override
  String toString() => actual == null
      ? '文件已移动或删除 / File moved or deleted'
      : '文件已更新，请比较后再保存 / File changed; compare before saving';
}

class DriveUploadResult {
  const DriveUploadResult(this.node, {required this.deduplicated});
  final DriveNode node;
  final bool deduplicated;
}

/// A server acknowledgement is distinct from a fully refreshed canonical node.
class DriveWriteReceipt {
  const DriveWriteReceipt({
    required this.id,
    required this.name,
    required this.requestedPath,
    required this.hash,
    required this.size,
    this.directory = false,
  });
  final int id, size;
  final String name, requestedPath, hash;
  final bool directory;
}

class DriveWriteAcknowledged implements Exception {
  const DriveWriteAcknowledged(this.reference, this.cause);
  final DriveWriteReceipt reference;
  final Object cause;
  @override
  String toString() =>
      '服务端已确认写入，当前文件信息待核对 / Server acknowledged the write; current file metadata needs verification';
}
