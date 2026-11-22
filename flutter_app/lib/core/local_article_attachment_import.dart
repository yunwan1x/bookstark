import 'dart:async';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'attachments.dart';
import 'local_attachments.dart';

/// Stream limit is repeated during copying; a changed provider length cannot
/// turn the native picker's size receipt into an unbounded private import.
Future<Attachment> importLocalArticleAttachment(
  LocalAttachments repository,
  XFile file, {
  AttachmentCancellation? cancellation,
}) async {
  const maxBytes = 64 * 1024 * 1024;
  cancellation?.check();
  if (await file.length() > maxBytes) {
    throw const FormatException('Attachment exceeds 64 MiB');
  }
  cancellation?.check();
  return repository.add(
    _BoundedAttachmentFile(file, maxBytes, cancellation),
    cancellation: cancellation,
  );
}

class _BoundedAttachmentFile extends XFile {
  _BoundedAttachmentFile(this.source, this.limit, this.cancellation)
    : super(source.path, name: source.name);
  final XFile source;
  @override
  String get name => source.name;
  final int limit;
  final AttachmentCancellation? cancellation;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    if (start != null || end != null) {
      throw StateError('Whole attachment import required');
    }
    var count = 0;
    await for (final bytes in source.openRead()) {
      cancellation?.check();
      count += bytes.length;
      if (count > limit) {
        throw const FormatException('Attachment exceeds 64 MiB');
      }
      yield bytes;
    }
    cancellation?.check();
  }
}
