import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/api_client.dart';
import 'admin_asset_models.dart';
import 'admin_assets_repository.dart';
import 'admin_assets_scope.dart';
import 'admin_files_models.dart';
import 'admin_files_transfer.dart';

class AdminFileResultUnknown implements Exception {
  const AdminFileResultUnknown();
  @override
  String toString() => 'Remote file result unknown; review without replay';
}

class AdminFileReviewRequired implements Exception {
  const AdminFileReviewRequired();
}

final class AdminFileUnknown {
  AdminFileUnknown(AdminFileWritePlan plan)
    : action = plan.action,
      path = plan.path,
      target = plan.target;
  final AdminFileAction action;
  final String path;
  final String? target;
  bool observationRead = false;
}

/// Owns requests, never plaintext credentials. No write retry or compensation.
class AdminFilesRepository {
  AdminFilesRepository(this.scope, this.host, {this.cacheDirectory})
    : assets = AdminAssetsRepository(scope.client);
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final AdminAssetsRepository assets;
  final Future<Directory> Function()? cacheDirectory;
  Completer<void>? _abort;
  bool _disposed = false, _busy = false;
  AdminFileUnknown? unknown;
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
    try {
      final rows = await assets.readHosts(
        scope.owner,
        abortTrigger: _abort?.future,
      );
      _guard();
      final matches = rows.where((row) => row.id == host.id).toList();
      if (matches.length != 1 ||
          matches.single.reviewFingerprint != host.reviewFingerprint) {
        throw const AdminAssetTargetChanged();
      }
      final principal = await scope.client.adminAssetPrincipalJson(
        abortTrigger: _abort?.future,
      );
      _guard();
      if (principal['member_id'] != scope.owner.memberId ||
          principal['account'] != scope.owner.account ||
          principal['role'] != 0) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
    } on ApiFailure catch (error) {
      if ({401, 403}.contains(error.status)) {
        scope.close();
        throw AdminAssetOwnerLost();
      }
      rethrow;
    } on AdminAssetOwnerLost {
      scope.close();
      rethrow;
    }
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

  Future<AdminFileListing> _list(String path) async {
    adminFilePath(path);
    final raw = await scope.client.adminRemoteFilesJson(
      host.id,
      query: {'path': path},
      abortTrigger: _abort?.future,
    );
    _guard();
    return AdminFileListing.parse(path, raw);
  }

  Future<AdminFileListing> list(String path) => _operation(() => _list(path));

  Future<AdminFileEntry> _fresh(AdminFileEntry baseline) async {
    final listing = await _list(adminFileParent(baseline.path));
    final current = listing.find(baseline.path);
    if (current == null || current.fingerprint != baseline.fingerprint) {
      throw const AdminAssetTargetChanged();
    }
    return current;
  }

  Future<AdminFileText> _text(String path) async {
    final raw = await scope.client.adminRemoteFilesJson(
      host.id,
      operation: 'read',
      query: {'path': path},
      abortTrigger: _abort?.future,
    );
    _guard();
    return AdminFileText.parse(path, raw);
  }

  Future<AdminFileText> read(AdminFileEntry entry) => _operation(() async {
    if (entry.type != AdminFileType.file || entry.size > adminFileTextLimit) {
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
    final listing = await _list(adminFileParent(path));
    if (listing.truncated || listing.find(path) != null) {
      throw const AdminAssetTargetChanged();
    }
  }

  Future<void> submit(
    AdminFileWritePlan plan, {
    String? baselineContent,
  }) => _operation(() async {
    if (unknown != null) throw const AdminFileReviewRequired();
    if (plan.baseline != null) await _fresh(plan.baseline!);
    if (plan.action == AdminFileAction.save) {
      if (baselineContent == null) {
        throw const FormatException('Original text required');
      }
      final current = await _text(plan.path);
      if (current.content != baselineContent) {
        throw const AdminAssetTargetChanged();
      }
      await _fresh(plan.baseline!);
    }
    if (plan.action == AdminFileAction.mkdir) await _requireAbsent(plan.path);
    if (plan.target != null) await _requireAbsent(plan.target!);
    // Final fresh identity/host check immediately before dispatch.
    await _verify();
    final body = switch (plan.action) {
      AdminFileAction.save => {'path': plan.path, 'content': plan.content!},
      AdminFileAction.mkdir => {'path': plan.path},
      AdminFileAction.rename => {
        'old_path': plan.path,
        'new_path': plan.target!,
      },
      AdminFileAction.copy => {
        'source_path': plan.path,
        'target_path': plan.target!,
      },
      AdminFileAction.chmod => {'path': plan.path, 'mode': plan.mode!},
      AdminFileAction.delete => null,
      AdminFileAction.upload => throw const FormatException(
        'Use upload transport',
      ),
    };
    var submitted = false;
    try {
      await scope.client.adminRemoteFilesJson(
        host.id,
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
        unknown = AdminFileUnknown(plan);
        throw const AdminFileResultUnknown();
      }
      rethrow;
    }
  });

  /// An observation is not a receipt for the previous write.
  Future<AdminFileObservation> observeUnknown() => _operation(() async {
    final pending = unknown;
    if (pending == null) throw const AdminFileReviewRequired();
    pending.observationRead = false;
    final paths = {
      adminFileParent(pending.path),
      if (pending.target != null) adminFileParent(pending.target!),
    };
    final results = <AdminFileListing>[];
    for (final path in paths) {
      results.add(await _list(path));
    }
    _guard();
    if (!identical(unknown, pending)) throw const AdminFileReviewRequired();
    AdminFileText? currentText;
    var unavailable = false, absenceProven = false;
    if (pending.action == AdminFileAction.save) {
      final parent = results.firstWhere(
        (list) => list.path == adminFileParent(pending.path),
      );
      final current = parent.find(pending.path);
      absenceProven = current == null && !parent.truncated;
      if (current != null &&
          current.type == AdminFileType.file &&
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
        pending.action != AdminFileAction.save ||
        currentText != null ||
        absenceProven;
    return AdminFileObservation(
      directories: List.unmodifiable(results),
      currentText: currentText,
      contentUnavailable: unavailable,
      absenceProven: absenceProven,
    );
  });

  void finishUnknownReview() {
    _guard();
    if (unknown?.observationRead != true) throw const AdminFileReviewRequired();
    unknown = null;
  }

  Future<AdminDownloadedFile> download(
    AdminFileEntry entry, {
    void Function(int, int)? onReceived,
  }) => _operation(() async {
    if (entry.type != AdminFileType.file ||
        entry.size > adminFileTransferLimit) {
      throw const FormatException('Unsupported remote download');
    }
    await _fresh(entry);
    AdminDownloadedFile? result;
    try {
      result = await scope.client.adminDownloadRemoteFile(
        host.id,
        entry.path,
        abortTrigger: _abort?.future,
        consume: (response, abort) => receiveAdminFile(
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
    if (unknown != null) throw const AdminFileReviewRequired();
    adminFileName(name);
    final path = adminFileJoin(directory, name);
    final plan = AdminFileWritePlan(action: AdminFileAction.upload, path: path);
    if (length < 0 || length > adminFileTransferLimit) {
      throw const FormatException('Upload exceeds local limit');
    }
    await _requireAbsent(path);
    await _verify();
    var submitted = false;
    try {
      final result = await scope.client.adminUploadRemoteFile(
        host.id,
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
        unknown = AdminFileUnknown(plan);
        throw const AdminFileResultUnknown();
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
    final ownerAbort = _ownerAbort;
    if (ownerAbort != null && !ownerAbort.isCompleted) ownerAbort.complete();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    assets.dispose();
    unknown = null;
  }
}
