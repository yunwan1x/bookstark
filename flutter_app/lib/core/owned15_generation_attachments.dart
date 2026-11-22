import 'dart:typed_data';
import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'attachments.dart';
import 'owned15_generation_resources.dart';

/// Rendering only. Never converts an original generation resource into an
/// account/public URL or authorizes new attachment INSERTs.
final class Owned15GenerationAttachments extends AttachmentRepository {
  Owned15GenerationAttachments(this.resources);
  final Owned15GenerationResources resources;
  @override
  bool owns(Uri uri) => resources.owns(uri);
  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) => Future.error(
    UnsupportedError('Original generation assets are read-only'),
  );
  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) async {
    if (maxBytes < 0 || !owns(uri)) {
      throw const FormatException('Asset unavailable');
    }
    final value = await resources.read(uri);
    if (value == null || value.bytes.length > maxBytes || !resources.current) {
      throw const FormatException('Asset unavailable');
    }
    return value.bytes;
  }

  @override
  Future<Uint8List> readPublic(Uri uri, {required int maxBytes}) =>
      Future.error(const FormatException('Network assets unavailable'));
  @override
  void close() {
    unawaited(resources.retire().catchError((Object _) {}));
    super.close();
  }
}
