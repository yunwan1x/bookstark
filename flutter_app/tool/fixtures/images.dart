// In-memory images only for tests/visual target; never imported by lib/main.dart.
import 'dart:typed_data';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/image_content.dart';
import 'package:bookstark_flutter/core/attachments.dart';

class ImagesFixture extends ImagesRepository {
  final records = <int, ManagedImage>{};
  final values = <Uri, Uint8List>{};
  final hashes = <String, UploadedImageReference>{};
  int uploadCalls = 0, hashCalls = 0, removeCalls = 0, nextId = 100;
  Future<UploadedImageReference> Function(
    ImageUploadPayload,
    AttachmentCancellation?,
    void Function(int, int)?,
  )?
  uploadOverride;
  @override
  bool get publicLinks => true;
  UploadedImageReference recordPayload(ImageUploadPayload payload) {
    final id = nextId++, mime = imageContentMime(payload.bytes) ?? 'image/png';
    final uri = Uri.parse(
      'https://fixture.invalid/upload-files/${payload.category.name}/$id${mime == 'image/svg+xml' ? '.svg' : '.png'}',
    );
    final ref = UploadedImageReference(
      id: id,
      name: payload.name,
      uri: uri,
      size: payload.bytes.length,
      width: 0,
      height: 0,
    );
    hashes[payload.hash] = ref;
    records[id] = ManagedImage(
      id: id,
      name: payload.name,
      uri: uri,
      size: payload.bytes.length,
      mime: mime,
      category: payload.category.name,
      createdOn: '2026-11-04 10:20',
    );
    values[uri] = payload.bytes;
    return ref;
  }

  @override
  Future<ImagesPageResult> list(ImagesQuery query) async {
    query.parameters();
    final rows =
        records.values
            .where(
              (item) =>
                  item.name.contains(query.keyword) &&
                  (query.category == null ||
                      item.category == query.category!.name),
            )
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
    return ImagesPageResult(
      rows.skip((query.page - 1) * 20).take(20).toList(),
      total: rows.length,
      page: query.page,
      pageSize: 20,
      totalImageBytes: records.values.fold(0, (sum, item) => sum + item.size),
    );
  }

  @override
  Future<UploadedImageReference?> byHash(String hash) async {
    hashCalls++;
    return hashes[hash];
  }

  @override
  Future<UploadedImageReference> upload(
    ImageUploadPayload payload, {
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) async {
    uploadCalls++;
    if (uploadOverride != null) {
      return uploadOverride!(payload, cancellation, onSent);
    }
    cancellation?.check();
    onSent?.call(payload.bytes.length, payload.bytes.length);
    return recordPayload(payload);
  }

  @override
  Future<ImageRemovalResult> remove(ManagedImage item) async {
    removeCalls++;
    records.remove(item.id);
    values.remove(item.uri);
    hashes.removeWhere((_, ref) => ref.id == item.id);
    return const ImageRemovalResult(recordRemoved: true, linkAvailable: false);
  }

  @override
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item) async =>
      ImageRemovalResult(
        recordRemoved: !records.containsKey(item.id),
        linkAvailable: values.containsKey(item.uri),
      );
  @override
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  }) async {
    final data = values[uri];
    if (data == null) throw StateError('Fixture image unavailable');
    if (data.length > maxBytes) throw StateError('Fixture byte bound');
    return data;
  }
}
