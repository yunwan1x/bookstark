import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'local_legacy_zip_index.dart';
import 'local_backup_importer.dart' show LocalBackupSpaceUnavailable;

final class LegacyZipStageCancelled implements Exception {
  const LegacyZipStageCancelled();
}

final class LegacyStagedFile {
  const LegacyStagedFile({
    required this.logicalName,
    required this.file,
    required this.bytes,
    required this.sha256Hex,
  });
  final String logicalName;
  final File file;
  final int bytes;
  final String sha256Hex;
}

final class LegacyZipStage {
  const LegacyZipStage._({
    required this.directory,
    required this.files,
    required this.sourceSha256,
    required this.sourceBytes,
  });
  final Directory directory;
  final Map<String, LegacyStagedFile> files;
  final String sourceSha256;
  final int sourceBytes;

  /// Stages into a newly allocated private child; archive paths never reach a
  /// filesystem API. The source is a caller-owned immutable SAF inbox copy.
  /// This is inspection only and never opens the active content database.
  static Future<LegacyZipStage> inspect(
    File source, {
    required Directory privateParent,
    required String expectedSha256,
    required Future<int> Function() availableBytes,
    LegacyZipLimits limits = const LegacyZipLimits(),
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) throw const LegacyZipStageCancelled();
    }

    checkCancelled();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
      throw ArgumentError('Expected a source SHA-256 receipt');
    }
    if (await FileSystemEntity.type(privateParent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw ArgumentError('Expected a private staging directory');
    }
    final index = await LegacyZipIndex.read(source, limits: limits);
    checkCancelled();
    if (await _sourceHash(source, checkCancelled) != expectedSha256) {
      throw const FormatException('Legacy ZIP source receipt does not match');
    }
    const reserveBytes = 128 * 1024 * 1024;
    if (await availableBytes() < index.totalBytes + reserveBytes) {
      throw const LocalBackupSpaceUnavailable();
    }
    var bytesSinceSpaceCheck = 0;
    Future<void> checkSpace(int bytes) async {
      bytesSinceSpaceCheck += bytes;
      if (bytesSinceSpaceCheck >= 8 * 1024 * 1024) {
        bytesSinceSpaceCheck = 0;
        if (await availableBytes() < reserveBytes) {
          throw const LocalBackupSpaceUnavailable();
        }
      }
    }

    final task = await privateParent.createTemp('legacy-zip-');
    try {
      final files = <String, LegacyStagedFile>{};
      for (final entry in index.entries) {
        checkCancelled();
        if (entry.isDirectory) {
          // Empty compressed directory streams are also decoded and checked.
          await _inflate(source, entry, null, checkCancelled, checkSpace);
          continue;
        }
        final output = File(p.join(task.path, 'entry-${files.length}.bin'));
        final digest = await _inflate(
          source,
          entry,
          output,
          checkCancelled,
          checkSpace,
        );
        files[entry.name] = LegacyStagedFile(
          logicalName: entry.name,
          file: output,
          bytes: entry.uncompressedBytes,
          sha256Hex: digest,
        );
      }
      checkCancelled();
      if (await source.length() != index.archiveBytes ||
          await _sourceHash(source, checkCancelled) != expectedSha256) {
        throw const FormatException(
          'Legacy ZIP source changed during inspection',
        );
      }
      checkCancelled();
      return LegacyZipStage._(
        directory: task,
        files: Map.unmodifiable(files),
        sourceSha256: expectedSha256,
        sourceBytes: index.archiveBytes,
      );
    } catch (_) {
      // Only the random child allocated by this invocation is removed.
      if (await task.exists()) await task.delete(recursive: true);
      rethrow;
    }
  }
}

Future<String> _sourceHash(File file, void Function() check) async {
  final sink = _DigestSink();
  final hash = sha256.startChunkedConversion(sink);
  try {
    await for (final chunk in file.openRead()) {
      check();
      hash.add(chunk);
    }
  } finally {
    hash.close();
  }
  return sink.value!.toString();
}

Future<String> _inflate(
  File source,
  LegacyZipEntry entry,
  File? output,
  void Function() check,
  Future<void> Function(int) checkSpace,
) async {
  final sink = _DigestSink();
  final hash = sha256.startChunkedConversion(sink);
  RandomAccessFile? writer;
  var length = 0;
  var crc = 0xffffffff;
  try {
    if (output != null) writer = await output.open(mode: FileMode.writeOnly);
    Stream<List<int>> bytes = source.openRead(
      entry.dataOffset,
      entry.dataOffset + entry.compressedBytes,
    );
    if (entry.method == 8) bytes = bytes.transform(ZLibDecoder(raw: true));
    await for (final chunk in bytes) {
      check();
      length += chunk.length;
      if (length > entry.uncompressedBytes) {
        throw const FormatException('ZIP inflated beyond its declared length');
      }
      await checkSpace(chunk.length);
      hash.add(chunk);
      for (final byte in chunk) {
        crc = _crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
      }
      await writer?.writeFrom(chunk);
    }
    check();
    if (length != entry.uncompressedBytes ||
        ((crc ^ 0xffffffff) & 0xffffffff) != entry.crc32) {
      throw const FormatException('ZIP payload length or CRC is invalid');
    }
    await writer?.flush();
  } finally {
    hash.close();
    await writer?.close();
  }
  return sink.value!.toString();
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

final Uint32List _crcTable = Uint32List.fromList(
  List.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
    return crc;
  }),
);
