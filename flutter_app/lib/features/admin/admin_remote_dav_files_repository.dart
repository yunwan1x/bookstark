import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/api_client.dart';
import 'admin_assets_repository.dart';
import 'admin_remote_dav_repository.dart';
import 'admin_remote_dav_models.dart';
import 'admin_remote_dav_transfer.dart';
import 'admin_assets_scope.dart';
import 'admin_files_models.dart';
import 'admin_files_transfer.dart';

class AdminDavFileResultUnknown implements Exception {
  const AdminDavFileResultUnknown();
  @override
  String toString() => 'Remote file result unknown; review without replay';
}

class AdminDavFileReviewRequired implements Exception {
  const AdminDavFileReviewRequired();
}

final class AdminDavFileUnknown {
  AdminDavFileUnknown(AdminDavFilePlan plan)
    : action = plan.action,
      path = plan.path,
      target = plan.target;
  final AdminDavFileAction action;
  final String path;
  final String? target;
  bool observationRead = false;
}

/// Owns requests, never plaintext credentials. No write retry or compensation.
class AdminDavFilesRepository {
  AdminDavFilesRepository(this.scope, this.binding, {this.cacheDirectory})
    : catalog = AdminDavRepository(scope);
  final AdminAssetsScope scope;
  final AdminDavBinding binding;
  final AdminDavRepository catalog;
  final Future<Directory> Function()? cacheDirectory;
  Completer<void>? _abort;
  bool _disposed = false, _busy = false;
  AdminDavFileUnknown? unknown;
  bool get active => !_disposed && scope.active;

  void _guard() {
    if (!active) {
      if (!_disposed) scope.guard();
      throw AdminAssetOwnerLost();
    }
    if (_abort?.isCompleted == true) throw AdminAssetReadSuperseded();
  }

  Future<void> _verify() async {
    _guard();
    await catalog.verifyBinding(binding);
    _guard();
  }

  Future<T> _operation<T>(Future<T> Function() action) async {
    _guard();
    if (_busy) throw const AdminAssetOperationBusy();
    _busy = true;
    final abort = Completer<void>();
    _abort = abort;
    try {
      await _verify();
      final result = await action();
      _guard();
      return result;
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
      _busy = false;
    }
  }

  Future<AdminDavListing> _list(String path) async {
    adminDavPath(path);
    final raw = await scope.client.adminDavFilesJson(
      binding.server.id,
      query: {'path': path},
      abortTrigger: _abort?.future,
    );
    _guard();
    return AdminDavListing.parse(Map<String, dynamic>.from(raw), path);
  }

  Future<AdminDavListing> list(String path) => _operation(() => _list(path));

  Future<AdminDavEntry> _fresh(AdminDavEntry baseline) async {
    final listing = await _list(adminDavParent(baseline.path));
    final current = listing.find(baseline.path);
    if (current == null || current.fingerprint != baseline.fingerprint) {
      throw const AdminAssetTargetChanged();
    }
    return current;
  }

  Future<AdminFileText> _text(String path) async {
    final raw = await scope.client.adminDavFilesJson(
      binding.server.id,
      operation: 'read',
      query: {'path': path},
      abortTrigger: _abort?.future,
    );
    _guard();
    return AdminFileText.parse(path, raw);
  }

  Future<AdminFileText> read(AdminDavEntry entry) => _operation(() async {
    if (entry.type != AdminDavEntryType.file ||
        entry.size > adminFileTextLimit) {
      throw const FormatException('Remote entry is not editable text');
    }
    await _fresh(entry);
    final text = await _text(entry.path);
    if (utf8.encode(text.content).length != entry.size) {
      throw const AdminAssetTargetChanged();
    }
    await _fresh(entry);
    return text;
  });

  Future<void> _requireAbsent(String path) async {
    final listing = await _list(adminDavParent(path));
    if (listing.truncated || listing.find(path) != null) {
      throw const AdminAssetTargetChanged();
    }
  }

  Future<void> submit(
    AdminDavFilePlan plan, {
    String? baselineContent,
  }) => _operation(() async {
    if (unknown != null) throw const AdminDavFileReviewRequired();
    if (plan.baseline != null) await _fresh(plan.baseline!);
    if (plan.action == AdminDavFileAction.save) {
      if (baselineContent == null) {
        throw const FormatException('Original text required');
      }
      final current = await _text(plan.path);
      if (current.content != baselineContent) {
        throw const AdminAssetTargetChanged();
      }
      await _fresh(plan.baseline!);
    }
    if (plan.action == AdminDavFileAction.mkdir) {
      await _requireAbsent(plan.path);
    }
    if (plan.target != null) await _requireAbsent(plan.target!);
    // Final fresh identity/host check immediately before dispatch.
    await _verify();
    final body = switch (plan.action) {
      AdminDavFileAction.save => {'path': plan.path, 'content': plan.content!},
      AdminDavFileAction.mkdir => {'path': plan.path},
      AdminDavFileAction.rename => {
        'old_path': plan.path,
        'new_path': plan.target!,
      },
      AdminDavFileAction.copy => {
        'source_path': plan.path,
        'target_path': plan.target!,
      },
      AdminDavFileAction.delete => null,
      AdminDavFileAction.upload => throw const FormatException(
        'Use upload transport',
      ),
    };
    var submitted = false;
    try {
      await scope.client.adminDavFilesJson(
        binding.server.id,
        operation: plan.action.name,
        body: body,
        query: body == null
            ? {'path': plan.path, 'recursive': '${plan.recursive}'}
            : {},
        abortTrigger: _abort?.future,
        onSubmitted: () => submitted = true,
      );
      _guard();
    } catch (error) {
      if (!active) throw AdminAssetOwnerLost();
      if (error is ApiFailure && {401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      if (submitted &&
          !(error is ApiFailure && error.status >= 400 && error.status < 500)) {
        unknown = AdminDavFileUnknown(plan);
        throw const AdminDavFileResultUnknown();
      }
      rethrow;
    }
  });

  /// An observation is not a receipt for the previous write.
  Future<AdminDavFileObservation> observeUnknown() => _operation(() async {
    final pending = unknown;
    if (pending == null) throw const AdminDavFileReviewRequired();
    pending.observationRead = false;
    final paths = {
      adminDavParent(pending.path),
      if (pending.target != null) adminDavParent(pending.target!),
    };
    final results = <AdminDavListing>[];
    for (final path in paths) {
      results.add(await _list(path));
    }
    _guard();
    if (!identical(unknown, pending)) throw const AdminDavFileReviewRequired();
    AdminFileText? currentText;
    var unavailable = false, absenceProven = false;
    if (pending.action == AdminDavFileAction.save) {
      final parent = results.firstWhere(
        (list) => list.path == adminDavParent(pending.path),
      );
      final current = parent.find(pending.path);
      absenceProven = current == null && !parent.truncated;
      if (current != null &&
          current.type == AdminDavEntryType.file &&
          current.size <= adminFileTextLimit) {
        try {
          currentText = await _text(current.path);
          if (utf8.encode(currentText.content).length != current.size) {
            throw const AdminAssetTargetChanged();
          }
          await _fresh(current);
        } on ApiFailure catch (error) {
          if ({401, 403}.contains(error.status)) rethrow;
          unavailable = true;
        } on FormatException {
          unavailable = true;
        }
      } else if (!absenceProven) {
        unavailable = true;
      }
    }
    _guard();
    pending.observationRead =
        pending.action != AdminDavFileAction.save ||
        currentText != null ||
        absenceProven;
    return AdminDavFileObservation(
      directories: List.unmodifiable(results),
      currentText: currentText,
      contentUnavailable: unavailable,
      absenceProven: absenceProven,
    );
  });

  void finishUnknownReview() {
    _guard();
    if (unknown?.observationRead != true) {
      throw const AdminDavFileReviewRequired();
    }
    unknown = null;
  }

  Future<AdminDownloadedFile> download(
    AdminDavEntry entry, {
    void Function(int, int)? onReceived,
  }) => _operation(() async {
    if (entry.type != AdminDavEntryType.file ||
        entry.size > adminFileTransferLimit) {
      throw const FormatException('Unsupported remote download');
    }
    await _fresh(entry);
    AdminDownloadedFile? result;
    try {
      result = await scope.client.adminDownloadDavFile(
        binding.server.id,
        entry.path,
        abortTrigger: _abort?.future,
        consume: (response, abort) => receiveAdminDavFile(
          response,
          entry,
          abort,
          onReceived: onReceived,
          cacheDirectory: cacheDirectory,
        ),
      );
      _guard();
      await _fresh(entry);
      return result!;
    } catch (_) {
      await result?.close();
      rethrow;
    }
  });

  Future<void> upload(
    String directory,
    String name,
    int length,
    Stream<List<int>> bytes, {
    void Function(int, int)? onSent,
  }) => _operation(() async {
    if (unknown != null) throw const AdminDavFileReviewRequired();
    adminFileName(name);
    final path = adminDavJoin(directory, name);
    final plan = AdminDavFilePlan(
      action: AdminDavFileAction.upload,
      path: path,
    );
    if (length < 0 || length > adminFileTransferLimit) {
      throw const FormatException('Upload exceeds local limit');
    }
    await _requireAbsent(path);
    await _verify();
    var submitted = false;
    try {
      final result = await scope.client.adminUploadDavFile(
        binding.server.id,
        directory,
        filename: name,
        length: length,
        bytes: bytes,
        abortTrigger: _abort?.future,
        onSubmitted: () => submitted = true,
        onSent: onSent,
      );
      _guard();
      if (result['path'] != path) {
        throw const FormatException('Upload receipt target differs');
      }
    } catch (error) {
      if (!active) throw AdminAssetOwnerLost();
      if (error is ApiFailure && {401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      if (submitted &&
          !(error is ApiFailure && error.status >= 400 && error.status < 500)) {
        unknown = AdminDavFileUnknown(plan);
        throw const AdminDavFileResultUnknown();
      }
      rethrow;
    }
  });

  Completer<void>? _ownerAbort;
  Future<void> pollOwner() async {
    if (!active) {
      scope.guard();
      throw AdminAssetOwnerLost();
    }
    if (_ownerAbort != null) return;
    final abort = Completer<void>();
    _ownerAbort = abort;
    try {
      final profile = await scope.client.adminAssetPrincipalJson(
        abortTrigger: abort.future,
      );
      if (!active) throw AdminAssetOwnerLost();
      if (profile['member_id'] != scope.owner.memberId ||
          profile['account'] != scope.owner.account ||
          profile['role'] != 0) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_ownerAbort, abort)) _ownerAbort = null;
    }
  }

  void cancel() {
    catalog.background();
    final ownerAbort = _ownerAbort;
    if (ownerAbort != null && !ownerAbort.isCompleted) ownerAbort.complete();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    catalog.dispose();
    unknown = null;
  }
}
