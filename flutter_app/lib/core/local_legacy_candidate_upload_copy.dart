import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;
import 'local_legacy_candidate_uploads.dart';
import 'local_legacy_import_records.dart';
import 'local_backup_importer.dart' show LocalBackupSpaceUnavailable;

final class LegacyUploadCopyProgress {
  const LegacyUploadCopyProgress(
    this.files,
    this.bytes,
    this.totalFiles,
    this.totalBytes,
  );
  final int files, bytes, totalFiles, totalBytes;
}

final class LegacyCopiedUpload {
  const LegacyCopiedUpload._(this.blob, this.file);
  final LegacyUploadBlob blob;
  final File file;
}

/// A private file-copy observation, never an activation or rendering approval.
/// Callers must verify bytes again before eventual candidate activation.
final class LegacyCopiedUploads {
  LegacyCopiedUploads._(
    this.directory,
    this.sourceSha256,
    this.recipeSha256,
    this.planSha256,
    List<LegacyCopiedUpload> files,
  ) : files = List.unmodifiable(files);
  final Directory directory;
  final String sourceSha256, recipeSha256, planSha256;
  final List<LegacyCopiedUpload> files;
}

final class _DigestSink implements Sink<Digest> {
  Digest? result;
  @override
  void add(Digest value) {
    result = value;
  }

  @override
  void close() {}
}

Future<void> _verifyUploadBlob(
  File file,
  LegacyUploadBlob blob,
  void Function() check,
) async {
  check();
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != blob.bytes) {
    throw const LegacyUploadFailure(LegacyUploadReason.integrity);
  }
  var read = 0;
  final hash = await sha256
      .bind(
        file.openRead().map((part) {
          check();
          read += part.length;
          if (read > blob.bytes) {
            throw const LegacyUploadFailure(LegacyUploadReason.integrity);
          }
          return part;
        }),
      )
      .first;
  check();
  if (read != blob.bytes ||
      hash.toString() != blob.sha256Hex ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != blob.bytes) {
    throw const LegacyUploadFailure(LegacyUploadReason.integrity);
  }
}

Future<LegacyCopiedUploads> copyLegacyCandidateUploads(
  LegacyCandidateUploads plan, {
  required Directory privateParent,
  required Future<int> Function() availableBytes,
  bool Function()? isCancelled,
  void Function(LegacyUploadCopyProgress)? onProgress,
}) async {
  void check() {
    if (isCancelled?.call() == true) throw const LegacyRecordsCancelled();
  }

  const reserve = 128 * 1024 * 1024;
  Directory? owned;

  try {
    check();
    if (await FileSystemEntity.type(privateParent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    final parent = Directory(await privateParent.resolveSymbolicLinks());
    if (await availableBytes() < plan.totalBytes + reserve) {
      throw const LocalBackupSpaceUnavailable();
    }
    check();
    owned = await parent.createTemp('legacy-upload-');
    final files = <LegacyCopiedUpload>[];
    var completed = 0, total = 0, sinceSpaceCheck = 0;
    onProgress?.call(
      LegacyUploadCopyProgress(0, 0, plan.blobs.length, plan.totalBytes),
    );
    for (final blob in plan.blobs) {
      check();
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(blob.attachmentId)) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
      final input = blob.staged.file;
      if (await FileSystemEntity.type(input.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await input.length() != blob.bytes) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
      final output = File(paths.join(owned.path, blob.attachmentId));
      await output.create(exclusive: true);
      final writer = await output.open(mode: FileMode.writeOnly);
      final digest = _DigestSink();
      final hashing = sha256.startChunkedConversion(digest);
      var read = 0;
      try {
        await for (final part in input.openRead()) {
          check();
          read += part.length;
          if (read > blob.bytes) {
            throw const LegacyUploadFailure(LegacyUploadReason.integrity);
          }
          await writer.writeFrom(part);
          hashing.add(part);
          total += part.length;
          sinceSpaceCheck += part.length;
          if (sinceSpaceCheck >= 8 * 1024 * 1024) {
            sinceSpaceCheck = 0;
            if (await availableBytes() < reserve) {
              throw const LocalBackupSpaceUnavailable();
            }
          }
          onProgress?.call(
            LegacyUploadCopyProgress(
              completed,
              total,
              plan.blobs.length,
              plan.totalBytes,
            ),
          );
        }
        hashing.close();
        if (read != blob.bytes ||
            digest.result?.toString() != blob.sha256Hex ||
            await FileSystemEntity.type(input.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await input.length() != blob.bytes) {
          throw const LegacyUploadFailure(LegacyUploadReason.integrity);
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      await _verifyUploadBlob(output, blob, check);
      files.add(LegacyCopiedUpload._(blob, output));
      completed++;
      onProgress?.call(
        LegacyUploadCopyProgress(
          completed,
          total,
          plan.blobs.length,
          plan.totalBytes,
        ),
      );
    }
    check();
    if (total != plan.totalBytes) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    // A late callback must not mutate a previously checked file unnoticed.
    for (final file in files) {
      await _verifyUploadBlob(file.file, file.blob, check);
    }
    check();
    if (await availableBytes() < reserve) {
      throw const LocalBackupSpaceUnavailable();
    }
    check();
    return LegacyCopiedUploads._(
      owned,
      plan.sourceSha256,
      plan.recipeSha256,
      plan.planSha256,
      files,
    );
  } catch (error) {
    try {
      if (owned != null) {
        final type = await FileSystemEntity.type(
          owned.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          await Link(owned.path).delete();
        } else if (type == FileSystemEntityType.directory) {
          await owned.delete(recursive: true);
        }
      }
    } catch (_) {
      throw const LegacyUploadFailure(LegacyUploadReason.storage);
    }
    if (error is LegacyRecordsCancelled ||
        error is LegacyUploadFailure ||
        error is LocalBackupSpaceUnavailable) {
      rethrow;
    }
    throw const LegacyUploadFailure(LegacyUploadReason.storage);
  }
}

/// Read-only verification immediately before storing a private copy observation.
/// This does not make the filesystem immutable or authorize activation.
Future<void> verifyLegacyCopiedUploads(
  LegacyCandidateUploads plan,
  LegacyCopiedUploads copied, {
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() == true) {
      throw const LegacyRecordsCancelled();
    }
  }

  try {
    check();
    if (copied.sourceSha256 != plan.sourceSha256 ||
        copied.recipeSha256 != plan.recipeSha256 ||
        copied.planSha256 != plan.planSha256 ||
        copied.files.length != plan.blobs.length) {
      throw const LegacyUploadFailure(LegacyUploadReason.sourceMismatch);
    }
    if (await FileSystemEntity.type(
              copied.directory.path,
              followLinks: false,
            ) !=
            FileSystemEntityType.directory ||
        await copied.directory.resolveSymbolicLinks() !=
            copied.directory.path) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    final expected = {for (final blob in plan.blobs) blob.attachmentId: blob};
    final observed = <String>{};
    await for (final entry in copied.directory.list(followLinks: false)) {
      check();
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !expected.containsKey(paths.basename(entry.path))) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
      observed.add(paths.basename(entry.path));
    }
    if (observed.length != expected.length) {
      throw const LegacyUploadFailure(LegacyUploadReason.integrity);
    }
    final ids = <String>{};
    for (final file in copied.files) {
      check();
      final id = file.blob.attachmentId,
          blob = expected[file.blob.attachmentId];
      if (blob == null ||
          !ids.add(id) ||
          paths.dirname(file.file.path) != copied.directory.path ||
          paths.basename(file.file.path) != id ||
          file.blob.logicalName != blob.logicalName ||
          file.blob.aliasPath != blob.aliasPath ||
          file.blob.bytes != blob.bytes ||
          file.blob.sha256Hex != blob.sha256Hex) {
        throw const LegacyUploadFailure(LegacyUploadReason.integrity);
      }
      await _verifyUploadBlob(file.file, blob, check);
    }
    check();
  } catch (error) {
    if (error is LegacyUploadFailure || error is LegacyRecordsCancelled) {
      rethrow;
    }
    throw const LegacyUploadFailure(LegacyUploadReason.storage);
  }
}
