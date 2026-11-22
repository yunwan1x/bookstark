import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import 'admin_assets_repository.dart';
import 'admin_files_models.dart';
import 'admin_remote_dav_files_repository.dart';
import 'admin_remote_dav_models.dart';
import 'admin_files_transfer.dart';

enum AdminDavFilesFailure {
  read,
  targetChanged,
  refused,
  unknown,
  ownerLost,
  editor,
  background,
}

class AdminDavFilesController extends ChangeNotifier {
  AdminDavFilesController(this.repository) : path = '.' {
    _ownerTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(checkOwner()),
    );
  }
  final AdminDavFilesRepository repository;
  Timer? _ownerTimer;
  bool _checkingOwner = false;
  Future<void> checkOwner() async {
    if (disposed || busy || suspended || _checkingOwner) return;
    _checkingOwner = true;
    try {
      await repository.pollOwner();
    } catch (error) {
      if (!disposed) {
        _error(error);
        _notify();
      }
    } finally {
      _checkingOwner = false;
    }
  }

  String path;
  AdminDavListing? listing;
  AdminDavEntry? editing;
  AdminFileText? original;
  List<AdminDavListing>? observations;
  AdminFileText? observedText;
  bool observationContentUnavailable = false, observationAbsenceProven = false;
  AdminDavFilesFailure? failure;
  AdminDavFileAction? receipt;
  bool busy = false, dirty = false, suspended = false, disposed = false;
  int generation = 0;
  int _epoch = 0;
  bool get active => !disposed && repository.active;
  bool get canAct =>
      active && !busy && !suspended && repository.unknown == null;
  bool get canEdit => canAct && original != null && editing != null;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  void _error(Object error) {
    failure = switch (error) {
      AdminAssetOwnerLost() => AdminDavFilesFailure.ownerLost,
      AdminAssetTargetChanged() => AdminDavFilesFailure.targetChanged,
      AdminDavFileResultUnknown() ||
      AdminDavFileReviewRequired() => AdminDavFilesFailure.unknown,
      ApiFailure(:final status) when status >= 400 && status < 500 =>
        AdminDavFilesFailure.refused,
      ApiFailure() => AdminDavFilesFailure.read,
      _ => AdminDavFilesFailure.read,
    };
    if (failure == AdminDavFilesFailure.ownerLost ||
        failure == AdminDavFilesFailure.unknown) {
      observedText = null;
      original = null;
      editing = null;
      listing = null;
      observations = null;
      observedText = null;
      observationContentUnavailable = false;
      observationAbsenceProven = false;
      dirty = false;
      generation++;
    }
  }

  Future<bool> _run(Future<void> Function() work) async {
    if (disposed || busy) return false;
    final epoch = _epoch;
    busy = true;
    failure = null;
    _notify();
    try {
      await work();
      return !disposed && epoch == _epoch;
    } catch (error) {
      if (!disposed && epoch == _epoch) _error(error);
      return false;
    } finally {
      if (!disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> load([String? target]) async {
    if (disposed || busy || repository.unknown != null) return false;
    final requested = target ?? path;
    final epoch = _epoch;
    suspended = false;
    observedText = null;
    original = null;
    editing = null;
    dirty = false;
    generation++;
    return _run(() async {
      final result = await repository.list(requested);
      if (disposed || epoch != _epoch) return;
      path = requested;
      listing = result;
    });
  }

  Future<bool> open(AdminDavEntry entry) async {
    if (!canAct) return false;
    final epoch = _epoch;
    return _run(() async {
      final result = await repository.read(entry);
      if (disposed || epoch != _epoch) return;
      original = result;
      editing = entry;
      dirty = false;
      generation++;
    });
  }

  void changed(bool value) {
    if (!canEdit) return;
    dirty = value;
    _notify();
  }

  void editorFailed() {
    if (disposed) return;
    observedText = null;
    original = null;
    editing = null;
    dirty = false;
    generation++;
    failure = AdminDavFilesFailure.editor;
    _notify();
  }

  void closeEditor() {
    if (disposed || busy) return;
    observedText = null;
    original = null;
    editing = null;
    dirty = false;
    generation++;
    _notify();
  }

  Future<bool> submit(AdminDavFilePlan plan, {String? baselineContent}) async {
    if (!canAct) return false;
    receipt = null;
    final epoch = _epoch;
    return _run(() async {
      await repository.submit(plan, baselineContent: baselineContent);
      if (disposed || epoch != _epoch) return;
      receipt = plan.action;
      observedText = null;
      original = null;
      editing = null;
      dirty = false;
      generation++;
      // A confirmed write and a later refresh are separate outcomes.
    });
  }

  Future<bool> observe() async {
    if (disposed || busy || suspended) return false;
    observedText = null;
    observations = null;
    generation++;
    final epoch = _epoch;
    return _run(() async {
      final result = await repository.observeUnknown();
      if (disposed || epoch != _epoch) return;
      observations = result.directories;
      observedText = result.currentText;
      observationContentUnavailable = result.contentUnavailable;
      observationAbsenceProven = result.absenceProven;
      generation++;
    });
  }

  void finishReview() {
    repository.finishUnknownReview();
    observations = null;
    observedText = null;
    observationContentUnavailable = false;
    observationAbsenceProven = false;
    failure = null;
    _notify();
  }

  int transferred = 0, total = 0;
  String? transferPath;
  bool uploading = false, downloading = false;
  void _progress(int epoch, int count, int expected) {
    if (disposed || epoch != _epoch) return;
    transferred = count;
    total = expected;
    _notify();
  }

  Future<AdminDownloadedFile?> download(AdminDavEntry entry) async {
    if (!canAct) return null;
    final epoch = _epoch;
    AdminDownloadedFile? result;
    transferPath = entry.path;
    downloading = true;
    transferred = 0;
    total = entry.size;
    final ok = await _run(() async {
      result = await repository.download(
        entry,
        onReceived: (count, total) => _progress(epoch, count, total),
      );
    });
    downloading = false;
    if (!ok) {
      await result?.close();
      _notify();
      return null;
    }
    _notify();
    return result;
  }

  Future<bool> upload(String name, int length, Stream<List<int>> bytes) async {
    if (!canAct) return false;
    final epoch = _epoch;
    transferPath = adminDavJoin(path, name);
    receipt = null;
    uploading = true;
    transferred = 0;
    total = length;
    final ok = await _run(() async {
      await repository.upload(
        path,
        name,
        length,
        bytes,
        onSent: (count, total) => _progress(epoch, count, total),
      );
      if (!disposed && epoch == _epoch) receipt = AdminDavFileAction.upload;
    });
    uploading = false;
    _notify();
    return ok;
  }

  void suspend() {
    if (disposed) return;
    _epoch++;
    generation++;
    suspended = true;
    uploading = false;
    downloading = false;
    transferPath = null;
    observedText = null;
    original = null;
    editing = null;
    listing = null;
    observations = null;
    observedText = null;
    observationContentUnavailable = false;
    observationAbsenceProven = false;
    dirty = false;
    failure = AdminDavFilesFailure.background;
    repository.cancel();
    _notify();
  }

  void resumeForReview() {
    if (disposed || busy) return;
    suspended = false;
    if (failure == AdminDavFilesFailure.background) failure = null;
    _notify();
  }

  @override
  void dispose() {
    if (disposed) return;
    _ownerTimer?.cancel();
    disposed = true;
    uploading = false;
    downloading = false;
    transferPath = null;
    _epoch++;
    generation++;
    repository.dispose();
    observedText = null;
    original = null;
    editing = null;
    listing = null;
    observations = null;
    observedText = null;
    observationContentUnavailable = false;
    observationAbsenceProven = false;
    super.dispose();
  }
}
