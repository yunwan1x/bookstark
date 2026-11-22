import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'drive_operation_record.dart';
import 'drive_operation_transport.dart';

/// Actual authenticated narrow API adapter; owns cancellation, never UI/session globals.
/// App merge must resolve package api_client to the reviewed notes07 working copy.
class DriveOperationHttpAdapter {
  DriveOperationHttpAdapter({
    required this.client,
    required this.scope,
    required this.isCurrent,
  }) : revision = client.sessionRevision,
       _token = client.exportSession()['token'] {
    if (client.baseUri.toString() != scope.server) {
      throw const FormatException('Drive server scope mismatch');
    }
  }
  final BookstarkClient client;
  final DriveOperationScope scope;
  final bool Function() isCurrent;
  final int revision;
  final String? _token;
  final _abort = Completer<void>();
  bool _closed = false;
  void guard() {
    if (_closed ||
        !isCurrent() ||
        client.sessionRevision != revision ||
        _token == null ||
        _token.isEmpty ||
        client.exportSession()['token'] != _token) {
      throw StateError('Drive scope retired');
    }
  }

  void retire() {
    if (_closed) return;
    _closed = true;
    _abort.complete();
  }

  ExactDriveOperationTransport get transport => ExactDriveOperationTransport(
    prepare: prepare,
    observe: observe,
    isCurrent: () =>
        !_closed &&
        isCurrent() &&
        client.sessionRevision == revision &&
        _token != null &&
        _token.isNotEmpty &&
        client.exportSession()['token'] == _token,
  );
  Future<void> _owner() async {
    guard();
    final root = await client.boundedCurrentOwnerJson(
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    guard();
    final row = root['data'];
    if (row is! Map ||
        row['member_id'] is! int ||
        row['member_id'] != scope.member) {
      throw const FormatException('Drive owner mismatch');
    }
  }

  Future<DriveOperationObservation> observe(String path) async {
    guard();
    if (drivePath(path) != path) {
      throw const FormatException('Canonical read path required');
    }
    final parent = path.isEmpty ? '' : driveParent(path);
    final envelope = await client.boundedDriveListJson(
      parent,
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    guard();
    if (envelope['code'] != 0 || !envelope.containsKey('data')) {
      throw const FormatException('Drive list unavailable');
    }
    final values = envelope['data'];
    // Go ListDAVNodes may encode a successful nil slice as null: explicit success only.
    if (values != null && values is! List) {
      throw const FormatException('Drive list unavailable');
    }
    final list = (values as List?) ?? const [];
    if (list.length > 2000) {
      throw const FormatException('Drive metadata item limit');
    }
    final rows = list.map((row) {
      if (row is! Map) throw const FormatException('Drive metadata required');
      return DriveNode.fromJson(row);
    }).toList();
    if (rows.any((node) => driveParent(node.path) != parent) ||
        rows.map((node) => node.id).toSet().length != rows.length ||
        rows.map((node) => node.name).toSet().length != rows.length) {
      throw const FormatException('Ambiguous drive membership');
    }
    if (path.isEmpty) {
      return DriveOperationObservation(
        path: '',
        state: DriveObservationState.root,
      );
    }
    final matches = rows.where((node) => node.path == path).toList();
    return matches.isEmpty
        ? DriveOperationObservation(
            path: path,
            state: DriveObservationState.missing,
          )
        : DriveOperationObservation(
            path: path,
            state: DriveObservationState.found,
            node: matches.single,
          );
  }

  Future<PreparedDriveOperation> prepare(DriveOperationRecord record) async {
    guard();
    if (record.scope.identity != scope.identity ||
        record.state != DriveOperationState.pending) {
      throw const FormatException('Drive operation mismatch');
    }
    await _owner();
    guard();
    final action = switch (record.kind) {
      DriveOperationKind.mkdir => DriveMutationAction.mkdir,
      DriveOperationKind.rename => DriveMutationAction.rename,
      DriveOperationKind.copy => DriveMutationAction.copy,
      DriveOperationKind.remove => DriveMutationAction.remove,
    };
    final prepared = await client.prepareDriveMutationJson(
      action,
      sourcePath: record.kind == DriveOperationKind.mkdir
          ? record.destinationParent!.path
          : record.source!.path,
      destinationPath:
          record.kind == DriveOperationKind.rename ||
              record.kind == DriveOperationKind.copy
          ? record.destination
          : null,
      name: record.kind == DriveOperationKind.mkdir
          ? driveBasename(record.destination)
          : null,
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    try {
      guard();
      // Auth/CSRF is already prepared. Validate each frozen actual parent/target/source
      // immediately before returning the prepared request, never use a stale UI list.
      final baselines = <String, DriveOperationObservation>{};
      for (final value in [
        record.sourceParent,
        record.destinationParent,
        record.source,
        record.destinationBefore,
      ]) {
        if (value != null) {
          final old = baselines[value.path];
          if (old != null &&
              driveMetadataDigest(old.toJson()) !=
                  driveMetadataDigest(value.toJson())) {
            throw const FormatException('Contradictory drive baseline');
          }
          baselines[value.path] = value;
        }
      }
      for (final baseline in baselines.values) {
        final fresh = await observe(baseline.path);
        guard();
        if (driveMetadataDigest(fresh.toJson()) !=
            driveMetadataDigest(baseline.toJson())) {
          throw const FormatException('Drive source or target changed');
        }
      }
      if (record.destinationBefore?.state == DriveObservationState.found) {
        throw const FormatException('Destination already exists');
      }
      return PreparedDriveOperation(
        recordFingerprint: record.fingerprint,
        scopeIdentity: scope.identity,
        send: () async {
          guard();
          final root = await prepared.sendOnce();
          guard();
          if (root['code'] != 0) {
            throw const FormatException('Drive acknowledgment unavailable');
          }
          if (record.kind == DriveOperationKind.mkdir) {
            final row = root['data'];
            if (row is! Map ||
                row['id'] is! int ||
                (row['id'] as int) <= 0 ||
                row['name'] != driveBasename(record.destination) ||
                row['type'] != 'dir' ||
                (row['path'] != '' && row['path'] != record.destination)) {
              throw const FormatException('Directory receipt mismatch');
            }
          } else if (root.length != 2 ||
              !root.containsKey('message') ||
              root['message'] is! String ||
              (root['message'] as String).isEmpty) {
            // Actual controllers/common.go APIResponse uses the message JSON field.
            throw const FormatException('Drive acknowledgment unavailable');
          }
        },
      );
    } catch (_) {
      prepared.retire();
      rethrow;
    }
  }
}
