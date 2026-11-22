import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'api_client.dart';
import 'attachments.dart';

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? digest;
  @override
  void add(crypto.Digest value) {
    digest = value;
  }

  @override
  void close() {}
}

class DriveSourceSnapshot {
  DriveSourceSnapshot._(this.file, this.size, this.modified, this.hash);
  final XFile file;
  final int size;
  final DateTime modified;
  final String hash;
  static Stream<List<int>> _boundedChunks(
    XFile file,
    int size,
    AttachmentCancellation? cancellation,
  ) async* {
    const chunkSize = 256 * 1024;
    for (var start = 0; start < size; start += chunkSize) {
      cancellation?.check();
      final end = (start + chunkSize).clamp(0, size);
      var count = 0;
      await for (final bytes in file.openRead(start, end)) {
        cancellation?.check();
        count += bytes.length;
        if (count > end - start) {
          throw const FormatException('Source range exceeded requested bounds');
        }
        yield bytes;
      }
      if (count != end - start) {
        throw const FormatException('Incomplete source range');
      }
    }
  }

  static Future<DriveSourceSnapshot> prepare(
    XFile file, {
    required int maxBytes,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    final size = await file.length(), modified = await file.lastModified();
    if (size < 0 || size > maxBytes) {
      throw const ApiFailure(
        413,
        '文件超过服务器单文件上限 / File exceeds server single-file limit',
      );
    }
    var count = 0;
    final stream = _boundedChunks(file, size, cancellation).map((chunk) {
      cancellation?.check();
      count += chunk.length;
      if (count > size || count > maxBytes) {
        throw const FormatException(
          '源文件在读取时发生变化 / Source file changed while reading',
        );
      }
      return chunk;
    });
    final hash = (await crypto.sha256.bind(stream).first).toString();
    if (count != size ||
        await file.length() != size ||
        await file.lastModified() != modified) {
      throw const FormatException(
        '源文件在读取时发生变化 / Source file changed while reading',
      );
    }
    cancellation?.check();
    return DriveSourceSnapshot._(file, size, modified, hash);
  }

  Future<void> verifyMetadata({AttachmentCancellation? cancellation}) async {
    cancellation?.check();
    if (await file.length() != size || await file.lastModified() != modified) {
      throw const FormatException(
        '源文件已更新，请重新选择 / Source file changed; select it again',
      );
    }
  }

  Stream<List<int>> verifiedStream({
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) async* {
    await verifyMetadata(cancellation: cancellation);
    var count = 0;
    final result = _DigestSink();
    final digest = crypto.sha256.startChunkedConversion(result);
    try {
      await for (final chunk in _boundedChunks(file, size, cancellation)) {
        cancellation?.check();
        count += chunk.length;
        if (count > size) {
          throw const FormatException('Source file size changed');
        }
        digest.add(chunk);
        onSent?.call(count, size);
        yield chunk;
      }
    } finally {
      digest.close();
    }
    if (count != size || result.digest.toString() != hash) {
      throw const FormatException('源文件内容已改变 / Source file content changed');
    }
    await verifyMetadata(cancellation: cancellation);
  }

  Future<List<String>> prove({
    required Uint8List nonce,
    required int chunkSize,
    required List<int> indices,
    AttachmentCancellation? cancellation,
  }) async {
    if (chunkSize != 1 << 20 ||
        indices.isEmpty ||
        indices.length > 3 ||
        indices.toSet().length != indices.length ||
        indices.any(
          (index) => index < 0 || index >= (size + chunkSize - 1) ~/ chunkSize,
        )) {
      throw const FormatException('Invalid file possession challenge');
    }
    await verifyMetadata(cancellation: cancellation);
    final hashes = <String>[];
    for (final index in indices) {
      final start = index * chunkSize,
          end = (start + chunkSize).clamp(0, size),
          result = _DigestSink();
      final digest = crypto.sha256.startChunkedConversion(result);
      digest.add(nonce);
      var count = 0;
      try {
        await for (final bytes in file.openRead(start, end)) {
          cancellation?.check();
          count += bytes.length;
          if (count > end - start) {
            throw const FormatException('Source chunk exceeded bound');
          }
          digest.add(bytes);
        }
      } finally {
        digest.close();
      }
      if (count != end - start) {
        throw const FormatException('Truncated source chunk');
      }
      hashes.add(result.digest!.toString());
    }
    await verifyMetadata(cancellation: cancellation);
    return hashes;
  }
}
