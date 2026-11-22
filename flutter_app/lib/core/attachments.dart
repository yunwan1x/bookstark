import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'api_client.dart';
import 'attachment_reference_removal.dart';

class AttachmentCancelled implements Exception {
  const AttachmentCancelled();
  @override
  String toString() => '附件操作已取消 / Attachment operation cancelled';
}

class AttachmentCancellation {
  final _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  Future<void> get signal => _cancelled.future;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  void check() {
    if (cancelled) throw const AttachmentCancelled();
  }
}

String attachmentId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String attachmentName(String value) {
  final name = value
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .trim();
  if (name.isEmpty || name == '.' || name == '..') return 'attachment';
  return name.length > 180 ? name.substring(name.length - 180) : name;
}

bool rasterImage(String name) =>
    RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false).hasMatch(name);
String markdownAttachment(String name, Uri uri, {required bool image}) {
  final label = name
      .replaceAll('\\', '\\\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll(RegExp(r'[\r\n]'), ' ');
  return '${image ? '!' : ''}[$label](<${uri.toString().replaceAll('>', '%3E').replaceAll('<', '%3C')}>)';
}

class Attachment {
  const Attachment({
    required this.uri,
    required this.name,
    required this.image,
    this.size,
  });
  final Uri uri;
  final String name;
  final bool image;
  final int? size;
}

abstract class AttachmentRepository {
  AttachmentRepository({http.Client? publicTransport})
    : _public = publicTransport ?? http.Client();
  final http.Client _public;
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  });
  bool owns(Uri uri);
  Uri resolve(Uri uri) => uri;
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024});
  Future<Uint8List> readPublic(Uri uri, {required int maxBytes}) async {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('不支持的附件地址 / Unsupported attachment URL');
    }
    final request = http.Request('GET', uri.replace(fragment: ''))
      ..followRedirects = false;
    final response = await _public.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      throw ApiFailure(response.statusCode, '图片或附件读取失败 / Failed to load media');
    }
    return readBoundedResponse(response, maxBytes: maxBytes);
  }

  void close() => _public.close();
}

class RemoteAttachments extends AttachmentRepository {
  RemoteAttachments(this.client, {super.publicTransport});
  final BookstarkClient client;
  @override
  Uri resolve(Uri uri) {
    if (uri.hasScheme) return uri;
    if (uri.hasAuthority) return client.baseUri.resolveUri(uri);
    final prefix = client.baseUri.path;
    final path = prefix.isNotEmpty && uri.path.startsWith('$prefix/')
        ? uri.path
        : '$prefix/${uri.path.replaceFirst(RegExp(r'^/+'), '')}';
    return client.baseUri.replace(
      path: path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  String? _privatePath(Uri uri) {
    final resolved = resolve(uri);
    if (!['http', 'https'].contains(resolved.scheme) ||
        resolved.origin != client.baseUri.origin ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    final root = '${client.baseUri.path}/api/webdav/files/';
    if (!['${root}download', '${root}preview'].contains(resolved.path)) {
      return null;
    }
    if (!resolved.queryParameters.containsKey('path')) return null;
    return '${resolved.path.substring(client.baseUri.path.length)}?${resolved.query}';
  }

  @override
  bool owns(Uri uri) {
    final resolved = resolve(uri);
    if (!['http', 'https'].contains(resolved.scheme) ||
        resolved.userInfo.isNotEmpty ||
        resolved.origin != client.baseUri.origin) {
      return false;
    }
    return _privatePath(uri) != null ||
        resolved.path.startsWith('${client.baseUri.path}/upload-files/');
  }

  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    final name = attachmentName(file.name);
    final size = await file.length();
    final image = rasterImage(name);
    Uri reference;
    if (image && !protected && !name.toLowerCase().endsWith('.bmp')) {
      final result = await client.upload(
        '/api/uploads',
        name: name,
        data: file.openRead(),
        length: size,
        fields: {'category': 'editor'},
        abortTrigger: cancellation?.signal,
      );
      reference = Uri.parse(result['url'] as String);
      if (!owns(reference) || _privatePath(reference) != null) {
        throw const FormatException('Invalid image upload response');
      }
    } else {
      final ext =
          RegExp(r'(\.[a-zA-Z0-9]{1,12})$').firstMatch(name)?.group(1) ?? '';
      final result = await client.upload(
        '/api/webdav/files/upload',
        name: '${attachmentId()}$ext',
        data: file.openRead(),
        length: size,
        fields: {'path': '/'},
        abortTrigger: cancellation?.signal,
      );
      final node = result['file'] as Map;
      final path = node['path'] as String;
      // DAV node paths are relative to the user's root; older servers may
      // include a leading slash. Never interpret this value as a URL.
      final segments = path.replaceFirst(RegExp(r'^/'), '').split('/');
      if (segments.any((part) => part.isEmpty || part == '.' || part == '..') ||
          path.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
        throw const FormatException('Invalid file upload response');
      }
      reference = Uri(
        path: '/api/webdav/files/download',
        queryParameters: {'path': path},
      );
    }
    cancellation?.check();
    return Attachment(
      uri: resolve(reference),
      name: name,
      image: image,
      size: size,
    );
  }

  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) {
    final privatePath = _privatePath(uri);
    if (privatePath != null) {
      return client.download(privatePath, maxBytes: maxBytes);
    }
    return readPublic(resolve(uri), maxBytes: maxBytes);
  }
}

class _AttachmentVisitor implements md.NodeVisitor {
  _AttachmentVisitor(this.include);
  final bool Function(Uri uri) include;
  final List<Attachment> values = [];
  @override
  bool visitElementBefore(md.Element element) {
    final image = element.tag == 'img';
    final url = image
        ? element.attributes['src']
        : element.tag == 'a'
        ? element.attributes['href']
        : null;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null &&
          (image || include(uri)) &&
          !values.any((item) => item.uri == uri)) {
        values.add(
          Attachment(
            uri: uri,
            name: image
                ? element.attributes['alt'] ?? 'image'
                : element.textContent,
            image: image,
          ),
        );
      }
    }
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {}
  @override
  void visitText(md.Text text) {}
}

List<Attachment> noteAttachments(
  String content,
  bool Function(Uri uri) include,
) {
  final visitor = _AttachmentVisitor(include);
  for (final node in md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(content.split('\n'))) {
    node.accept(visitor);
  }
  return visitor.values;
}

/// Removes parsed uses by URI, retaining reference definitions and real files.
String removeAttachmentReference(String content, Attachment attachment) =>
    removeMarkdownAttachmentUses(content, attachment.uri);
