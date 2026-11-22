part of 'local_legacy_upload_alias_index.dart';

/// Passive data only; never authorizes document navigation or script execution.
final class LegacyRasterResource {
  const LegacyRasterResource._(this.bytes, this.mime, this.sha256Hex);
  final Uint8List bytes;
  final String mime, sha256Hex;
}

final class _RasterDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest input) {
    value = input;
  }

  @override
  void close() {}
}

final class _RasterRetired implements Exception {
  const _RasterRetired();
}

extension LegacyUploadRasterBytes on LegacyUploadAliasIndex {
  Future<LegacyRasterResource?> readRaster(
    String rawUrl, {
    required GenerationContentHandle content,
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    if (maxBytes < 0 || maxBytes > 20 * 1024 * 1024) {
      throw ArgumentError('Expected a bounded raster size');
    }
    bool current() =>
        _live() &&
        content.isCurrent &&
        content.metadata.generationId == _generation.generationId;
    if (!current()) {
      return null;
    }
    final ref = await lookup(rawUrl, maxBytes: maxBytes);
    if (ref == null || !ref.isCurrent || !current()) {
      return null;
    }
    final chunks = BytesBuilder(copy: false);
    Uint8List? result;
    try {
      void check() {
        if (!current() || !ref.isCurrent) {
          throw const _RasterRetired();
        }
      }

      check();
      final support = await _generation.privateSupport.resolveSymbolicLinks();
      check();
      final expected = paths.join(
        support,
        'local-data-v1',
        'generations',
        _generation.generationId!,
      );
      final root = Directory(
        paths.dirname(paths.dirname(_generation.databasePath)),
      );
      final attachments = _generation.attachments;
      if (await root.resolveSymbolicLinks() != expected ||
          await FileSystemEntity.type(attachments.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await attachments.resolveSymbolicLinks() !=
              paths.join(expected, 'attachments')) {
        return null;
      }
      check();
      final file = File(paths.join(attachments.path, ref.attachmentId));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != ref.bytes) {
        return null;
      }
      check();
      var count = 0;
      final collected = _RasterDigest();
      // Digest a single bounded stream while retaining only its accepted bytes.
      final hash = sha256.startChunkedConversion(collected);
      await for (final part in file.openRead()) {
        check();
        count += part.length;
        if (count > ref.bytes || count > maxBytes) {
          return null;
        }
        hash.add(part);
        chunks.add(part);
      }
      hash.close();
      check();
      if (count != ref.bytes ||
          collected.value?.toString() != ref.sha256Hex ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != ref.bytes) {
        return null;
      }
      check();
      result = chunks.takeBytes();
      final mime = lookupMimeType('', headerBytes: result);
      if (!{
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      }.contains(mime)) {
        return null;
      }
      check();
      final accepted = LegacyRasterResource._(
        result.asUnmodifiableView(),
        mime!,
        ref.sha256Hex,
      );
      result = null;
      return accepted;
    } catch (_) {
      return null;
    } finally {
      final rejected = result;
      if (rejected != null) {
        rejected.fillRange(0, rejected.length, 0);
      }
      final discarded = chunks.takeBytes();
      discarded.fillRange(0, discarded.length, 0);
    }
  }
}

/// Borrows a content handle; disposing this binding does not close its owner.
final class GenerationHtmlRasterBinding {
  GenerationHtmlRasterBinding({required this.index, required this.content}) {
    if (!(content.metadata.format.name == 'html' ||
            content.metadata.collection == 'article' &&
                content.metadata.format.name == 'markdown') ||
        content.metadata.generationId != index._generation.generationId) {
      throw ArgumentError('Expected HTML in the same generation');
    }
  }
  final LegacyUploadAliasIndex index;
  final GenerationContentHandle content;
  bool _disposed = false;
  bool get isCurrent => !_disposed && index._live() && content.isCurrent;
  String get scopeKey =>
      '${content.metadata.generationId}/${index.sourceSha256}/${content.metadata.id}/${content.metadata.revision}';
  LocalHtmlPreviewDocument get document {
    if (!isCurrent) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    return LocalHtmlPreviewDocument(
      content.metadata.format.name == 'markdown'
          ? markdown.markdownToHtml(
              content.source,
              extensionSet: markdown.ExtensionSet.gitHubFlavored,
            )
          : content.source,
      const [],
      scriptsEnabled: false,
    );
  }

  Future<LocalHtmlRasterResponse?> load(String url) async {
    if (!isCurrent) return null;
    final resource = await index.readRaster(url, content: content);
    if (!isCurrent || resource == null) return null;
    return LocalHtmlRasterResponse(mime: resource.mime, bytes: resource.bytes);
  }

  void dispose() {
    _disposed = true;
  }
}
