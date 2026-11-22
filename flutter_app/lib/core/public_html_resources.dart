import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class PublicHtmlResource {
  PublicHtmlResource(Uint8List value, this.mime)
    : bytes = value.asUnmodifiableView();
  final Uint8List bytes;
  final String mime;
}

/// A public renderer never receives the account client or its cookie jar.
/// Only owned-server static/upload resources are fetched; API access is denied.
class PublicHtmlResources {
  PublicHtmlResources(
    Uri server, {
    http.Client? transport,
    this.timeout = const Duration(seconds: 12),
  }) : server = BookstarkClient.normalizeServer(server.toString()),
       _transport = transport ?? http.Client() {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Positive resource timeout required');
    }
  }
  final Uri server;
  final http.Client _transport;
  final Duration timeout;
  static const maxResourceBytes = 5 * 1024 * 1024;
  static const maxTotalBytes = 20 * 1024 * 1024;
  static const maxResources = 32;
  final _abort = Completer<void>();
  final _cache = <Uri, Future<PublicHtmlResource>>{};
  Future<void>? _tail;
  bool _closed = false;
  int _bytes = 0, loaded = 0, failed = 0;
  void Function()? onChanged;
  static const _mimes = {
    'text/css',
    'application/javascript',
    'text/javascript',
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/svg+xml',
    'image/x-icon',
    'image/vnd.microsoft.icon',
    'font/woff',
    'font/woff2',
    'font/ttf',
    'font/otf',
    'application/font-woff',
    'application/vnd.ms-fontobject',
  };
  Uri? _canonical(Uri target) {
    if (!{'http', 'https'}.contains(target.scheme) ||
        target.host.isEmpty ||
        !target.hasAuthority ||
        target.origin != server.origin ||
        target.userInfo.isNotEmpty ||
        target.hasFragment) {
      return null;
    }
    final parts = target.pathSegments, prefix = server.pathSegments;
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(part),
    )) {
      return null;
    }
    bool publicPath(List<String> path) =>
        path.length >= 2 && {'static', 'upload-files'}.contains(path.first);
    final prefixed =
        parts.length >= prefix.length &&
        List.generate(
          prefix.length,
          (index) => parts[index] == prefix[index],
        ).every((same) => same);
    var scoped = prefixed ? parts.sublist(prefix.length) : parts;
    var canonical = target;
    if (!prefixed || !publicPath(scoped)) {
      // Go emits root-relative upload/static URLs. Keep them inside the chosen
      // BookStark mount rather than requesting another service at the host root.
      if (prefix.isEmpty || !publicPath(parts)) return null;
      scoped = parts;
      canonical = target.replace(pathSegments: [...prefix, ...parts]);
    }
    if (!publicPath(scoped)) return null;
    if (target.hasQuery) {
      final query = target.queryParametersAll;
      if (scoped.first != 'static' ||
          query.length != 1 ||
          query['v']?.length != 1 ||
          !RegExp(r'^[a-zA-Z0-9._-]{1,128}$').hasMatch(query['v']!.single)) {
        return null;
      }
    }
    return canonical;
  }

  bool allows(Uri target) => _canonical(target) != null;

  Future<PublicHtmlResource> read(Uri target) {
    if (_closed) return Future.error(StateError('Public preview ended'));
    final canonical = _canonical(target);
    if (canonical == null) {
      failed++;
      onChanged?.call();
      return Future.error(
        const FormatException('Public HTML resource outside approved scope'),
      );
    }
    target = canonical;
    final previous = _cache[target];
    if (previous != null) return previous;
    if (_cache.length >= maxResources) {
      failed++;
      onChanged?.call();
      return Future.error(
        const FormatException('Public HTML resource count exceeded'),
      );
    }
    // Serialize fetches so concurrent images cannot allocate beyond the total.
    final waiting = Stopwatch()..start();
    final pending = _tail;
    final result = pending == null
        ? Future<PublicHtmlResource>.sync(() => _load(target, waiting))
        : pending.then((_) => _load(target, waiting));
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    tail.then((_) {
      if (identical(_tail, tail)) _tail = null;
    });
    _cache[target] = result;
    return result;
  }

  Future<PublicHtmlResource> _load(Uri target, Stopwatch waiting) async {
    if (_closed) throw StateError('Public preview ended');
    final cancel = Completer<void>();
    final stopped = Future.any<void>([_abort.future, cancel.future]);
    try {
      final remaining = maxTotalBytes - _bytes;
      if (remaining <= 0) {
        throw const FormatException('Public HTML resource total exceeded');
      }
      Future<PublicHtmlResource> fetch() async {
        final request =
            http.AbortableRequest('GET', target, abortTrigger: stopped)
              ..followRedirects = false
              ..headers.addAll({
                'accept': 'text/css, application/javascript, image/*, font/*',
                'cache-control': 'no-store',
              });
        final response = await _transport.send(request);
        final media = (response.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase();
        if (response.statusCode != 200 || !_mimes.contains(media)) {
          await response.stream.listen((_) {}).cancel();
          throw const FormatException('Public HTML resource response refused');
        }
        final bytes = await readBoundedResponse(
          response,
          maxBytes: remaining < maxResourceBytes ? remaining : maxResourceBytes,
        );
        if (_closed || cancel.isCompleted) {
          throw StateError('Public preview ended');
        }
        _bytes += bytes.length;
        loaded++;
        onChanged?.call();
        return PublicHtmlResource(
          bytes,
          media == 'text/javascript' ? 'application/javascript' : media,
        );
      }

      final duration = timeout - waiting.elapsed;
      if (duration <= Duration.zero) {
        throw TimeoutException('Public resource deadline');
      }
      return await fetch().timeout(duration);
    } catch (_) {
      if (!_closed) {
        failed++;
        onChanged?.call();
      }
      rethrow;
    } finally {
      if (!cancel.isCompleted) cancel.complete();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    onChanged = null;
    _abort.complete();
    _cache.clear();
    _transport.close();
  }
}
