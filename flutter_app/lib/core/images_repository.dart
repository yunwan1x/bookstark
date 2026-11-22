import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'attachments.dart';

enum ImageCategory { editor, note, drawing }

const maxImageTransferBytes = 64 * 1024 * 1024;
int _number(Object? value, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0)) {
    throw const FormatException('Invalid image number');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String) throw const FormatException('Invalid image text');
  return value;
}

class ManagedImage {
  const ManagedImage({
    required this.id,
    required this.name,
    required this.uri,
    this.thumbnail,
    this.category = '',
    this.mime = '',
    this.size = 0,
    this.width = 0,
    this.height = 0,
    this.createdOn = '',
  });
  final int id, size, width, height;
  final String name, category, mime, createdOn;
  final Uri uri;
  final Uri? thumbnail;
  bool get knownDimensions => width > 0 && height > 0;
  factory ManagedImage.fromJson(Map row, Uri Function(String) resolve) =>
      ManagedImage(
        id: _number(row['id'], positive: true),
        name: _text(row['file_name']),
        uri: resolve(_text(row['url'])),
        thumbnail: row['thumb_url'] == null || row['thumb_url'] == ''
            ? null
            : resolve(_text(row['thumb_url'])),
        category: _text(row['category']),
        mime: _text(row['mime_type']),
        size: _number(row['file_size']),
        width: _number(row['width']),
        height: _number(row['height']),
        createdOn: _text(row['create_time']),
      );
}

class ImagesQuery {
  const ImagesQuery({this.keyword = '', this.category, this.page = 1});
  final String keyword;
  final ImageCategory? category;
  final int page;
  Map<String, String> parameters() {
    if (page < 1) throw const FormatException('Invalid images page');
    return {
      'keyword': keyword,
      'page': '$page',
      'page_size': '20',
      if (category != null) 'category': category!.name,
    };
  }
}

class ImagesPageResult {
  const ImagesPageResult(
    this.items, {
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalImageBytes,
  });
  final List<ManagedImage> items;
  final int total, page, pageSize, totalImageBytes;
  bool get hasMore => page * pageSize < total;
}

/// Upload replies do not contain category, MIME, owner or creation time.
class UploadedImageReference {
  const UploadedImageReference({
    required this.id,
    required this.name,
    required this.uri,
    this.thumbnail,
    required this.size,
    required this.width,
    required this.height,
  });
  final int id, size, width, height;
  final String name;
  final Uri uri;
  final Uri? thumbnail;
  factory UploadedImageReference.fromJson(
    Map row,
    Uri Function(String) resolve,
  ) => UploadedImageReference(
    id: _number(row['id'], positive: true),
    name: _text(row['file_name']),
    uri: resolve(_text(row['url'])),
    thumbnail: row['thumb_url'] == null || row['thumb_url'] == ''
        ? null
        : resolve(_text(row['thumb_url'])),
    size: _number(row['file_size']),
    width: _number(row['width']),
    height: _number(row['height']),
  );
}

class ImageUploadPayload {
  ImageUploadPayload.fromBytes({
    required String name,
    required Uint8List bytes,
    required this.category,
  }) : name = attachmentName(name),
       bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.isEmpty || bytes.length > maxImageTransferBytes) {
      throw const ApiFailure(
        413,
        '图片为空或超过客户端64MiB读取上限 / Empty image or over the 64 MiB client bound',
      );
    }
  }
  final String name;
  final Uint8List bytes;
  final ImageCategory category;
  late final String hash = crypto.sha256.convert(bytes).toString();
  static Future<ImageUploadPayload> readFile(
    XFile file,
    ImageCategory category, {
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    if (await file.length() > maxImageTransferBytes) {
      throw const ApiFailure(
        413,
        '图片超过客户端读取上限 / Image exceeds the client read bound',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      cancellation?.check();
      if (builder.length + chunk.length > maxImageTransferBytes) {
        throw const ApiFailure(
          413,
          '图片超过客户端读取上限 / Image exceeds the client read bound',
        );
      }
      builder.add(chunk);
    }
    cancellation?.check();
    return ImageUploadPayload.fromBytes(
      name: file.name,
      bytes: builder.takeBytes(),
      category: category,
    );
  }
}

class ImageRemovalResult {
  const ImageRemovalResult({
    required this.recordRemoved,
    this.linkAvailable,
    this.cleanupPending = false,
  });
  final bool recordRemoved;
  // null means current file accessibility could not be verified, not deletion.
  final bool? linkAvailable;
  final bool cleanupPending;
}

abstract class ImagesRepository {
  bool get publicLinks;
  Future<ImagesPageResult> list(ImagesQuery query);
  Future<UploadedImageReference?> byHash(String hash);
  Future<UploadedImageReference> upload(
    ImageUploadPayload payload, {
    AttachmentCancellation? cancellation,
    void Function(int sent, int total)? onSent,
  });
  Future<ImageRemovalResult> remove(ManagedImage item);
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item);
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  });
  Future<List<ManagedImage>> pendingCleanup() async => const [];
  void dispose() {}
  Future<ManagedImage?> findCanonical(ManagedImage item) async {
    var page = 1;
    while (true) {
      final result = await list(ImagesQuery(keyword: item.name, page: page));
      for (final row in result.items) {
        if (row.id == item.id) return row;
      }
      if (!result.hasMore) return null;
      if (result.page != page || result.items.isEmpty) {
        throw const FormatException('Image pagination changed');
      }
      page++;
    }
  }
}

class RemoteImagesRepository extends ImagesRepository {
  RemoteImagesRepository(
    this.client, {
    http.Client? publicTransport,
    this.isCurrentScope,
  }) : _public = publicTransport ?? http.Client(),
       _revision = client.sessionRevision;
  final BookstarkClient client;
  final bool Function()? isCurrentScope;
  final int _revision;
  void _guard() {
    bool current;
    try {
      current = isCurrentScope?.call() ?? true;
    } catch (_) {
      current = false;
    }
    if (_disposed || !current || client.sessionRevision != _revision) {
      throw StateError('Image library retired');
    }
  }

  final http.Client _public;
  final _cache = <Uri, Uint8List>{};
  final _pending = <(Uri, int), Future<Uint8List>>{};
  int _cachedBytes = 0;
  bool _disposed = false;
  @override
  bool get publicLinks => true;
  Uri _resolve(String value) {
    var candidate = value;
    for (var depth = 0; depth < 3; depth++) {
      if (candidate.contains('\\') ||
          RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(candidate) ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(candidate)) {
        throw const FormatException('Invalid image path');
      }
      String decoded;
      try {
        decoded = Uri.decodeComponent(candidate);
      } on FormatException {
        if (depth == 0) rethrow;
        break;
      }
      if (decoded == candidate) break;
      candidate = decoded;
    }
    if (candidate.contains('\\') ||
        RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(candidate)) {
      throw const FormatException('Invalid image path');
    }
    final raw = Uri.parse(value);
    if (raw.hasQuery ||
        raw.hasFragment ||
        raw.userInfo.isNotEmpty ||
        (!raw.hasScheme && raw.hasAuthority)) {
      throw const FormatException('Invalid image reference');
    }
    final prefix = '${client.baseUri.path}/upload-files/';
    final Uri uri;
    if (raw.hasScheme) {
      uri = raw;
    } else if (raw.path.startsWith('/upload-files/')) {
      uri = client.baseUri.replace(path: '${client.baseUri.path}${raw.path}');
    } else {
      uri = client.baseUri.replace(path: raw.path);
    }
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != client.baseUri.origin ||
        !uri.path.startsWith(prefix) ||
        uri.pathSegments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('\\') ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(part),
        )) {
      throw const FormatException(
        'Image reference leaves current upload library',
      );
    }
    return uri;
  }

  @override
  Future<ImagesPageResult> list(ImagesQuery query) async {
    final result = await client.get(
      '/api/uploads?${Uri(queryParameters: query.parameters()).query}',
    );
    final data = result['data'];
    if (data != null && data is! List) {
      throw const FormatException('Invalid images list');
    }
    final rows = (data as List? ?? const [])
        .map((row) => ManagedImage.fromJson(row as Map, _resolve))
        .toList();
    final page = _number(result['page'], positive: true),
        size = _number(result['page_size'], positive: true);
    if (page != query.page ||
        rows.length > size ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      throw const FormatException('Invalid images pagination');
    }
    return ImagesPageResult(
      rows,
      total: _number(result['total']),
      page: page,
      pageSize: size,
      totalImageBytes: _number(result['total_size']),
    );
  }

  @override
  Future<UploadedImageReference?> byHash(String hash) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid image hash');
    }
    try {
      return UploadedImageReference.fromJson(
        await client.get('/api/uploads/by-hash/$hash'),
        _resolve,
      );
    } on ApiFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<UploadedImageReference> upload(
    ImageUploadPayload payload, {
    AttachmentCancellation? cancellation,
    void Function(int sent, int total)? onSent,
  }) async {
    _guard();
    cancellation?.check();
    var sent = 0;
    Stream<List<int>> data() async* {
      for (var start = 0; start < payload.bytes.length; start += 64 * 1024) {
        _guard();
        cancellation?.check();
        final end = (start + 64 * 1024).clamp(0, payload.bytes.length);
        final chunk = payload.bytes.sublist(start, end);
        sent += chunk.length;
        onSent?.call(sent, payload.bytes.length);
        yield chunk;
      }
    }

    final result = await client.upload(
      '/api/uploads',
      name: payload.name,
      data: data(),
      length: payload.bytes.length,
      fields: {'category': payload.category.name},
      abortTrigger: cancellation?.signal,
      beforeSubmit: () {
        _guard();
        cancellation?.check();
      },
    );
    // A response already received is a known confirmation even if cancellation
    // happens in the same event-loop turn. Do not erase its real resource ID.
    return UploadedImageReference.fromJson(result, _resolve);
  }

  Future<bool?> _available(Uri original) async {
    final uri = _resolve(original.toString()).replace(
      queryParameters: {
        '_bookstark_verify': '${DateTime.now().microsecondsSinceEpoch}',
      },
    );
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 15), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      _guard();
      final response = await _public.send(
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['cache-control'] = 'no-cache',
      );
      final status = response.statusCode;
      await response.stream.listen((_) {}).cancel();
      if (status == 404 || status == 410) return false;
      if (status == 200 || status == 206) return true;
      return null;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<ImageRemovalResult> remove(ManagedImage item) async {
    _number(item.id, positive: true);
    _resolve(item.uri.toString());
    try {
      _guard();
      await client.mutate(
        'DELETE',
        '/api/uploads/${item.id}',
        {},
        beforeSubmit: _guard,
      );
    } on ApiFailure catch (error) {
      if (error.status != 404) rethrow;
    }
    _evict(item.uri);
    if (item.thumbnail != null) _evict(item.thumbnail!);
    return ImageRemovalResult(
      recordRemoved: true,
      linkAvailable: await _available(item.uri),
    );
  }

  @override
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item) async {
    final present = await findCanonical(item);
    return ImageRemovalResult(
      recordRemoved: present == null,
      linkAvailable: await _available(item.uri),
    );
  }

  void _evict(Uri uri) {
    final old = _cache.remove(uri);
    if (old != null) _cachedBytes -= old.length;
  }

  Future<Uint8List> _download(Uri uri, int maxBytes) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 30), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      _guard();
      final response = await _public.send(
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false,
      );
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw ApiFailure(response.statusCode, '图片读取失败 / Image download failed');
      }
      return (await readBoundedResponse(
        response,
        maxBytes: maxBytes,
      )).asUnmodifiableView();
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  }) async {
    _guard();
    if (maxBytes < 1 || maxBytes > maxImageTransferBytes) {
      throw const FormatException('Invalid image read bound');
    }
    final target = _resolve(uri.toString());
    if (reload) _evict(target);
    final cached = _cache.remove(target);
    if (cached != null) {
      _cache[target] = cached;
      if (cached.length > maxBytes) {
        throw const ApiFailure(413, '图片超过读取上限 / Image exceeds read bound');
      }
      return cached;
    }
    final key = (target, maxBytes);
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _download(target, maxBytes);
    _pending[key] = future;
    try {
      final result = await future;
      _guard();
      if (!_disposed && result.length <= 24 * 1024 * 1024) {
        _evict(target);
        _cache[target] = result;
        _cachedBytes += result.length;
        while (_cachedBytes > 24 * 1024 * 1024 || _cache.length > 32) {
          _evict(_cache.keys.first);
        }
      }
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    _cachedBytes = 0;
    _public.close();
  }
}
