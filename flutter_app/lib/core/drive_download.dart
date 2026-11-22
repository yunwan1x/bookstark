import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'api_client.dart';
import 'attachments.dart';
import 'drive_models.dart';
import 'drive_repository.dart';
import 'owned_download_cache.dart';

class _Hash implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest digest) {
    value = digest;
  }

  @override
  void close() {}
}

class DriveDownloadedFile {
  DriveDownloadedFile._(
    this._directory, {
    required this.node,
    required this.file,
    required this.hash,
    required this.size,
    this.memory,
    this.cacheLease,
  });
  final DriveNode node;
  final XFile file;
  final String hash;
  final int size;
  final Uint8List? memory;
  final Directory? _directory;
  final OwnedDownloadLease? cacheLease;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    final directory = _directory;
    if (cacheLease != null) {
      await cacheLease!.close();
    } else if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _closed = true;
  }
}

/// Download one immutable content version to bounded memory (web) or private cache.
Future<DriveDownloadedFile> downloadDriveFile(
  DriveRepository repository,
  DriveNode source, {
  int? maxBytes,
  AttachmentCancellation? cancellation,
  void Function(int, int)? onReceived,
  Future<Directory> Function()? cacheDirectory,
}) async {
  cancellation?.check();
  final node = await repository.verify(source, cancellation: cancellation);
  if (node.directory) {
    throw const FormatException('Cannot download a directory');
  }
  final bound = maxBytes ?? node.size;
  if (node.size > bound) {
    throw const ApiFailure(413, '文件超过预览读取上限 / File exceeds preview read bound');
  }
  if (kIsWeb && node.size > 64 * 1024 * 1024) {
    throw const ApiFailure(
      413,
      '浏览器预览文件超过64MiB / Browser file exceeds 64 MiB preview bound',
    );
  }
  final response = await repository.open(node, cancellation: cancellation);
  Directory? directory;
  OwnedDownloadLease? cacheLease;
  RandomAccessFile? writer;
  var completed = false, responseStarted = false;
  final memory = kIsWeb ? BytesBuilder(copy: false) : null;
  final result = _Hash();
  final hash = crypto.sha256.startChunkedConversion(result);
  try {
    if (response.status != 200 ||
        response.length != null && response.length != node.size) {
      throw const FormatException('File version or content length changed');
    }
    if (!kIsWeb) {
      final root = await (cacheDirectory?.call() ?? getTemporaryDirectory());
      cacheLease = await OwnedDownloadCache(root).create('drive');
      directory = cacheLease.directory;
      writer = await File(
        '${directory.path}/partial',
      ).open(mode: FileMode.writeOnly);
    }
    var count = 0;
    responseStarted = true;
    await for (final chunk in response.stream) {
      cancellation?.check();
      count += chunk.length;
      if (count > node.size || count > bound) {
        throw const ApiFailure(
          413,
          '下载超过预期文件大小 / Download exceeds expected file size',
        );
      }
      hash.add(chunk);
      if (memory != null) {
        memory.add(chunk);
      } else {
        await writer!.writeFrom(chunk);
      }
      onReceived?.call(count, node.size);
    }
    hash.close();
    if (count != node.size) {
      throw const FormatException('文件下载不完整 / Incomplete file download');
    }
    final actual = result.value!.toString();
    if (node.etag.isNotEmpty && node.etag != actual) {
      throw const FormatException(
        '文件内容与版本不一致，请刷新 / File bytes do not match its version; refresh',
      );
    }
    cancellation?.check();
    if (writer != null) {
      await writer.flush();
      await writer.close();
      writer = null;
    }
    final Uint8List? bytes = memory?.takeBytes().asUnmodifiableView();
    final XFile file;
    if (directory != null) {
      final extension =
          RegExp(r'(\.[A-Za-z0-9]{1,12})$').firstMatch(node.name)?.group(1) ??
          '.bin';
      final target = await File(
        '${directory.path}/partial',
      ).rename('${directory.path}/file$extension');
      file = XFile(target.path, mimeType: node.mime);
    } else {
      file = XFile.fromData(bytes!, name: node.name, mimeType: node.mime);
    }
    completed = true;
    return DriveDownloadedFile._(
      directory,
      node: node,
      file: file,
      hash: actual,
      size: count,
      memory: bytes,
      cacheLease: cacheLease,
    );
  } finally {
    if (result.value == null) hash.close();
    try {
      await writer?.close();
    } catch (_) {}
    if (!completed) {
      // Cancel a response not yet listened to (e.g. invalid headers or cache failure).
      if (!responseStarted) {
        try {
          await response.stream.listen((_) {}).cancel();
        } catch (_) {}
      }
      if (cacheLease != null) {
        await cacheLease.close();
      } else if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}
