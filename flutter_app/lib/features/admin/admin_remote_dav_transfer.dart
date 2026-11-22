import '../../core/owned_download_cache.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'admin_files_transfer.dart'
    show AdminDownloadedFile, adminFileTransferLimit;
import 'admin_remote_dav_models.dart';

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest digest) {
    value = digest;
  }

  @override
  void close() {}
}

/// Private temporary result, never exported until exact size and fresh target checks.
Future<AdminDownloadedFile> receiveAdminDavFile(
  http.StreamedResponse response,
  AdminDavEntry entry,
  Future<void> abort, {
  void Function(int, int)? onReceived,
  Future<Directory> Function()? cacheDirectory,
}) async {
  if (entry.type != AdminDavEntryType.file ||
      entry.size > adminFileTransferLimit) {
    throw const FormatException('Remote download exceeds local limit');
  }
  if (response.statusCode != 200 ||
      response.contentLength != null && response.contentLength != entry.size) {
    final subscription = response.stream.listen(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await subscription.cancel();
    throw const FormatException('Download metadata changed');
  }
  var cancelled = false, complete = false;
  abort.then(
    (_) {
      cancelled = true;
    },
    onError: (Object _, StackTrace _) {
      cancelled = true;
    },
  );
  Directory? directory;
  OwnedDownloadLease? cacheLease;
  RandomAccessFile? writer;
  final memory = kIsWeb ? BytesBuilder(copy: false) : null;
  final digest = _DigestSink();
  final hashing = crypto.sha256.startChunkedConversion(digest);
  var hashClosed = false;
  void check() {
    if (cancelled) throw StateError('Remote download cancelled');
  }

  try {
    check();
    if (!kIsWeb) {
      final root = await (cacheDirectory?.call() ?? getTemporaryDirectory());
      cacheLease = await OwnedDownloadCache(root).create('dav');
      directory = cacheLease.directory;
      writer = await File(
        '${directory.path}/partial',
      ).open(mode: FileMode.writeOnly);
    }
    var count = 0;
    await for (final chunk in response.stream) {
      check();
      count += chunk.length;
      if (count > entry.size || count > adminFileTransferLimit) {
        throw const FormatException('Remote download exceeds expected size');
      }
      hashing.add(chunk);
      if (memory != null) {
        memory.add(chunk);
      } else {
        await writer!.writeFrom(chunk);
      }
      onReceived?.call(count, entry.size);
    }
    check();
    if (count != entry.size) {
      throw const FormatException('Remote download incomplete');
    }
    hashing.close();
    hashClosed = true;
    if (writer != null) {
      await writer.flush();
      await writer.close();
      writer = null;
    }
    check();
    final bytes = memory?.takeBytes();
    final file = directory == null
        ? XFile.fromData(
            bytes!,
            name: entry.name,
            mimeType: 'application/octet-stream',
          )
        : XFile(
            '${directory.path}/partial',
            name: entry.name,
            mimeType: 'application/octet-stream',
          );
    complete = true;
    return AdminDownloadedFile(
      file: file,
      name: entry.name,
      size: count,
      hash: digest.value!.toString(),
      directory: directory,
      cacheLease: cacheLease,
    );
  } finally {
    if (!hashClosed) hashing.close();
    await writer?.close();
    if (!complete && cacheLease != null) {
      await cacheLease.close();
    } else if (!complete && directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
