import 'drive_operation_record.dart';

/// Root must implement actual mutation preparation after authentication, CSRF,
/// fixed source/parent/target checks, before POST/DELETE. No legacy repository-call
/// wrapper may claim this is the actual transmission boundary.
/// send must validate the actual successful response for the same operation;
/// a completed preflight/list refresh or swallowed network failure is not an ACK.
/// Root must bind the exact HTTP method/path/body to the frozen record, not accept
/// an arbitrary destination URL. This draft does not implement that HTTP adapter.
class PreparedDriveOperation {
  PreparedDriveOperation({
    required this.recordFingerprint,
    required this.scopeIdentity,
    required this._send,
  });
  final String recordFingerprint, scopeIdentity;
  final Future<void> Function() _send;
  bool _used = false;
  Future<void> sendOnce() {
    if (_used) throw StateError('Cannot replay');
    _used = true;
    return _send();
  }
}

class ExactDriveOperationTransport {
  ExactDriveOperationTransport({
    required this.prepare,
    required this.observe,
    required this.isCurrent,
  });
  final Future<PreparedDriveOperation> Function(DriveOperationRecord) prepare;

  /// Must use bounded authenticated read-only metadata calls; permission/read
  /// errors MUST throw, not become missing. Root path returns explicit root.
  final Future<DriveOperationObservation> Function(String path) observe;
  final bool Function() isCurrent;
  Future<void> execute(
    DriveOperationRecord record, {
    required Future<void> Function() onSubmit,
  }) async {
    if (!isCurrent()) throw StateError('Retired');
    final p = await prepare(record);
    if (!isCurrent() ||
        p.scopeIdentity != record.scope.identity ||
        p.recordFingerprint != record.fingerprint) {
      throw StateError('Preparation identity changed');
    }
    await onSubmit();
    if (!isCurrent()) throw StateError('Retired');
    await p.sendOnce();
  }
}
