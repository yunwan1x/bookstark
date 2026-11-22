import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'image_dimensions.dart';
import 'local_markdown_resources.dart';

/// Exact actual slide image/background paths only. Notes and unknown fields
/// never grant resource authority; parsing preserves the full original source.
final class LocalPresentationImageReference {
  LocalPresentationImageReference._({
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

final class LocalPresentationImageReferences {
  LocalPresentationImageReferences._(
    this.sourceDigest,
    this.files,
    this.unavailableFileIds,
    this.discoveryFailed,
  );
  final String sourceDigest;
  final Map<String, LocalPresentationImageReference> files;
  final Set<String> unavailableFileIds;
  final bool discoveryFailed;
  Map<String, LocalPresentationImageReference> get references =>
      Map.unmodifiable({
        for (final item in files.values) item.sourceValue: item,
      });
  Set<String> get unavailableSourceKeys => unavailableFileIds;
  bool get complete => !discoveryFailed && unavailableFileIds.isEmpty;
  Set<Uri> get attachmentUris => Set<Uri>.unmodifiable(
    files.values.map((v) => v.attachment).whereType<Uri>(),
  );

  factory LocalPresentationImageReferences.unavailable(
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.presentation) {
      throw const FormatException('Actual presentation source required');
    }
    return LocalPresentationImageReferences._(
      document.digest,
      const <String, LocalPresentationImageReference>{},
      const <String>{},
      true,
    );
  }

  factory LocalPresentationImageReferences.capture(
    ComplexEditorDocument document,
  ) {
    if (document.kind != ComplexEditorKind.presentation) {
      throw const FormatException('Actual presentation source required');
    }
    // Parsing view only: original BOM/full bytes and digest never change.
    final source = document.source.startsWith('\uFEFF')
        ? document.source.substring(1)
        : document.source;
    final root = jsonDecode(source);
    if (root is! Map || root['slides'] is! List) {
      throw const FormatException('Actual presentation slides required');
    }
    final slides = root['slides'] as List;
    if (slides.length > 5000) {
      throw const FormatException('Presentation slide count bound');
    }
    final rawFiles = <String, Object?>{};
    var elementsSeen = 0;
    for (var si = 0; si < slides.length; si++) {
      final slide = slides[si];
      if (slide is! Map || slide['elements'] is! List) {
        throw const FormatException(
          'Actual presentation slide elements required',
        );
      }
      final elements = slide['elements'] as List;
      elementsSeen += elements.length;
      if (elementsSeen > 50000) {
        throw const FormatException('Presentation element bound');
      }
      for (var ei = 0; ei < elements.length; ei++) {
        final element = elements[ei];
        if (element is Map && element['type'] == 'image') {
          rawFiles['slides/$si/elements/$ei/src'] = element['src'];
        }
      }
      final background = slide['background'];
      if (background is Map && background['type'] == 'image') {
        final image = background['image'];
        rawFiles['slides/$si/background/image/src'] = image is Map
            ? image['src']
            : null;
      }
    }
    final ids = rawFiles.keys;
    final distinctSources = rawFiles.values.whereType<String>().toSet();
    if (distinctSources.length > 32) {
      throw const FormatException('Presentation image count bound');
    }
    var inlineTotal = 0;
    final knownSources = <String, LocalPresentationImageReference>{};
    final files = <String, LocalPresentationImageReference>{};
    final unavailable = <String>{};
    for (final id in ids) {
      final raw = rawFiles[id];
      if (raw is! String || raw.isEmpty) {
        unavailable.add(id);
        continue;
      }
      final known = knownSources[raw];
      if (known != null) {
        files[id] = LocalPresentationImageReference._(
          fileId: id,
          sourceValue: raw,
          resourceId: known.resourceId,
          attachment: known.attachment,
          inlineBytes: known.inlineBytes,
          inlineMime: known.inlineMime,
        );
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
            throw const FormatException(
              'Presentation inline raster byte bound',
            );
          }
          final actualMime = _mime(inline);
          if (actualMime == null || actualMime != match.group(1)) {
            throw const FormatException(
              'Presentation inline raster MIME mismatch',
            );
          }
          final dimensions = encodedImageDimensions(inline);
          if (dimensions.$1 < 1 ||
              dimensions.$2 < 1 ||
              dimensions.$1 > 16384 ||
              dimensions.$2 > 16384 ||
              dimensions.$1 * dimensions.$2 > 32 * 1024 * 1024) {
            throw const FormatException(
              'Presentation inline raster pixel bound',
            );
          }
          inlineTotal += inline.length;
          if (inlineTotal > 20 * 1024 * 1024) {
            throw const FormatException(
              'Presentation inline raster scope bound',
            );
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
                'ordinary-local-presentation-raster-v1',
                document.digest,
                sha256.convert(utf8.encode(raw)).toString(),
              ]),
            ),
          )
          .toString();
      files[id] = LocalPresentationImageReference._(
        fileId: id,
        sourceValue: raw,
        resourceId: resourceId,
        attachment: attachment,
        inlineBytes: inline?.asUnmodifiableView(),
        inlineMime: mime,
      );
      knownSources[raw] = files[id]!;
    }
    return LocalPresentationImageReferences._(
      document.digest,
      Map<String, LocalPresentationImageReference>.unmodifiable(files),
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
