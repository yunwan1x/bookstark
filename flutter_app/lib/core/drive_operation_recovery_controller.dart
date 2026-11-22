import 'package:flutter/foundation.dart';
import 'drive_operation_record.dart';
import 'drive_operation_store.dart';
import 'drive_operation_transport.dart';

class DriveOperationReview {
  DriveOperationReview(
    this.recordFingerprint,
    List<DriveOperationObservation> rows,
  ) : observations = List.unmodifiable(rows);
  final String recordFingerprint;
  final List<DriveOperationObservation> observations;
}

class DriveOperationRecoveryController extends ChangeNotifier {
  DriveOperationRecoveryController({
    required this.store,
    required this.transport,
  });
  final DriveOperationStore store;
  final ExactDriveOperationTransport transport;
  DriveOperationRecord? record;
  DriveOperationReview? review;
  bool busy = false,
      ready = false,
      storageUnconfirmed = false,
      serverAcknowledged = false,
      _closed = false;
  String? safeError;
  int _generation = 0;
  bool get blocked => !ready || record != null || storageUnconfirmed;
  void _guard() {
    store.guard();
    if (_closed) throw const DriveOperationRetired();
  }

  void _emit() {
    if (!_closed && store.isCurrent()) notifyListeners();
  }

  Future<void> load() async {
    _guard();
    if (busy) return;
    busy = true;
    ready = false;
    review = null;
    safeError = null;
    _generation++;
    _emit();
    try {
      record = await store.read();
      _guard();
      ready = true;
      storageUnconfirmed = false;
      serverAcknowledged = record?.state == DriveOperationState.acknowledged;
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        storageUnconfirmed = true;
        safeError =
            '无法确认本机记录；文件写入仍暂停。 / Cannot confirm device record. File writes remain paused.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  /// A new explicit action only. Loaded records have no replay API.
  Future<void> beginAndSubmit(DriveOperationRecord pending) async {
    _guard();
    if (busy || blocked || pending.state != DriveOperationState.pending) return;
    final lease = Object();
    try {
      store.acquire(lease);
    } catch (_) {
      safeError = '另一操作正在处理此空间。 / Another operation owns this scope.';
      _emit();
      return;
    }
    busy = true;
    record = pending;
    review = null;
    safeError = null;
    _generation++;
    _emit();
    var claimed = false;
    try {
      await store.insert(pending);
      _guard();
      await transport.execute(
        pending,
        onSubmit: () async {
          _guard();
          await store.claim(pending, lease);
          _guard();
          claimed = true;
          record = pending.withState(DriveOperationState.unknown);
        },
      );
      _guard();
      serverAcknowledged = true;
      await store.acknowledge(pending.withState(DriveOperationState.unknown));
      _guard();
      record = pending.withState(DriveOperationState.acknowledged);
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        // Never infer unsent from a failed durable claim or recover by replaying.
        // Reload actual slot before an explicit end; retain corrupt bytes.
        storageUnconfirmed = true;
        safeError = claimed
            ? '结果未知；不会自动重试，请只读核对。 / Result unknown. Review without retrying.'
            : '提交或本机记录未确认；不会重发，请重新读取记录。 / Submission or device record unconfirmed. Reload without resending.';
      }
    } finally {
      store.release(lease);
      busy = false;
      _emit();
    }
  }

  /// This path records an already received acknowledgment, with NO mutation send.
  Future<void> retryAcknowledgmentStorage() async {
    _guard();
    if (busy || !serverAcknowledged || record == null) return;
    busy = true;
    _emit();
    try {
      final unknown = record!.withState(DriveOperationState.unknown);
      await store.acknowledge(unknown);
      _guard();
      record = unknown.withState(DriveOperationState.acknowledged);
      storageUnconfirmed = false;
      safeError = null;
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        safeError =
            '仅本机确认失败，没有发送文件写请求。 / Device acknowledgment failed. No file write was sent.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> inspect() async {
    _guard();
    if (busy || record == null || !ready || storageUnconfirmed) return;
    final expected = record!, generation = ++_generation;
    busy = true;
    review = null;
    safeError = null;
    _emit();
    try {
      final paths = <String>{
        if (expected.source != null) expected.source!.path,
        if (expected.sourceParent != null) expected.sourceParent!.path,
        if (expected.destination.isNotEmpty) expected.destination,
        if (expected.destinationParent != null)
          expected.destinationParent!.path,
      };
      final observations = <DriveOperationObservation>[];
      for (final path in paths) {
        final value = await transport.observe(path);
        _guard();
        if (generation != _generation ||
            record?.fingerprint != expected.fingerprint) {
          return;
        }
        if (value.path != path) {
          throw const FormatException('Read identity mismatch');
        }
        observations.add(value);
      }
      review = DriveOperationReview(expected.fingerprint, observations);
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        safeError =
            '只读核对失败；权限或网络错误不代表路径不存在。 / Read-only review failed. An error does not mean missing.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> endRecord({
    required String expectedFingerprint,
    required bool explicitlyConfirmed,
  }) async {
    _guard();
    if (busy ||
        !ready ||
        storageUnconfirmed ||
        record == null ||
        !explicitlyConfirmed ||
        record!.fingerprint != expectedFingerprint) {
      return;
    }
    busy = true;
    review = null;
    _generation++;
    _emit();
    try {
      await store.end(record!);
      _guard();
      record = null;
      storageUnconfirmed = false;
      serverAcknowledged = false;
      safeError = null;
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        storageUnconfirmed = true;
        safeError =
            '结束记录未确认；不会撤销或重发操作。 / Ending tracking unconfirmed. No rollback or replay.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    review = null;
    super.dispose();
  }
}
