import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/image_content.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runImagesContract(BookstarkClient client) async {
  final repo = RemoteImagesRepository(client);
  final created = <ManagedImage>[];
  try {
    final source = await File(
      '../docs/flutter-rewrite/pages/08-editor.png',
    ).readAsBytes();
    final payload = ImageUploadPayload.fromBytes(
      name: '图片库真实转换契约.png',
      bytes: source,
      category: ImageCategory.note,
    );
    final first = await repo.upload(payload);
    final duplicate = await repo.upload(
      ImageUploadPayload.fromBytes(
        name: '同内容其他分类.png',
        bytes: source,
        category: ImageCategory.drawing,
      ),
    );
    check(
      duplicate.id == first.id,
      'Global hash dedup retains canonical image ID',
    );
    check(
      (await repo.byHash(payload.hash))?.id == first.id,
      'Hash lookup returns confirmed saved ID',
    );
    final canonical = await repo.findCanonical(
      ManagedImage(id: first.id, name: first.name, uri: first.uri),
    );
    check(
      canonical != null &&
          canonical.id == first.id &&
          canonical.category == 'note',
      'List preserves original category after dedup',
    );
    created.add(canonical!);
    final actual = await repo.bytes(canonical.uri);
    check(
      imageContentMime(actual) == 'image/webp',
      'Actual converted bytes are WebP, irrespective of input PNG filename',
    );
    check(
      canonical.name.endsWith('.png'),
      'Original display filename retained',
    );
    final listing = await repo.list(const ImagesQuery(keyword: '图片库真实转换契约'));
    check(
      listing.items.any((image) => image.id == first.id) &&
          listing.totalImageBytes >= canonical.size,
      'Filtered listing returns actual records and global main-file bytes',
    );
    final svg = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80"><rect width="120" height="80" fill="#2563eb"/><title>图片库契约独立原图</title></svg>',
      ),
    );
    final vector = await repo.upload(
      ImageUploadPayload.fromBytes(
        name: '图片库矢量契约.svg',
        bytes: svg,
        category: ImageCategory.drawing,
      ),
    );
    final listed = await repo.findCanonical(
      ManagedImage(id: vector.id, name: vector.name, uri: vector.uri),
    );
    check(listed != null, 'SVG appears under actual server ID');
    created.add(listed!);
    check(
      base64Encode(await repo.bytes(listed.uri)) == base64Encode(svg),
      'SVG download preserves original bytes',
    );
    check(!listed.knownDimensions, 'Zero server dimensions stay unknown');
    final animation = await File('test/fixtures/two-frame.gif').readAsBytes();
    final gif = await repo.upload(
      ImageUploadPayload.fromBytes(
        name: '图片库动画契约.gif',
        bytes: animation,
        category: ImageCategory.editor,
      ),
    );
    final gifRecord = await repo.findCanonical(
      ManagedImage(id: gif.id, name: gif.name, uri: gif.uri),
    );
    check(gifRecord != null, 'Animated GIF appears under its saved ID');
    created.add(gifRecord!);
    check(
      base64Encode(await repo.bytes(gifRecord.uri)) == base64Encode(animation),
      'Animated GIF is stored byte-for-byte without flattening',
    );
    final result = await repo.remove(listed);
    check(
      result.recordRemoved && result.linkAvailable == false,
      'DELETE is followed by fresh public availability check',
    );
    check(
      (await repo.verifyRemoval(listed)).recordRemoved,
      'Idempotent removal verification reads canonical state',
    );
    check(
      await repo.byHash(
            ImageUploadPayload.fromBytes(
              name: 'x.svg',
              bytes: svg,
              category: ImageCategory.editor,
            ).hash,
          ) ==
          null,
      'Removed SVG hash no longer resolves',
    );
    stdout.writeln(
      'PASS production image library: actual paginated IDs, global hash dedup, original category, PNG-to-WebP bytes, public SVG and animated GIF bytes, unknown dimensions and deletion availability verification',
    );
  } finally {
    for (final image in created.reversed) {
      await repo.remove(image);
    }
    repo.dispose();
  }
}
