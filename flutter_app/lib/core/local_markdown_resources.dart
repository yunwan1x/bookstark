import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'local_attachments.dart';
import 'image_dimensions.dart';

class LocalMarkdownImage {
  const LocalMarkdownImage(this.bytes, this.mime, this.pixels);
  final Uint8List bytes;
  final String mime;
  final int pixels;
}

/// Image-only, lease-owned access to the existing private attachment directory.
/// There is no network fallback and no caller-supplied filesystem path.
class LocalMarkdownResources {
  LocalMarkdownResources(this.attachments);
  final LocalAttachments attachments;
  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxTotalBytes = 20 * 1024 * 1024;
  static const maxImages = 32;
  final _cache = <String, LocalMarkdownImage>{};
  final _requested = <String>{};
  final _failed = <String>{};
  Future<void> _queue = Future<void>.value();
  int _total = 0, _pixels = 0;
  bool _closed = false;
  int get loaded => _cache.length;
  int get failed => _failed.length;
  void Function()? onChanged;

  static String identity(Uri uri) {
    if (uri.scheme != 'bookstark-attachment' ||
        uri.host.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(uri.pathSegments.first)) {
      throw const FormatException('Invalid local image reference');
    }
    final name = uri.pathSegments.last;
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.length > 255 ||
        name.contains('/') ||
        name.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        uri.toString().length > 2048) {
      throw const FormatException('Invalid local image name');
    }
    return uri.pathSegments.first;
  }

  Future<LocalMarkdownImage> read(Uri uri) {
    final done = Completer<LocalMarkdownImage>();
    _queue = _queue.then((_) async {
      try {
        if (_closed) throw StateError('Local image lease ended');
        final id = identity(uri);
        if (_failed.contains(id)) throw StateError('Local image unavailable');
        final cached = _cache[id];
        if (cached != null) {
          done.complete(cached);
          return;
        }
        if (_requested.length >= maxImages && !_requested.contains(id)) {
          throw StateError('Local image count limit');
        }
        _requested.add(id);
        try {
          final image = await attachments.maintenance.use(() async {
            var cursor = p.normalize(attachments.directory.absolute.path);
            while (true) {
              if (await FileSystemEntity.type(cursor, followLinks: false) ==
                  FileSystemEntityType.link) {
                throw const FormatException(
                  'Local image directory link rejected',
                );
              }
              final parent = p.dirname(cursor);
              if (parent == cursor) break;
              cursor = parent;
            }
            final file = File(p.join(attachments.directory.path, id));
            if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file) {
              throw const FormatException('Local image file unavailable');
            }
            final bytes = await attachments.read(uri, maxBytes: maxImageBytes);
            final mime = _imageMime(bytes);
            if (mime == null || bytes.isEmpty) {
              throw const FormatException(
                'Local preview requires a raster image',
              );
            }
            final (width, height) = encodedImageDimensions(bytes);
            if (width > 16384 ||
                height > 16384 ||
                width * height > 32 * 1024 * 1024) {
              throw const FormatException(
                'Local image dimensions exceed limit',
              );
            }
            return LocalMarkdownImage(bytes, mime, width * height);
          });
          if (_closed) throw StateError('Local image lease ended');
          if (_total + image.bytes.length > maxTotalBytes ||
              _pixels + image.pixels > 32 * 1024 * 1024) {
            throw StateError('Local image byte limit');
          }
          _cache[id] = image;
          _total += image.bytes.length;
          _pixels += image.pixels;
          onChanged?.call();
          done.complete(image);
        } catch (_) {
          if (!_closed) {
            _failed.add(id);
            onChanged?.call();
          }
          rethrow;
        }
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  static String? _imageMime(Uint8List bytes) {
    bool prefix(List<int> magic) =>
        bytes.length >= magic.length &&
        List.generate(
          magic.length,
          (i) => bytes[i] == magic[i],
        ).every((v) => v);
    if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (prefix([255, 216, 255])) return 'image/jpeg';
    if (prefix([71, 73, 70, 56, 55, 97]) || prefix([71, 73, 70, 56, 57, 97])) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        prefix([82, 73, 70, 70]) &&
        bytes[8] == 87 &&
        bytes[9] == 69 &&
        bytes[10] == 66 &&
        bytes[11] == 80) {
      return 'image/webp';
    }
    return null;
  }

  void close() {
    _closed = true;
    onChanged = null;
    _cache.clear();
    _requested.clear();
    _failed.clear();
    _total = 0;
    _pixels = 0;
  }
}
