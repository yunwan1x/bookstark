import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'drive_download.dart';

enum FileExportOutcome { saved, cancelled, browserDownloadStarted }

class SystemFileExporter {
  const SystemFileExporter();
  static const _channel = MethodChannel('bookstark/file_export');
  bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      {
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);
  Future<FileExportOutcome> save(DriveDownloadedFile source) => saveFile(
    file: source.file,
    name: source.node.name,
    mime: source.node.mime,
    size: source.size,
    hash: source.hash,
  );
  Future<FileExportOutcome> saveFile({
    required XFile file,
    required String name,
    required String mime,
    required int size,
    required String hash,
  }) async {
    if (kIsWeb) {
      await file.saveTo(name);
      return FileExportOutcome.browserDownloadStarted;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'saveFile',
        {
          'path': file.path,
          'name': name,
          'mime': mime,
          'size': size,
          'sha256': hash,
        },
      );
      if (reply == null || reply['saved'] is! bool) {
        throw const FormatException('Invalid Android export result');
      }
      if (reply['saved'] == false) return FileExportOutcome.cancelled;
      if (reply['bytes'] != size || reply['sha256'] != hash) {
        throw const FormatException(
          'Saved file confirmation does not match source',
        );
      }
      return FileExportOutcome.saved;
    }
    if (!supported) {
      throw UnsupportedError(
        'System file save is unavailable on this platform',
      );
    }
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return FileExportOutcome.cancelled;
    await file.saveTo(location.path);
    return FileExportOutcome.saved;
  }
}
