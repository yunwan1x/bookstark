import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'api_client.dart';
import 'attachments.dart';

/// Public Markdown never borrows the signed-in viewer's private DAV transport.
class PublicShareAttachments extends AttachmentRepository {
  PublicShareAttachments(this.server, {super.publicTransport});
  final Uri server;
  @override
  Uri resolve(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority) return server.resolveUri(uri);
    final root = server.path;
    final path = root.isNotEmpty && uri.path.startsWith('$root/')
        ? uri.path
        : '$root/${uri.path.replaceFirst(RegExp(r'^/+'), '')}';
    return server.replace(
      path: path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  bool _allowed(Uri target) {
    if (!{'http', 'https'}.contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      return false;
    }
    if (target.origin != server.origin) return true;
    // Browsers can automatically attach same-origin cookies. Allow only the
    // known static public-upload route, never arbitrary same-origin endpoints.
    final segments = target.pathSegments;
    if (segments.any(
      (part) =>
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(part),
    )) {
      return false;
    }
    return target.path.startsWith('${server.path}/upload-files/') &&
        !target.hasQuery;
  }

  @override
  bool owns(Uri uri) {
    final target = resolve(uri);
    return _allowed(target) && target.origin == server.origin;
  }

  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) =>
      readPublic(uri, maxBytes: maxBytes);
  @override
  Future<Uint8List> readPublic(Uri uri, {required int maxBytes}) async {
    final target = resolve(uri);
    if (!_allowed(target)) {
      throw const ApiFailure(
        403,
        '公开正文不能读取个人附件 / Public content cannot read private attachments',
      );
    }
    return super.readPublic(target, maxBytes: maxBytes);
  }

  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async {
    throw UnsupportedError('Public reading is read-only');
  }
}
