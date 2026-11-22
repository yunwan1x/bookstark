import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'attachments.dart';
import 'drive_models.dart';
import 'drive_repository.dart';

/// Read-only Markdown references rooted in the current private file directory.
class DriveAttachments extends AttachmentRepository {
  DriveAttachments(this.repository, {required String directory})
    : directory = drivePath(directory);
  final DriveRepository repository;
  final String directory;
  Uri _base() => Uri(
    scheme: 'bookstark-drive',
    pathSegments: ['', if (directory.isNotEmpty) ...directory.split('/'), ''],
  );
  Uri? _own(Uri uri) {
    if (uri.hasAuthority || uri.hasQuery || uri.userInfo.isNotEmpty) {
      return null;
    }
    if (uri.hasScheme && uri.scheme != 'bookstark-drive') return null;
    if (uri.toString().contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(uri.toString())) {
      throw const FormatException('Invalid file reference');
    }
    final resolved = uri.hasScheme ? uri : _base().resolveUri(uri);
    final path = drivePath(
      resolved.pathSegments.where((segment) => segment.isNotEmpty).join('/'),
    );
    return Uri(
      scheme: 'bookstark-drive',
      pathSegments: ['', ...path.split('/')],
    );
  }

  @override
  Uri resolve(Uri uri) => _own(uri) ?? uri;
  @override
  bool owns(Uri uri) => _own(uri) != null;
  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) async {
    final own = _own(uri);
    if (own == null) return readPublic(uri, maxBytes: maxBytes);
    final path = drivePath(
      own.pathSegments.where((segment) => segment.isNotEmpty).join('/'),
    );
    final file = await repository.lookup(path);
    if (file == null || file.directory) {
      throw const FormatException('附件文件不存在 / Attachment file unavailable');
    }
    return repository.bytes(file, maxBytes: maxBytes);
  }

  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async => throw UnsupportedError(
    'This file preview attachment adapter is read-only',
  );
}
