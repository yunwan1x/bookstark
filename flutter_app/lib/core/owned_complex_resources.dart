import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'owned_complex_resource_lease.dart';
import 'raw_document_client.dart';
import 'image_dimensions.dart';

class OwnedComplexResource {
  OwnedComplexResource(Uint8List bytes, this.mime)
    : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final String mime;
}

typedef OwnedComplexImageValidator =
    Future<void> Function(Uint8List bytes, String mime);

/// Today's Go /upload-files is public. This dedicated client sends no account
/// cookies, Authorization, CSRF, Referer or language headers.
class OwnedComplexResources {
  OwnedComplexResources({
    required this.lease,
    required Iterable<Uri> documentReferences,
    this.sourceDigest,
    http.Client? transport,
    this.deadline = const Duration(seconds: 15),
    OwnedComplexImageValidator? validateImage,
  }) : _transport = transport ?? createRawDocumentClient(),
       _ownsTransport = transport == null,
       _validateImage = validateImage ?? _raster {
    if (deadline <= Duration.zero) {
      throw ArgumentError('Positive deadline required');
    }
    for (final reference in documentReferences) {
      try {
        _approved.add(canonical(reference));
      } on FormatException {
        rejectedReferences++;
        continue;
      }
      if (_approved.length > maxCount) {
        throw const FormatException('Too many document resource references');
      }
    }
  }
  final String? sourceDigest;
  String get identity => crypto.sha256
      .convert(utf8.encode(jsonEncode([lease.identity, sourceDigest])))
      .toString();
  final OwnedComplexResourceLease lease;
  final http.Client _transport;
  final bool _ownsTransport;
  final Duration deadline;
  final OwnedComplexImageValidator _validateImage;
  static const maxObject = 5 * 1024 * 1024,
      maxTotal = 20 * 1024 * 1024,
      maxCount = 32;
  final _cache = <Uri, Future<OwnedComplexResource>>{};
  final _approved = <Uri>{};
  final _abort = Completer<void>();
  Future<void>? _tail;
  int rejectedReferences = 0;
  bool _closed = false;
  int _bytes = 0;
  static const _rasterMimes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  };
  static const _staticMimes = {
    'text/css',
    'font/woff',
    'font/woff2',
    'font/ttf',
    'font/otf',
    'application/font-woff',
    'application/vnd.ms-fontobject',
  };
  void _guard() {
    lease.guard();
    if (_closed) throw const OwnedComplexResourceRetired();
  }

  Uri canonical(Uri value) {
    final base = lease.client.baseUri;
    if (value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.hasAuthority && !value.hasScheme) {
      throw const FormatException('Unapproved owned resource');
    }
    bool invalid(String part) =>
        part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.contains('/') ||
        part.contains('\\') ||
        part.contains('%') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(part);
    if (value.pathSegments.any(invalid)) {
      throw const FormatException('Invalid original resource path');
    }
    final target = value.hasScheme ? value : base.resolve(value.toString());
    if (!{'https', 'http'}.contains(target.scheme) ||
        target.origin != base.origin) {
      throw const FormatException('Unapproved owned resource');
    }
    final parts = target.pathSegments, prefix = base.pathSegments;
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\') ||
          part.contains('%') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(part),
    )) {
      throw const FormatException('Invalid owned resource path');
    }
    final hasPrefix =
        parts.length >= prefix.length &&
        List.generate(
          prefix.length,
          (i) => parts[i] == prefix[i],
        ).every((v) => v);
    List<String> scoped = hasPrefix ? parts.sublist(prefix.length) : parts;
    bool allowed(List<String> path) =>
        path.length >= 2 && {'static', 'upload-files'}.contains(path.first);
    if (!allowed(scoped)) {
      if (!allowed(parts)) {
        throw const FormatException('Unapproved owned resource path');
      }
      scoped = parts;
    }
    return base.replace(pathSegments: [...prefix, ...scoped]);
  }

  /// Only the trusted Dart upload controller calls this after a validated
  /// positive server receipt and explicit insert confirmation. JS cannot expand
  /// the document allowlist by asking for arbitrary same-origin URLs.
  void approveConfirmedUpload({required int uploadId, required Uri uri}) {
    _guard();
    if (uploadId <= 0) {
      throw const FormatException('Confirmed upload ID required');
    }
    final reference = canonical(uri);
    final path = reference.pathSegments.sublist(
      lease.client.baseUri.pathSegments.length,
    );
    if (path.first != 'upload-files') {
      throw const FormatException('Confirmed upload route required');
    }
    if (!_approved.contains(reference) && _approved.length >= maxCount) {
      throw const FormatException('Document resource count exceeded');
    }
    _approved.add(reference);
  }

  Future<OwnedComplexResource> read(Uri value) {
    _guard();
    final target = canonical(value);
    if (!_approved.contains(target)) {
      throw const FormatException(
        'Resource is not referenced by this document',
      );
    }
    final cached = _cache[target];
    if (cached != null) return cached;
    if (_cache.length >= maxCount) {
      throw const FormatException('Owned resource count exceeded');
    }
    final clock = Stopwatch()..start(), previous = _tail;
    final result = lease
        .use(() async {
          if (previous != null) await previous;
          _guard();
          final remaining = deadline - clock.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException('Owned resource deadline');
          }
          return _fetch(target, remaining);
        })
        .timeout(
          deadline,
          onTimeout: () =>
              throw TimeoutException('Owned resource queued deadline'),
        );
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    _cache[target] = result;
    return result;
  }

  Future<OwnedComplexResource> _fetch(Uri target, Duration remaining) async {
    _guard();
    final cancel = Completer<void>();
    void stop() {
      if (!cancel.isCompleted) cancel.complete();
    }

    final timer = Timer(remaining, stop);
    final stopped = Future.any<void>([
      cancel.future,
      _abort.future,
      lease.abortTrigger,
    ]);
    Future<T> wait<T>(Future<T> future) => Future.any<T>([
      future,
      stopped.then<T>((_) => throw TimeoutException('Owned resource ended')),
    ]);
    var cleanupOwns = false;
    final request = http.AbortableRequest('GET', target, abortTrigger: stopped)
      ..followRedirects = false;
    request.headers.addAll({
      'accept': 'image/png,image/jpeg,image/gif,image/webp,text/css,font/*',
      'accept-encoding': 'identity',
      'cache-control': 'no-store',
    });
    // Register the complete late-response cleanup before retirement can start.
    // The send completion alone is not a drained body cancellation.
    final pending = lease.use(() async {
      final response = await _transport.send(request);
      if (cancel.isCompleted || _closed || !lease.current) {
        cleanupOwns = true;
        try {
          await response.stream
              .listen((_) {}, onError: (Object _, StackTrace _) {})
              .cancel();
        } catch (_) {}
      }
      return response;
    });
    try {
      final response = await wait(pending);
      try {
        _guard();
        if (cancel.isCompleted || cleanupOwns) {
          throw TimeoutException('Owned resource ended');
        }
      } catch (_) {
        if (!cleanupOwns) {
          cleanupOwns = true;
          try {
            await response.stream
                .listen((_) {}, onError: (Object _, StackTrace _) {})
                .cancel();
          } catch (_) {}
        }
        rethrow;
      }
      final mime = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      final image = _rasterMimes.contains(mime);
      final path = target.pathSegments.sublist(
        lease.client.baseUri.pathSegments.length,
      );
      if (response.statusCode != 200 ||
          response.isRedirect ||
          response.request != null && response.request!.url != target ||
          !{'', 'identity'}.contains(
            (response.headers['content-encoding'] ?? '').toLowerCase(),
          ) ||
          (!image &&
              (path.first != 'static' || !_staticMimes.contains(mime))) ||
          response.contentLength != null &&
              response.contentLength! > maxObject) {
        await response.stream
            .listen((_) {}, onError: (Object _, StackTrace _) {})
            .cancel();
        throw const FormatException('Owned resource response refused');
      }
      final iterator = StreamIterator<List<int>>(response.stream),
          output = BytesBuilder(copy: false);
      try {
        while (await wait(iterator.moveNext())) {
          _guard();
          final part = iterator.current;
          if (output.length + part.length > maxObject ||
              _bytes + output.length + part.length > maxTotal) {
            throw const FormatException('Owned resource byte bound');
          }
          output.add(part);
        }
      } finally {
        await iterator.cancel();
      }
      _guard();
      final bytes = output.takeBytes();
      if (image) {
        if (!_signature(bytes, mime)) {
          throw const FormatException('Image MIME/signature mismatch');
        }
        await wait(_validateImage(bytes, mime));
      }
      _guard();
      if (cancel.isCompleted) throw TimeoutException('Owned resource deadline');
      _bytes += bytes.length;
      return OwnedComplexResource(bytes, mime);
    } finally {
      timer.cancel();
      stop();
    }
  }

  static bool _signature(Uint8List b, String mime) {
    bool at(int offset, List<int> signature) =>
        b.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => b[offset + i] == signature[i],
        ).every((v) => v);
    switch (mime) {
      case 'image/png':
        return at(0, [137, 80, 78, 71, 13, 10, 26, 10]);
      case 'image/jpeg':
        return at(0, [255, 216, 255]);
      case 'image/gif':
        return at(0, [71, 73, 70, 56, 55, 97]) ||
            at(0, [71, 73, 70, 56, 57, 97]);
      case 'image/webp':
        return at(0, [82, 73, 70, 70]) && at(8, [87, 69, 66, 80]);
      default:
        return false;
    }
  }

  static Future<void> _raster(Uint8List bytes, String mime) async {
    // Inspect bounded container metadata before asking any native decoder.
    final (width, height) = encodedImageDimensions(bytes);
    if (width > 8192 || height > 8192 || width * height > 16000000) {
      throw const FormatException('Owned image dimensions exceeded');
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width != width ||
          descriptor.height != height ||
          descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 16 * 1024 * 1024) {
        throw const FormatException('Owned image dimensions exceeded');
      }
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _abort.complete();
    if (_ownsTransport) _transport.close();
    _cache.clear();
  }
}
