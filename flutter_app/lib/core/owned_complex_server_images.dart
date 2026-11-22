import 'dart:async';
import 'owned_complex_resource_lease.dart';
import 'owned_complex_resources.dart';

class OwnedComplexServerImage {
  const OwnedComplexServerImage({
    required this.id,
    required this.url,
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
    required this.page,
  });
  final int id, bytes, width, height, page;
  final Uri url;
  final String name;
}

class OwnedComplexServerImagePage {
  const OwnedComplexServerImagePage(this.items, this.page, this.hasNext);
  final List<OwnedComplexServerImage> items;
  final int page;
  final bool hasNext;
}

/// Current session's visible server library. The existing endpoint is not
/// member-filtered; this adapter makes no ownership/hash/upload provenance claim.
class OwnedComplexServerImages {
  OwnedComplexServerImages({required this.lease, required this.resources});
  final OwnedComplexResourceLease lease;
  final OwnedComplexResources resources;
  Future<bool> verify(OwnedComplexServerImage image) async {
    final page = await read(image.page);
    return page.items.any(
      (fresh) =>
          fresh.id == image.id &&
          fresh.url == image.url &&
          fresh.bytes == image.bytes &&
          fresh.width == image.width &&
          fresh.height == image.height,
    );
  }

  Future<OwnedComplexServerImagePage> read(
    int page, {
    Future<void>? abortTrigger,
  }) async {
    lease.guard();
    final root = await lease.use(
      () => lease.client.boundedOwnedImageChoicesJson(
        page,
        expectedSessionRevision: lease.revision,
        abortTrigger: abortTrigger == null
            ? lease.abortTrigger
            : Future.any<void>([lease.abortTrigger, abortTrigger]),
      ),
    );
    lease.guard();
    final rows = root['data'],
        actualPage = root['page'],
        totalPages = root['total_pages'];
    if (root['code'] is! int ||
        root['code'] != 0 ||
        rows is! List ||
        rows.length > 20 ||
        actualPage is! int ||
        actualPage != page ||
        totalPages is! int ||
        totalPages < 0 ||
        totalPages > 1000000) {
      throw const FormatException('Invalid server image page');
    }
    final result = <OwnedComplexServerImage>[];
    final seen = <int>{};
    for (final row in rows) {
      if (row is! Map) throw const FormatException('Invalid server image');
      final id = row['id'],
          raw = row['url'],
          name = row['file_name'],
          bytes = row['file_size'],
          width = row['width'],
          height = row['height'],
          mime = row['mime_type'];
      if (id is! int ||
          id <= 0 ||
          !seen.add(id) ||
          raw is! String ||
          raw.length > 2048 ||
          name is! String ||
          name.isEmpty ||
          name.length > 255 ||
          bytes is! int ||
          bytes <= 0 ||
          width is! int ||
          height is! int ||
          width <= 0 ||
          height <= 0) {
        throw const FormatException('Invalid server image metadata');
      }
      // Oversized/unsupported media stay unavailable, never passed to a decoder.
      if (bytes > 5 * 1024 * 1024 ||
          width > 8192 ||
          height > 8192 ||
          width * height > 16 * 1024 * 1024 ||
          !{
            'image/png',
            'image/jpeg',
            'image/gif',
            'image/webp',
          }.contains(mime)) {
        continue;
      }
      final uri = resources.canonical(Uri.parse(raw));
      final path = uri.pathSegments.sublist(
        lease.client.baseUri.pathSegments.length,
      );
      if (path.first != 'upload-files') {
        throw const FormatException('Invalid image route');
      }
      result.add(
        OwnedComplexServerImage(
          id: id,
          url: uri,
          name: name,
          bytes: bytes,
          width: width,
          height: height,
          page: page,
        ),
      );
    }
    return OwnedComplexServerImagePage(
      List.unmodifiable(result),
      page,
      page < totalPages,
    );
  }
}
