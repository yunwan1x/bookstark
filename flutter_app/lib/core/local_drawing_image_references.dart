import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'image_dimensions.dart';
import 'local_markdown_resources.dart';

/// One actual Excalidraw file used by a live image element. Arbitrary strings,
/// unused files and unrelated customData never authorize a filesystem read.
final class LocalDrawingImageReference {
  LocalDrawingImageReference._({
    required this.fileId,
    required this.sourceValue,
    required this.resourceId,
    this.attachment,
    this.inlineBytes,
    this.inlineMime,
  });
  final String fileId, sourceValue, resourceId;
  final Uri? attachment;
  final Uint8List? inlineBytes;
  final String? inlineMime;
}

final class LocalDrawingImageReferences {
  LocalDrawingImageReferences._(
    this.sourceDigest,
    this.files,
    this.unavailableFileIds,
    this.discoveryFailed,
  );
  final String sourceDigest;
  final Map<String, LocalDrawingImageReference> files;
  final Set<String> unavailableFileIds;
  final bool discoveryFailed;
  bool get complete => !discoveryFailed && unavailableFileIds.isEmpty;
  Set<Uri> get attachmentUris => Set<Uri>.unmodifiable(
    files.values.map((v) => v.attachment).whereType<Uri>(),
  );

  factory LocalDrawingImageReferences.unavailable(
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.drawing) {
      throw const FormatException('Actual drawing source required');
    }
    return LocalDrawingImageReferences._(
      document.digest,
      const <String, LocalDrawingImageReference>{},
      const <String>{},
      true,
    );
  }

  factory LocalDrawingImageReferences.capture(ComplexEditorDocument document) {
    if (document.kind != ComplexEditorKind.drawing) {
      throw const FormatException('Actual drawing source required');
    }
    // Parsing view only: original BOM/full bytes and digest never change.
    final source = document.source.startsWith('\uFEFF')
        ? document.source.substring(1)
        : document.source;
    final root = jsonDecode(source);
    if (root is! List &&
        (root is! Map ||
            root['elements'] is! List ||
            (root['files'] != null && root['files'] is! Map))) {
      throw const FormatException('Actual drawing elements/files required');
    }
    final elements = root is List ? root : (root as Map)['elements'] as List;
    if (elements.length > 50000) {
      throw const FormatException('Drawing element bound exceeded');
    }
    final rawFiles = root is Map ? root['files'] as Map? ?? const {} : const {};
    final ids = <String>{};
    for (final element in elements) {
      if (element is! Map ||
          element['type'] != 'image' ||
          element['isDeleted'] == true)
        continue;
      final id = element['fileId'];
      if (id is! String || id.isEmpty || id.length > 256) {
        throw const FormatException('Actual drawing image file ID required');
      }
      ComplexEditorDocument.validateText(id);
      ids.add(id);
      if (ids.length > 32) {
        throw const FormatException('Drawing image count bound');
      }
    }
    var inlineTotal = 0;
    final files = <String, LocalDrawingImageReference>{};
    final unavailable = <String>{};
    for (final id in ids) {
      final item = rawFiles[id];
      final raw = item is Map ? item['dataURL'] : null;
      if (raw is! String || raw.isEmpty) {
        unavailable.add(id);
        continue;
      }
      Uri? attachment;
      Uint8List? inline;
      String? mime;
      final uri = Uri.tryParse(raw);
      if (uri?.scheme == 'bookstark-attachment') {
        LocalMarkdownResources.identity(uri!);
        attachment = uri;
      } else {
        final match = RegExp(
          r'^data:(image/(?:png|jpeg|gif|webp));base64,',
        ).firstMatch(raw);
        if (match == null) {
          // No account client, HTTP fallback or blob authority in this mode.
          unavailable.add(id);
          continue;
        }
        final encoded = raw.substring(match.end);
        if (encoded.length > ((5 * 1024 * 1024 + 2) ~/ 3) * 4) {
          unavailable.add(id);
          continue;
        }
        try {
          inline = Uint8List.fromList(base64Decode(encoded));
          if (inline.isEmpty || inline.length > 5 * 1024 * 1024) {
            throw const FormatException('Drawing inline raster byte bound');
          }
          final actualMime = _mime(inline);
          if (actualMime == null || actualMime != match.group(1)) {
            throw const FormatException('Drawing inline raster MIME mismatch');
          }
          final dimensions = encodedImageDimensions(inline);
          if (dimensions.$1 < 1 ||
              dimensions.$2 < 1 ||
              dimensions.$1 > 16384 ||
              dimensions.$2 > 16384 ||
              dimensions.$1 * dimensions.$2 > 32 * 1024 * 1024) {
            throw const FormatException('Drawing inline raster pixel bound');
          }
          inlineTotal += inline.length;
          if (inlineTotal > 20 * 1024 * 1024) {
            throw const FormatException('Drawing inline raster scope bound');
          }
          mime = match.group(1)!;
        } on FormatException {
          unavailable.add(id);
          continue;
        }
      }
      final resourceId = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'ordinary-local-drawing-raster-v1',
                document.digest,
                id,
                sha256.convert(utf8.encode(raw)).toString(),
              ]),
            ),
          )
          .toString();
      files[id] = LocalDrawingImageReference._(
        fileId: id,
        sourceValue: raw,
        resourceId: resourceId,
        attachment: attachment,
        inlineBytes: inline?.asUnmodifiableView(),
        inlineMime: mime,
      );
    }
    return LocalDrawingImageReferences._(
      document.digest,
      Map<String, LocalDrawingImageReference>.unmodifiable(files),
      Set<String>.unmodifiable(unavailable),
      false,
    );
  }
  static String? _mime(Uint8List bytes) {
    bool prefix(List<int> value) =>
        bytes.length >= value.length &&
        List.generate(
          value.length,
          (i) => bytes[i] == value[i],
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
        bytes[11] == 80)
      return 'image/webp';
    return null;
  }
}
