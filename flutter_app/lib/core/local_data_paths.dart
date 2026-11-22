import 'dart:io';
import 'package:path/path.dart' as paths;
import 'local_draft_namespace.dart';
import 'local_generation_state.dart';

class LocalDataNeedsReview implements Exception {
  const LocalDataNeedsReview(this.observation);
  final LocalGenerationObservation observation;
  @override
  String toString() => 'Local data activation requires read-only review';
}

/// Built from trusted OS-private roots and a validated generation identity.
/// In particular, retain the original legacy database path spelling: HTML and
/// complex recovery scopes already use that spelling as their storage identity.
class LocalDataPaths {
  LocalDataPaths._({
    required this.databasePath,
    required this.privateSupport,
    required this.generationId,
    required this.attachments,
    required this.driveBlobs,
  });
  factory LocalDataPaths.legacy({
    required String databasePath,
    required Directory privateSupport,
  }) {
    _absolute(databasePath);
    _absolute(privateSupport.path);
    final support = Directory(paths.normalize(privateSupport.path));
    return LocalDataPaths._(
      databasePath: paths.normalize(databasePath),
      privateSupport: support,
      generationId: null,
      attachments: Directory(paths.join(support.path, 'attachments')),
      driveBlobs: Directory(paths.join(support.path, 'drive-blobs')),
    );
  }
  factory LocalDataPaths.generation({
    required String id,
    required Directory privateSupport,
  }) {
    LocalDraftNamespace.generation(id);
    _absolute(privateSupport.path);
    final support = Directory(paths.normalize(privateSupport.path));
    final root = paths.join(support.path, 'local-data-v1', 'generations', id);
    return LocalDataPaths._(
      databasePath: paths.join(root, 'database', 'content.db'),
      privateSupport: support,
      generationId: id,
      attachments: Directory(paths.join(root, 'attachments')),
      driveBlobs: Directory(paths.join(root, 'drive-blobs')),
    );
  }
  factory LocalDataPaths.fromObservation({
    required LocalGenerationObservation observation,
    required String legacyDatabasePath,
    required Directory privateSupport,
  }) {
    if (observation.needsReview) throw LocalDataNeedsReview(observation);
    final pointer = observation.pointer;
    return pointer == null
        ? LocalDataPaths.legacy(
            databasePath: legacyDatabasePath,
            privateSupport: privateSupport,
          )
        : LocalDataPaths.generation(
            id: pointer.generation,
            privateSupport: privateSupport,
          );
  }
  final String databasePath;
  final Directory privateSupport, attachments, driveBlobs;
  final String? generationId;
  Directory get controlRoot =>
      Directory(paths.join(privateSupport.path, 'local-data-v1'));
  String get draftNamespace => generationId == null
      ? 'local'
      : LocalDraftNamespace.generation(generationId!);
  static void _absolute(String path) {
    if (!paths.isAbsolute(path) || path.contains('\u0000')) {
      throw const FormatException('Absolute private data root required');
    }
  }
}
