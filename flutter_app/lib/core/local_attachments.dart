import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'attachments.dart';
import 'api_client.dart';
import 'local_data_maintenance.dart';

class LocalAttachments extends AttachmentRepository {
  LocalAttachments(
    this.directory, {
    super.publicTransport,
    LocalDataMaintenance? maintenance,
  }) : maintenance =
           maintenance ??
           LocalDataMaintenance.forStorage(
             'attachments:${directory.absolute.path}',
           );
  final Directory directory;
  final LocalDataMaintenance maintenance;
  String _id(Uri uri) {
    if (uri.scheme != 'bookstark-attachment' ||
        uri.host.isNotEmpty ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(uri.pathSegments.first)) {
      throw const FormatException('Invalid local attachment reference');
    }
    return uri.pathSegments.first;
  }

  @override
  bool owns(Uri uri) {
    try {
      _id(uri);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) => maintenance.use(() async {
    cancellation?.check();
    if (protected) {
      throw StateError('本地密码附件需要加密存储 / Encrypted local attachments required');
    }
    await directory.create(recursive: true);
    final id = attachmentId();
    final target = File('${directory.path}/$id');
    final sink = target.openWrite();
    try {
      await sink.addStream(
        file.openRead().takeWhile((_) => cancellation?.cancelled != true),
      );
      cancellation?.check();
      await sink.flush();
      await sink.close();
      cancellation?.check();
    } catch (_) {
      // A stream failure may already have closed the sink. Closing it again
      // must not prevent removal of this operation's unpublished partial file.
      try {
        await sink.close();
      } catch (_) {}
      if (await target.exists()) await target.delete();
      rethrow;
    }
    final name = attachmentName(file.name);
    return Attachment(
      uri: Uri.parse(
        'bookstark-attachment:///$id/${Uri.encodeComponent(name)}',
      ),
      name: name,
      image: rasterImage(name),
      size: await target.length(),
    );
  });

  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) =>
      maintenance.use(() async {
        if (['http', 'https'].contains(uri.scheme)) {
          return readPublic(uri, maxBytes: maxBytes);
        }
        final id = _id(uri);
        final file = File('${directory.path}/$id');
        if (await file.length() > maxBytes) {
          throw const ApiFailure(413, '文件超过读取上限 / File exceeds the read limit');
        }
        // Use the same streaming bound even if the file changes after stat.
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.openRead()) {
          if (builder.length + chunk.length > maxBytes) {
            throw const ApiFailure(
              413,
              '文件超过读取上限 / File exceeds the read limit',
            );
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      });
}
