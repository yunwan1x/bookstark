import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../features/html/html_preview_document.dart';

class LocalHtmlPreviewResource {
  LocalHtmlPreviewResource({
    required this.path,
    required this.mime,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!validLocalHtmlResourcePath(path) ||
        path == 'index.html' ||
        !localHtmlResourceMimes.contains(mime) ||
        bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid local HTML resource');
    }
  }
  final String path, mime;
  final Uint8List bytes;
  Map<String, Object> toNative() => {
    'path': path,
    'mime': mime,
    'bytes': bytes,
  };
}

const localHtmlResourceMimes = {
  'text/html',
  'text/css',
  'text/plain',
  'application/javascript',
  'application/json',
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/svg+xml',
  'font/woff',
  'font/woff2',
  'font/ttf',
  'audio/mpeg',
  'audio/ogg',
  'video/mp4',
};
bool validLocalHtmlResourcePath(String path) =>
    path.isNotEmpty &&
    path.length <= 1024 &&
    !path.startsWith('/') &&
    !path.endsWith('/') &&
    !path.contains('\\') &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) &&
    !path.split('/').any((part) => part.isEmpty || part == '.' || part == '..');

class LocalHtmlPreviewDocument {
  LocalHtmlPreviewDocument(
    String source,
    List<LocalHtmlPreviewResource> resources, {
    this.scriptsEnabled = true,
  }) : source = buildHtmlPreviewDocument(source),
       resources = List.unmodifiable(resources) {
    final paths = <String>{};
    if (resources.length > 32 ||
        resources.any((r) => !paths.add(r.path)) ||
        resources.fold<int>(0, (sum, r) => sum + r.bytes.length) >
            20 * 1024 * 1024) {
      throw const FormatException('Local HTML resources exceed preview bounds');
    }
    // Fragment wrapping is preview-only and must still satisfy the native bound.
    if (utf8.encode(this.source).length > 5 * 1024 * 1024 + 16 * 1024) {
      throw const FormatException('Wrapped HTML exceeds preview bound');
    }
  }
  final String source;
  final bool scriptsEnabled;
  final List<LocalHtmlPreviewResource> resources;
  late final String fingerprint = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            source,
            scriptsEnabled,
            for (final resource in resources)
              [
                resource.path,
                resource.mime,
                sha256.convert(resource.bytes).toString(),
              ],
          ]),
        ),
      )
      .toString();
  Map<String, Object> toNative(String lease, {required bool english}) => {
    'lease': lease,
    'source': source,
    'scriptsEnabled': scriptsEnabled,
    'resources': resources.map((r) => r.toNative()).toList(),
    'english': english,
  };
}

/// A passive callback cannot grant CSS, script, HTML or file navigation.
class LocalHtmlRasterResponse {
  LocalHtmlRasterResponse({required this.mime, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!{
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        }.contains(mime) ||
        bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid passive raster response');
    }
  }
  final String mime;
  final Uint8List bytes;
  Map<String, Object> toNative() => {'mime': mime, 'bytes': bytes};
}
