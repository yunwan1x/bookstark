import 'dart:convert';
import '../../core/go_text.dart';
import 'admin_asset_models.dart';

const adminFileTextLimit = 2 * 1024 * 1024;
const adminFileSafeInteger = 9007199254740991;

String adminFilePath(String value, {bool mutation = false}) {
  if (value.isEmpty ||
      value != trimGoSpace(value) ||
      value.contains('\u0000') ||
      utf8.encode(value).length > 16384 ||
      !adminFileValidUnicode(value) ||
      value.split('/').contains('..')) {
    throw const FormatException('Invalid remote path');
  }
  if (mutation && {'.', '/', './'}.contains(value)) {
    throw const FormatException('Root mutation is not permitted');
  }
  return value;
}

bool adminFileValidUnicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length) return false;
      final next = value.codeUnitAt(i);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

String adminFileName(String value) {
  if (value.isEmpty ||
      value != trimGoSpace(value) ||
      {'.', '..'}.contains(value) ||
      value.contains('/') ||
      value.contains('\\') ||
      utf8.encode(value).length > 255) {
    throw const FormatException('Invalid remote filename');
  }
  return adminFilePath(value, mutation: true);
}

String _adminFileJoined(String directory, String name) {
  final parts = '$directory/$name'
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  return '${directory.startsWith('/') ? '/' : ''}${parts.join('/')}';
}

String adminFileJoin(String directory, String name) {
  adminFilePath(directory);
  adminFileName(name);
  return _adminFileJoined(directory, name);
}

String adminFileParent(String value) {
  adminFilePath(value);
  final clean = _adminFileJoined(value, '');
  if (clean == '/') return '/';
  final index = clean.lastIndexOf('/');
  return index < 0
      ? '.'
      : index == 0
      ? '/'
      : clean.substring(0, index);
}

String adminFileMode(String value) {
  if (!RegExp(r'^[0-7]{3,4}$').hasMatch(value)) {
    throw const FormatException('Invalid remote permissions');
  }
  return value.padLeft(4, '0');
}

enum AdminFileType { file, dir, symlink, other }

final class AdminFileEntry {
  AdminFileEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    required this.mode,
    required this.modified,
  });
  final String name, path, mode;
  final AdminFileType type;
  final int size;
  final AdminAssetTimestamp modified;
  factory AdminFileEntry.parse(Map<String, dynamic> data, String directory) {
    final name = data['name'], path = data['path'], size = data['size'];
    if (name is! String ||
        path is! String ||
        size is! int ||
        size < 0 ||
        size > adminFileSafeInteger ||
        name.isEmpty ||
        {'.', '..'}.contains(name) ||
        name.contains('/') ||
        name.contains('\u0000') ||
        !adminFileValidUnicode(name) ||
        path != _adminFileJoined(directory, name)) {
      throw const FormatException('Invalid remote directory entry');
    }
    final type = switch (data['type']) {
      'file' => AdminFileType.file,
      'dir' => AdminFileType.dir,
      'symlink' => AdminFileType.symlink,
      'other' => AdminFileType.other,
      _ => throw const FormatException('Invalid remote entry type'),
    };
    if (data['mode'] is! String) throw const FormatException('Missing mode');
    return AdminFileEntry(
      name: name,
      path: path,
      type: type,
      size: size,
      mode: adminFileMode(data['mode'] as String),
      modified: AdminAssetTimestamp.parse(data['mod_time']),
    );
  }
  String get fingerprint =>
      jsonEncode([path, name, type.name, size, mode, modified.raw]);
  bool get addressable {
    try {
      adminFilePath(path);
      return true;
    } on FormatException {
      return false;
    }
  }

  bool get normalPermissionsOnly => int.parse(mode, radix: 8) <= 0x1ff;
}

final class AdminFileListing {
  AdminFileListing({
    required this.path,
    required this.items,
    required this.truncated,
    required this.limit,
  });
  final String path;
  final List<AdminFileEntry> items;
  final bool truncated;
  final int limit;
  factory AdminFileListing.parse(String path, Map<String, Object?> data) {
    adminFilePath(path);
    final raw = data['items'],
        limit = data['limit'],
        truncated = data['truncated'];
    if (raw is! List ||
        limit is! int ||
        limit != 1000 ||
        truncated is! bool ||
        raw.length > limit) {
      throw const FormatException('Invalid remote directory response');
    }
    final items = <AdminFileEntry>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid directory row');
      }
      final item = AdminFileEntry.parse(value, path);
      if (!seen.add(item.path)) {
        throw const FormatException('Duplicate remote path');
      }
      items.add(item);
    }
    return AdminFileListing(
      path: path,
      items: List.unmodifiable(items),
      truncated: truncated,
      limit: limit,
    );
  }
  AdminFileEntry? find(String path) {
    for (final item in items) {
      if (item.path == path) return item;
    }
    return null;
  }
}

final class AdminFileText {
  AdminFileText(this.path, this.content) {
    adminFilePath(path);
    if (!adminFileValidUnicode(content) ||
        content.contains('\u0000') ||
        utf8.encode(content).length > adminFileTextLimit) {
      throw const FormatException('Invalid remote text');
    }
  }
  final String path, content;
  factory AdminFileText.parse(String path, Map<String, Object?> data) {
    if (data['path'] != path || data['content'] is! String) {
      throw const FormatException('Remote content target changed');
    }
    return AdminFileText(path, data['content'] as String);
  }
  @override
  String toString() => 'AdminFileText';
}

enum AdminFileAction { save, mkdir, rename, copy, chmod, delete, upload }

final class AdminFileWritePlan {
  AdminFileWritePlan({
    required this.action,
    required this.path,
    this.target,
    this.mode,
    this.content,
    this.baseline,
    this.recursive = false,
  }) {
    adminFilePath(path, mutation: true);
    if (target != null) adminFilePath(target!, mutation: true);
    if (mode != null && (!RegExp(r'^0[0-7]{3}$').hasMatch(mode!))) {
      throw const FormatException('Special permission bits are unsupported');
    }
    if (content != null) AdminFileText(path, content!);
    if (baseline != null && baseline!.path != path) {
      throw const FormatException('Baseline path differs');
    }
    if (recursive &&
        (action != AdminFileAction.delete ||
            baseline?.type != AdminFileType.dir)) {
      throw const FormatException(
        'Recursive deletion requires reviewed directory',
      );
    }
    if ({
          AdminFileAction.save,
          AdminFileAction.chmod,
          AdminFileAction.delete,
          AdminFileAction.rename,
          AdminFileAction.copy,
        }.contains(action) &&
        baseline == null) {
      throw const FormatException('Reviewed target required');
    }
    if (baseline != null &&
        {AdminFileType.symlink, AdminFileType.other}.contains(baseline!.type)) {
      throw const FormatException('Unsupported remote special entry');
    }
    if (action == AdminFileAction.save &&
            (content == null || baseline?.type != AdminFileType.file) ||
        {AdminFileAction.rename, AdminFileAction.copy}.contains(action) &&
            (target == null || target == path) ||
        action == AdminFileAction.chmod && mode == null) {
      throw const FormatException('Invalid remote operation');
    }
  }
  final AdminFileAction action;
  final String path;
  final String? target, mode, content;
  final AdminFileEntry? baseline;
  final bool recursive;
  @override
  String toString() => 'AdminFileWritePlan';
}

final class AdminFileObservation {
  const AdminFileObservation({
    required this.directories,
    this.currentText,
    this.contentUnavailable = false,
    this.absenceProven = false,
  });
  final List<AdminFileListing> directories;
  final AdminFileText? currentText;
  final bool contentUnavailable, absenceProven;
}

// A raw String method-channel reply consumes a leading UTF-8 BOM in Flutter's
// StandardMessageCodec. The native side sends a JSON envelope instead.
String adminFileDecodeEditorSnapshot(String envelope) {
  final value = jsonDecode(envelope);
  if (value is! Map<String, dynamic> ||
      value.length != 1 ||
      value['content'] is! String) {
    throw const FormatException('Invalid editor snapshot envelope');
  }
  return AdminFileText('/owned-source', value['content'] as String).content;
}
