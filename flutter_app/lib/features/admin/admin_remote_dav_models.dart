import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import '../../core/go_text.dart';
import 'admin_asset_models.dart';
import 'admin_files_models.dart';

int _id(Object? value) {
  if (value is! int || value < 1 || value > adminFileSafeInteger) {
    throw const FormatException('Invalid WebDAV identifier');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String ||
      !adminFileValidUnicode(value) ||
      value.contains('\u0000')) {
    throw const FormatException('Invalid WebDAV metadata');
  }
  return value;
}

/// API-relative path, independent of the configured URL prefix and root_path.
/// Refuse any input that Go's TrimSpace/path.Clean would silently retarget.
String adminDavPath(String value, {bool mutation = false}) {
  adminFilePath(value, mutation: mutation);
  if (value == '.') return value;
  if (value.startsWith('/') ||
      value.endsWith('/') ||
      value.split('/').any((part) => part.isEmpty || part == '.')) {
    throw const FormatException('Noncanonical WebDAV path');
  }
  return value;
}

String adminDavJoin(String directory, String name) {
  adminDavPath(directory);
  adminFileName(name);
  return adminDavPath(
    directory == '.' ? name : '$directory/$name',
    mutation: true,
  );
}

String adminDavRoot(String value) {
  if (value == '/') return value;
  adminDavPath(value.startsWith('/') ? value.substring(1) : value);
  if (!value.startsWith('/')) {
    throw const FormatException('WebDAV root must start with slash');
  }
  return value;
}

Uri adminDavUrl(String value) {
  if (value != trimGoSpace(value) ||
      !adminFileValidUnicode(value) ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid WebDAV URL');
  }
  // Uri.parse itself removes dot segments. Inspect the caller's original
  // encoded path first, before parsing can hide a change of target.
  final authority = value.indexOf('://');
  final pathStart = authority < 0 ? -1 : value.indexOf('/', authority + 3);
  if (pathStart >= 0) {
    final rawPath = value.substring(pathStart).split(RegExp(r'[?#]')).first;
    final parts = rawPath.split('/');
    for (var i = 0; i < parts.length; i++) {
      final decoded = Uri.decodeComponent(parts[i]);
      if ({'.', '..'}.contains(decoded) ||
          decoded.contains('/') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(decoded) ||
          decoded.isEmpty && i > 0 && i < parts.length - 1) {
        throw const FormatException('Noncanonical WebDAV URL path');
      }
    }
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'WebDAV URL must not contain credentials, query or fragment',
    );
  }
  // Never silently normalize dot segments or double-encode path input.
  if (uri.pathSegments.any((part) => part == '.' || part == '..')) {
    throw const FormatException('Noncanonical WebDAV URL');
  }
  return uri;
}

sealed class AdminDavConnection {
  String get name;
  factory AdminDavConnection.parse(Map<String, dynamic> data) {
    if (data['id'] == 'local' && data['built_in'] == true) {
      return AdminDavBuiltin(_text(data['name']));
    }
    if (data['built_in'] == true || data['id'] is! int) {
      throw const FormatException('Invalid WebDAV connection type');
    }
    return AdminDavServer.parse(data);
  }
}

final class AdminDavBuiltin implements AdminDavConnection {
  const AdminDavBuiltin(this.name);
  @override
  final String name;
}

final class AdminDavServer implements AdminDavConnection {
  AdminDavServer._({
    required this.id,
    required this.name,
    required this.url,
    required this._urlDigest,
    required this.urlNeedsReplacement,
    required this.root,
    required this.credentialId,
    required this.createdBy,
    required this.status,
    required this.created,
    required this.modified,
    this.credentialName,
    this.username,
    this.checked,
  });
  final int id, credentialId, createdBy;
  @override
  final String name;
  final String url, root;
  final String _urlDigest;
  final bool urlNeedsReplacement;
  final String? credentialName, username;
  final AdminAssetStatus status;
  final AdminAssetTimestamp created, modified;
  final AdminAssetTimestamp? checked;
  factory AdminDavServer.parse(Map<String, dynamic> data) {
    final rawUrl = _text(data['url']), root = _text(data['root_path']);
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null ||
        !{'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty) {
      throw const FormatException('Invalid stored WebDAV URL');
    }
    var url = rawUrl, needsReplacement = false;
    try {
      adminDavUrl(rawUrl);
    } on FormatException {
      needsReplacement = true;
      url = Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: parsed.path,
      ).toString();
    }
    adminDavRoot(root);
    return AdminDavServer._(
      id: _id(data['id']),
      name: _text(data['name']),
      url: url,
      urlDigest: sha256.convert(utf8.encode(rawUrl)).toString(),
      urlNeedsReplacement: needsReplacement,
      root: root,
      credentialId: _id(data['credential_id']),
      createdBy: data['created_by'] == 0 ? 0 : _id(data['created_by']),
      status: AdminAssetStatus.parse(data['status']),
      created: AdminAssetTimestamp.parse(data['create_time']),
      modified: AdminAssetTimestamp.parse(data['modify_time']),
      credentialName: data['credential_name'] == null
          ? null
          : _text(data['credential_name']),
      username: data['username'] == null ? null : _text(data['username']),
      checked: data['last_check_time'] == null
          ? null
          : AdminAssetTimestamp.parse(data['last_check_time']),
    );
  }
  // Testing also changes modify_time; a stale review must be read again.
  String get fingerprint => jsonEncode([
    id,
    name,
    _urlDigest,
    root,
    credentialId,
    createdBy,
    created.raw,
    modified.raw,
  ]);
  @override
  String toString() => 'AdminDavServer#$id';
}

final class AdminDavDraft {
  AdminDavDraft({
    required this.name,
    required this.url,
    required this.root,
    required this.credentialId,
  }) {
    if (name.isEmpty ||
        name != trimGoSpace(name) ||
        !adminFileValidUnicode(name) ||
        name.contains('\u0000') ||
        utf8.encode(name).length > 100) {
      throw const FormatException('Invalid WebDAV connection name');
    }
    adminDavUrl(url);
    adminDavRoot(root);
    _id(credentialId);
  }
  final String name, url, root;
  final int credentialId;
  Map<String, Object> get json => {
    'name': name,
    'url': url,
    'root_path': root,
    'credential_id': credentialId,
  };
}

enum AdminDavEntryType { file, directory }

final class AdminDavEntry {
  AdminDavEntry._({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    required this.modified,
  });
  final String name, path;
  final AdminDavEntryType type;

  /// Go maps a missing DAV length to zero, so zero is not proof of an empty file.
  final int size;
  final AdminAssetTimestamp modified;
  factory AdminDavEntry.parse(Map<String, dynamic> data, String directory) {
    adminDavPath(directory);
    final name = _text(data['name']), path = _text(data['path']);
    final type = switch (data['type']) {
      'file' => AdminDavEntryType.file,
      'dir' => AdminDavEntryType.directory,
      _ => throw const FormatException('Invalid WebDAV entry type'),
    };
    final size = data['size'];
    if (size is! int ||
        size < 0 ||
        size > adminFileSafeInteger ||
        name.isEmpty ||
        {'.', '..'}.contains(name) ||
        name.contains('/') ||
        path != (directory == '.' ? name : '$directory/$name')) {
      throw const FormatException('Invalid WebDAV directory entry');
    }
    // The backend synthesizes this symbolic field; never interpret it as chmod.
    if (data['mode'] !=
        (type == AdminDavEntryType.file ? '-rw-r--r--' : 'drwxr-xr-x')) {
      throw const FormatException('Invalid WebDAV mode metadata');
    }
    return AdminDavEntry._(
      name: name,
      path: path,
      type: type,
      size: size,
      modified: AdminAssetTimestamp.parse(data['mod_time']),
    );
  }
  bool get addressable {
    try {
      adminDavPath(path, mutation: true);
      adminFileName(name);
      return true;
    } on FormatException {
      return false;
    }
  }

  String get fingerprint =>
      jsonEncode([name, path, type.name, size, modified.raw]);
}

final class AdminDavListing {
  AdminDavListing._(this.path, this.items, this.truncated);
  final String path;
  AdminDavEntry? find(String path) {
    for (final item in items) {
      if (item.path == path) return item;
    }
    return null;
  }

  final List<AdminDavEntry> items;
  final bool truncated;
  factory AdminDavListing.parse(Map<String, dynamic> data, String directory) {
    final raw = data['items'],
        limit = data['limit'],
        truncated = data['truncated'];
    if (raw is! List ||
        limit != 1000 ||
        truncated is! bool ||
        raw.length > limit) {
      throw const FormatException('Invalid WebDAV listing');
    }
    final items = <AdminDavEntry>[];
    final paths = <String>{};
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid WebDAV item');
      }
      final entry = AdminDavEntry.parse(item, directory);
      if (!paths.add(entry.path)) {
        throw const FormatException('Duplicate WebDAV target');
      }
      items.add(entry);
    }
    return AdminDavListing._(directory, List.unmodifiable(items), truncated);
  }
}

enum AdminDavFileAction { save, mkdir, rename, copy, delete, upload }

final class AdminDavFilePlan {
  AdminDavFilePlan({
    required this.action,
    required this.path,
    this.baseline,
    this.target,
    this.content,
    this.recursive = false,
  }) {
    adminDavPath(path, mutation: true);
    if (action == AdminDavFileAction.delete &&
        baseline?.type == AdminDavEntryType.directory &&
        !recursive) {
      throw const FormatException(
        'WebDAV directory deletion requires explicit recursive review',
      );
    }
    if (baseline != null && baseline!.path != path) {
      throw const FormatException('DAV baseline target differs');
    }
    if (target != null) adminDavPath(target!, mutation: true);
    if ({AdminDavFileAction.rename, AdminDavFileAction.copy}.contains(action) !=
            (target != null) ||
        target == path) {
      throw const FormatException('Invalid DAV destination');
    }
    if (action == AdminDavFileAction.save) {
      if (baseline?.type != AdminDavEntryType.file || content == null) {
        throw const FormatException('DAV original text required');
      }
      AdminFileText(path, content!);
    } else if (content != null) {
      throw const FormatException('Unexpected DAV text');
    }
    if ({
          AdminDavFileAction.rename,
          AdminDavFileAction.copy,
          AdminDavFileAction.delete,
        }.contains(action) &&
        baseline == null) {
      throw const FormatException('DAV metadata review required');
    }
  }
  final AdminDavFileAction action;
  final String path;
  final AdminDavEntry? baseline;
  final String? target, content;
  final bool recursive;
}

String adminDavParent(String value) {
  adminDavPath(value);
  final index = value.lastIndexOf('/');
  return index < 0 ? '.' : value.substring(0, index);
}

final class AdminDavFileObservation {
  const AdminDavFileObservation({
    required this.directories,
    this.currentText,
    this.contentUnavailable = false,
    this.absenceProven = false,
  });
  final List<AdminDavListing> directories;
  final AdminFileText? currentText;
  final bool contentUnavailable, absenceProven;
}
