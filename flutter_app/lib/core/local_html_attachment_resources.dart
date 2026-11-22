import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as paths;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'local_attachments.dart';
import 'local_markdown_resources.dart';

/// A frozen, source-bound raster. This does not authorize file navigation.
class LocalHtmlAttachmentRaster {
  LocalHtmlAttachmentRaster({
    required this.uri,
    required this.mime,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uri uri;
  final String mime;
  final Uint8List bytes;
  late final String sha256Hex = sha256.convert(bytes).toString();
}

/// Explicit link handoff bytes, never a render-resource response.
class LocalHtmlAttachmentFile {
  LocalHtmlAttachmentFile(this.uri, Uint8List value)
    : bytes = Uint8List.fromList(value).asUnmodifiableView();
  final Uri uri;
  String get name => uri.pathSegments.last;
  final Uint8List bytes;
  late final String sha256Hex = sha256.convert(bytes).toString();
}

/// Ordinary local-space attachments only; no account or generation15 fallback.
/// The saved HTML is never rewritten by this resource reader.
class LocalHtmlAttachmentResources {
  LocalHtmlAttachmentResources({
    required LocalAttachments attachments,
    required String source,
    required this.scopeIdentity,
    required this.isCurrentScope,
  }) : _attachments = attachments,
       _source = source,
       _reader = LocalMarkdownResources(attachments),
       sourceDigest = sha256.convert(utf8.encode(source)).toString(),
       _references = _imageReferences(source) {
    if (scopeIdentity.isEmpty) throw ArgumentError('Missing local scope');
  }

  final String scopeIdentity, sourceDigest;
  final LocalAttachments _attachments;
  final String _source;
  late final Set<String> _fileReferences = _referencesIn(_source, "a", "href");
  Set<String> get fileReferences => Set.unmodifiable(_fileReferences);
  final bool Function() isCurrentScope;
  final LocalMarkdownResources _reader;
  final Set<String> _references;
  final Set<Future<void>> _pending = {};
  bool _retired = false;
  Future<void>? _retirement;
  bool get current => !_retired && isCurrentScope();
  Set<String> get references => Set.unmodifiable(_references);

  static Set<String> _imageReferences(String source) =>
      _referencesIn(source, "img", "src");

  static Set<String> _referencesIn(String source, String tag, String attribute) {
    if (utf8.encode(source).length > 5 * 1024 * 1024) {
      throw const FormatException('Local HTML source exceeds preview limit');
    }
    // Bound parser object growth before allocating a DOM. Plain text remains
    // subject to the source byte bound; comments/script strings grant nothing.
    var markup = 0;
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 60 && ++markup > 32768) {
        throw const FormatException('Local HTML markup exceeds preview limit');
      }
    }
    final document = html.parse(source);
    final result = <String>{};
    for (final image in document.querySelectorAll('$tag[$attribute]')) {
      final raw = image.attributes[attribute]!;
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme != 'bookstark-attachment') continue;
      LocalMarkdownResources.identity(uri);
      result.add(uri.toString());
      if (result.length > LocalMarkdownResources.maxImages) {
        throw const FormatException('Local HTML attachment count exceeds limit');
      }
    }
    return Set.unmodifiable(result);
  }

  void _guard() {
    if (!current) throw StateError('Local HTML attachment scope retired');
  }

  Future<LocalHtmlAttachmentRaster?> read(Uri uri) {
    _guard();
    // Validate before consulting LocalAttachments, whose general read API also
    // supports public HTTP. No network URI can reach it through this reader.
    if (uri.scheme != 'bookstark-attachment') {
      return Future<LocalHtmlAttachmentRaster?>.value(null);
    }
    LocalMarkdownResources.identity(uri);
    if (!_references.contains(uri.toString())) {
      return Future<LocalHtmlAttachmentRaster?>.value(null);
    }
    final operation = () async {
      final image = await _reader.read(uri);
      _guard();
      return LocalHtmlAttachmentRaster(
        uri: uri, mime: image.mime, bytes: image.bytes,
      );
    }();
    // Track the actual IO future, not a page/picker lifetime. Error consumption
    // here prevents drain bookkeeping from introducing a second unhandled error.
    late final Future<void> tracked;
    tracked = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() { _pending.remove(tracked); });
    _pending.add(tracked);
    return operation;
  }

  /// Called only after the Flutter user-gesture/confirmation path. Merely
  /// loading HTML or asking for an image never reaches these file bytes.
  Future<LocalHtmlAttachmentFile> readReferencedFile(Uri uri) {
    _guard();
    LocalMarkdownResources.identity(uri);
    if (!_fileReferences.contains(uri.toString())) {
      throw StateError('File is not linked by the current local HTML');
    }
    final operation = _attachments.maintenance.use(() async {
      _guard();
      var directory = paths.normalize(_attachments.directory.absolute.path);
      while (true) {
        if (await FileSystemEntity.type(directory, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FormatException('Local attachment directory link rejected');
        }
        _guard();
        final parent = paths.dirname(directory);
        if (parent == directory) break;
        directory = parent;
      }
      final id = LocalMarkdownResources.identity(uri);
      final file = File(paths.join(_attachments.directory.path, id));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Local attachment unavailable');
      }
      _guard();
      final bytes = await _attachments.read(uri, maxBytes: 20 * 1024 * 1024);
      _guard();
      return LocalHtmlAttachmentFile(uri, bytes);
    });
    late final Future<void> tracked;
    tracked = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() { _pending.remove(tracked); });
    _pending.add(tracked);
    return operation;
  }

  Future<void> retireAndDrain() {
    final existing = _retirement;
    if (existing != null) return existing;
    _retired = true;
    _reader.close();
    return _retirement = Future.wait<void>(List.of(_pending)).then((_) {});
  }
}
