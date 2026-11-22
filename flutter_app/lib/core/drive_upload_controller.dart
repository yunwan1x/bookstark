import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'attachments.dart';
import 'drive_models.dart';
import 'drive_repository.dart';
import 'drive_source.dart';

enum DriveUploadState {
  pending,
  preparing,
  conflict,
  uploading,
  confirmed,
  reused,
  skipped,
  failed,
  uncertain,
}

enum DriveCollisionAction { overwrite, rename, skip, pause }

class DriveCollisionChoice {
  const DriveCollisionChoice(this.action, {this.name});
  final DriveCollisionAction action;
  final String? name;
}

class DriveUploadEntry {
  DriveUploadEntry._(this.id, this.file, this.name);
  final int id;
  final XFile file;
  String name;
  DriveUploadState state = DriveUploadState.pending;
  String? target, hash, error;
  int? size;
  int sent = 0;
  DriveNode? result;
  bool verifying = false;
  bool get completed =>
      state == DriveUploadState.confirmed || state == DriveUploadState.reused;
}

/// Serial uploads; looking up a collision is read-only. The mutating check/prove
/// protocol is called only after start and explicit overwrite consent.
class DriveUploadController extends ChangeNotifier {
  DriveUploadController(this.repository, {required String directory})
    : _directory = drivePath(directory);
  final DriveRepository repository;
  final _entries = <DriveUploadEntry>[];
  String _directory;
  int _next = 1;
  bool running = false, stopping = false, _closed = false;
  AttachmentCancellation? _cancellation;
  DriveUploadEntry? active;
  String get directory => _directory;
  List<DriveUploadEntry> get entries => List.unmodifiable(_entries);
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void setDirectory(String value) {
    if (running || _entries.any((e) => e.state == DriveUploadState.uncertain)) {
      throw StateError('Resolve pending writes before changing directory');
    }
    _directory = drivePath(value);
    _notify();
  }

  void addFiles(List<XFile> files) {
    if (running || _closed) return;
    for (final file in files) {
      final entry = DriveUploadEntry._(_next++, file, file.name);
      try {
        driveName(entry.name);
      } catch (e) {
        entry.state = DriveUploadState.failed;
        entry.error = '$e';
      }
      _entries.add(entry);
    }
    _notify();
  }

  void remove(DriveUploadEntry entry) {
    if (running || entry.state == DriveUploadState.uncertain) {
      throw StateError('Cannot remove an active or unverified write');
    }
    _entries.remove(entry);
    _notify();
  }

  void stop() {
    stopping = true;
    _cancellation?.cancel();
    _notify();
  }

  Future<void> start({
    required Future<DriveCollisionChoice> Function(DriveUploadEntry, DriveNode)
    onCollision,
  }) async {
    if (running ||
        _closed ||
        _entries.any((e) => e.state == DriveUploadState.uncertain)) {
      return;
    }
    running = true;
    stopping = false;
    _notify();
    try {
      final profile = await repository.profile();
      for (final entry in _entries) {
        if (stopping ||
            _closed ||
            _entries.any((e) => e.state == DriveUploadState.uncertain)) {
          break;
        }
        if (entry.state != DriveUploadState.pending &&
            entry.state != DriveUploadState.conflict) {
          continue;
        }
        active = entry;
        final cancellation = AttachmentCancellation();
        _cancellation = cancellation;
        var attempted = false;
        try {
          entry.state = DriveUploadState.preparing;
          entry.error = null;
          entry.sent = 0;
          _notify();
          final snapshot = await DriveSourceSnapshot.prepare(
            entry.file,
            maxBytes: profile.fileMaxBytes,
            cancellation: cancellation,
          );
          entry.hash = snapshot.hash;
          entry.size = snapshot.size;
          DriveNode? expected;
          while (true) {
            cancellation.check();
            entry.target = driveChild(directory, entry.name);
            final existing = await repository.lookup(
              entry.target!,
              cancellation: cancellation,
            );
            if (existing == null) break;
            entry.state = DriveUploadState.conflict;
            _notify();
            final choice = await onCollision(entry, existing);
            cancellation.check();
            if (choice.action == DriveCollisionAction.skip) {
              entry.state = DriveUploadState.skipped;
              break;
            }
            if (choice.action == DriveCollisionAction.pause) {
              stopping = true;
              break;
            }
            if (choice.action == DriveCollisionAction.rename) {
              entry.name = driveName(choice.name ?? '');
              continue;
            }
            if (existing.directory) {
              throw const FormatException(
                'Cannot overwrite a directory with a file',
              );
            }
            // The exact object shown in the dialog becomes the repository's
            // precondition. A changed ID/hash/public context requires new consent.
            expected = existing;
            break;
          }
          if (entry.state == DriveUploadState.skipped || stopping) continue;
          cancellation.check();
          entry.state = DriveUploadState.uploading;
          attempted = true;
          _notify();
          final progressClock = Stopwatch()..start();
          final result = await repository.upload(
            snapshot,
            target: entry.target!,
            expected: expected,
            cancellation: cancellation,
            onSent: (sent, total) {
              entry.sent = sent;
              if (progressClock.elapsedMilliseconds >= 100 || sent == total) {
                progressClock.reset();
                _notify();
              }
            },
          );
          if (result.node.path != entry.target ||
              result.node.directory ||
              result.node.etag != snapshot.hash ||
              result.node.size != snapshot.size) {
            throw const FormatException(
              'Upload confirmation does not match source',
            );
          }
          entry.result = result.node;
          entry.state = result.deduplicated
              ? DriveUploadState.reused
              : DriveUploadState.confirmed;
        } on DriveConflict catch (e) {
          entry.state = DriveUploadState.conflict;
          entry.error = '$e';
        } catch (e) {
          entry.state = attempted
              ? DriveUploadState.uncertain
              : DriveUploadState.failed;
          entry.error = '$e';
        } finally {
          active = null;
          _cancellation = null;
          _notify();
        }
      }
    } finally {
      running = false;
      stopping = false;
      _notify();
    }
  }

  /// A missing/different file does not prove an old request can no longer commit.
  /// Keep the row uncertain; no automatic POST or retry is exposed here.
  Future<bool> verify(DriveUploadEntry entry) async {
    if (running ||
        !_entries.contains(entry) ||
        entry.state != DriveUploadState.uncertain ||
        entry.verifying) {
      throw StateError('No uncertain upload to verify');
    }
    entry.verifying = true;
    _notify();
    try {
      final node = await repository.lookup(entry.target!);
      if (node == null ||
          node.directory ||
          node.etag != entry.hash ||
          node.size != entry.size) {
        entry.error = '当前文件与本次上传不匹配；旧请求仍可能完成';
        return false;
      }
      // Hash is content identity. Canonical listing confirms the actual target;
      // it does not establish which writer created identical bytes or dedup status.
      entry.result = node;
      entry.state = DriveUploadState.confirmed;
      entry.error = null;
      return true;
    } catch (e) {
      entry.error = '$e';
      rethrow;
    } finally {
      entry.verifying = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _closed = true;
    stop();
    super.dispose();
  }
}
