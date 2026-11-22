import 'package:flutter/material.dart';
import '../../core/drive_repository.dart';
import '../../core/file_draft_vault.dart';
import 'drive_page.dart';

/// Owns the file repository while borrowing global auth, SQLite and draft store.
class DriveFeature extends StatefulWidget {
  const DriveFeature({
    super.key,
    required this.createRepository,
    required this.vault,
    this.beforePlay,
    this.pageBuilder,
  });
  final Widget Function(DriveRepository, FileDraftVault)? pageBuilder;
  final DriveRepository Function() createRepository;
  final FileDraftVault vault;
  final Future<void> Function()? beforePlay;
  @override
  State<DriveFeature> createState() => _DriveFeatureState();
}

class _DriveFeatureState extends State<DriveFeature> {
  late final repository = widget.createRepository();
  @override
  void dispose() {
    repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.pageBuilder?.call(repository, widget.vault) ??
      DrivePage(
        repository: repository,
        vault: widget.vault,
        beforePlay: widget.beforePlay,
      );
}
