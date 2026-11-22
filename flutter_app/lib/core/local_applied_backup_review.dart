import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'local_backup_codec.dart';
import 'local_backup_content.dart';
import 'local_backup_schema.dart';
import 'local_data_paths.dart';
import 'local_generation_state.dart';
import 'native_local_data_control.dart';

class ReviewedLocalAppliedBackup {
  ReviewedLocalAppliedBackup._(
    this.intent,
    this.manifest,
    this.contentReport,
    this.bytes,
  );
  final LocalRestoreIntent intent;
  final LocalBackupManifest manifest;
  final LocalBackupContentReport contentReport;
  final int bytes;
}

/// Native first hashes the full inactive generation and retained source archive.
/// SQLite structure/content are then read-only checked; a fresh state observation
/// binds both passes. This observation never acknowledges or replays restoration.
class LocalAppliedBackupReviewer {
  LocalAppliedBackupReviewer({
    required this.control,
    required this.privateSupport,
    required this.privateCache,
    required this.factory,
  });
  final NativeLocalDataControl control;
  final Directory privateSupport, privateCache;
  final DatabaseFactory factory;

  Future<ReviewedLocalAppliedBackup> read(
    LocalDataControlState selected,
  ) async {
    final intent = selected.observation.intent;
    if (!selected.observation.canAcknowledgeApplied || intent == null) {
      throw StateError('Applied data must be selected for read-only review');
    }
    final files = await control.reviewApplied(intent);
    final pointer = LocalGenerationPointer.parse(intent.targetPointerRaw);
    final layout = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: privateSupport,
    );
    // Never create/open through LocalStore here: upgrades and ordinary writers
    // remain unavailable until the explicit durable acknowledgement.
    final task = Directory(
      '${privateCache.path}/applied-review-${attachmentId()}',
    );
    if (await privateSupport.resolveSymbolicLinks() != privateSupport.path ||
        await privateCache.resolveSymbolicLinks() != privateCache.path) {
      throw const FormatException('Private review roots must be canonical');
    }
    if (await FileSystemEntity.type(task.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Review identity already exists');
    }
    await task.create();
    try {
      final facts =
          await LocalBackupSchemaVerifier(
            factory: factory,
            workspace: Directory('${task.path}/schema'),
          ).verify(
            File(layout.databasePath),
            declaredRows: files.manifest.tables,
            expectedSchema: files.manifest.databaseSchema,
          );
      final content = await LocalBackupContentVerifier(
        factory,
      ).verify(File(layout.databasePath), files.manifest, facts);
      final current = await control.readState();
      if (!current.observation.canAcknowledgeApplied ||
          current.pointerRaw != selected.pointerRaw ||
          current.intentRaw != selected.intentRaw) {
        throw StateError('Applied result changed during read-only review');
      }
      return ReviewedLocalAppliedBackup._(
        intent,
        files.manifest,
        content,
        12 + utf8.encode(files.manifestRaw).length + files.manifest.totalBytes,
      );
    } finally {
      await task.delete(recursive: true);
    }
  }
}
