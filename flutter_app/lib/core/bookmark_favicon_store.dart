import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/image_dimensions.dart';
import 'bookmark_favicon_wire_stub.dart'
    if (dart.library.io) 'bookmark_favicon_wire_io.dart'
    as wire;

/// Accept only an explicit stored icon URL. Never takes or derives bookmark.url.
Uri? explicitBookmarkFavicon(String value) {
  if (value.isEmpty ||
      value.length > 4096 ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    return null;
  }
  try {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return null;
    }
    return uri;
  } catch (_) {
    return null;
  }
}

/// Raster only. ICO containers permit ONLY a bounded embedded PNG frame.
/// Unsupported SVG/DIB ICO formats fail closed to the existing link icon.
Uint8List boundedBookmarkRaster(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 256 * 1024) {
    throw const FormatException('Icon bytes');
  }
  var raster = bytes;
  if (bytes.length >= 6 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 1 &&
      bytes[3] == 0) {
    final data = ByteData.sublistView(bytes),
        count = ByteData.sublistView(bytes).getUint16(4, Endian.little);
    if (count < 1 || count > 64 || 6 + 16 * count > bytes.length) {
      throw const FormatException('Icon directory');
    }
    Uint8List? selected;
    for (var i = 0; i < count; i++) {
      final at = 6 + 16 * i,
          length = data.getUint32(at + 8, Endian.little),
          offset = data.getUint32(at + 12, Endian.little);
      if (offset < 6 + 16 * count ||
          length < 24 ||
          offset + length > bytes.length) {
        throw const FormatException('Icon frame');
      }
      final frame = Uint8List.sublistView(bytes, offset, offset + length);
      if (frame[0] == 137 &&
          frame[1] == 80 &&
          frame[2] == 78 &&
          frame[3] == 71) {
        final (w, h) = encodedImageDimensions(frame);
        if (w <= 512 &&
            h <= 512 &&
            (selected == null || frame.length < selected.length)) {
          selected = frame;
        }
      }
    }
    if (selected == null) throw const FormatException('Unsupported icon');
    raster = selected;
  }
  final (w, h) = encodedImageDimensions(raster);
  if (w > 512 || h > 512 || w * h > 262144) {
    throw const FormatException('Icon dimensions');
  }
  return Uint8List.fromList(raster).asUnmodifiableView();
}

class _IconJob {
  _IconJob(this.uri);
  final Uri uri;
  final result = Completer<Uint8List?>();
}

/// Page-owned memory cache. No account client, cookies, disk or global image cache.
class BookmarkFaviconStore {
  BookmarkFaviconStore({http.Client Function()? anonymousTestFactory})
    : _factory = anonymousTestFactory ?? wire.anonymousFaviconClient;
  final http.Client Function() _factory;
  final _cache = <Uri, Uint8List?>{};
  final _pending = <Uri, _IconJob>{};
  final _queue = Queue<_IconJob>();
  final _clients = <http.Client>{};
  final _cancelers = <void Function()>{};
  final _retired = Completer<void>();
  int _active = 0, _bytes = 0;
  bool get retired => _retired.isCompleted;
  static const maxEntries = 32,
      maxCacheBytes = 2 * 1024 * 1024,
      maxConcurrent = 2,
      maxPending = 64;
  Future<Uint8List?> read(String explicitUrl) {
    final uri = explicitBookmarkFavicon(explicitUrl);
    if (retired || uri == null) return Future.value(null);
    if (_cache.containsKey(uri)) {
      final data = _cache.remove(uri);
      _cache[uri] = data;
      return Future.value(data);
    }
    final old = _pending[uri];
    if (old != null) return old.result.future;
    if (_pending.length >= maxPending) return Future.value(null);
    final job = _IconJob(uri);
    _pending[uri] = job;
    _queue.add(job);
    _pump();
    return job.result.future;
  }

  void rejectDecoded(String explicitUrl) {
    final uri = explicitBookmarkFavicon(explicitUrl);
    if (retired || uri == null || !_cache.containsKey(uri)) return;
    _bytes -= _cache.remove(uri)?.length ?? 0;
    _cache[uri] = null;
  }

  void _pump() {
    while (!retired && _active < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_IconJob job) async {
    Uint8List? data;
    try {
      data = await _fetch(job.uri);
    } catch (_) {
      /* Stable fallback, never log URLs. */
    }
    if (!retired) {
      while (_cache.isNotEmpty &&
          (_cache.length >= maxEntries ||
              _bytes + (data?.length ?? 0) > maxCacheBytes)) {
        final first = _cache.keys.first;
        _bytes -= _cache.remove(first)?.length ?? 0;
      }
      _cache[job.uri] = data;
      _bytes += data?.length ?? 0;
    }
    _pending.remove(job.uri);
    if (!job.result.isCompleted) job.result.complete(retired ? null : data);
    _active--;
    _pump();
  }

  Future<Uint8List> _fetch(Uri uri) async {
    final client = _factory();
    _clients.add(client);
    final abort = Completer<void>();
    bool stopped = false;
    void cancel() {
      if (stopped) return;
      stopped = true;
      if (!abort.isCompleted) abort.complete();
      try {
        client.close();
      } catch (_) {
        /* Cancellation must still settle the job. */
      }
    }

    final timer = Timer(const Duration(seconds: 8), cancel);
    _cancelers.add(cancel);
    Future<T> wait<T>(Future<T> work) => Future.any([
      work,
      abort.future.then<T>((_) => throw StateError('Icon cancelled')),
    ]);
    StreamIterator<List<int>>? body;
    try {
      if (retired) throw StateError('Retired');
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({
        'accept':
            'image/png,image/jpeg,image/gif,image/webp,image/bmp,image/x-icon,image/vnd.microsoft.icon',
        'accept-encoding': 'identity',
        'cache-control': 'no-store',
      });
      final response = await wait(client.send(request));
      body = StreamIterator(response.stream);
      final mime = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode != 200 ||
          !{
            'image/png',
            'image/jpeg',
            'image/gif',
            'image/webp',
            'image/bmp',
            'image/x-icon',
            'image/vnd.microsoft.icon',
          }.contains(mime) ||
          !{'', 'identity'}.contains(
            (response.headers['content-encoding'] ?? '').trim().toLowerCase(),
          )) {
        throw const FormatException('Icon response');
      }
      final length = int.tryParse(response.headers['content-length'] ?? '');
      if (length != null && (length < 0 || length > 256 * 1024)) {
        throw const FormatException('Icon length');
      }
      final bytes = BytesBuilder(copy: false);
      var count = 0;
      while (await wait(body.moveNext())) {
        count += body.current.length;
        if (count > 256 * 1024) throw const FormatException('Icon bound');
        bytes.add(body.current);
      }
      if (retired) throw StateError('Retired');
      return boundedBookmarkRaster(bytes.takeBytes());
    } finally {
      // The absolute request budget includes waiting for headers and body, but
      // must never wait for a hostile/blocked stream cancellation acknowledgement.
      timer.cancel();
      cancel();
      final ownedBody = body;
      if (ownedBody != null) {
        unawaited(ownedBody.cancel().catchError((Object _, StackTrace _) {}));
      }
      _cancelers.remove(cancel);
      _clients.remove(client);
    }
  }

  void retire() {
    if (retired) return;
    _retired.complete();
    for (final cancel in _cancelers.toList()) {
      cancel();
    }
    for (final job in _pending.values) {
      if (!job.result.isCompleted) job.result.complete(null);
    }
    _pending.clear();
    _queue.clear();
    _cache.clear();
    _bytes = 0;
  }
}
