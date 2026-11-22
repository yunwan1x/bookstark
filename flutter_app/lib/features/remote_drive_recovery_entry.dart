import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_repository.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/features/drive/drive_page.dart';
import '../core/drive_operation_record.dart';
import '../core/drive_operation_store.dart';
import '../core/drive_operation_recovery_controller.dart';
import '../core/drive_operation_http_adapter.dart';
import 'drive_operation_recovery_page.dart';

final _driveEntryOwners = <String>{};
Future<Widget> createRemoteDriveRecoveryEntry({
  required BookstarkClient client,
  required DriveOperationScope scope,
  required DriveRepository repository,
  required FileDraftVault vault,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  Future<void> Function()? beforePlay,
  bool english = false,
}) async {
  if (client.baseUri.toString() != scope.server) {
    throw StateError('Drive server mismatch');
  }
  if (repository.local || !_driveEntryOwners.add(scope.identity)) {
    throw StateError('Remote drive entry unavailable');
  }
  final revision = client.sessionRevision,
      token = client.exportSession()['token'];
  bool current() =>
      isCurrent() &&
      client.sessionRevision == revision &&
      token != null &&
      token.isNotEmpty &&
      client.exportSession()['token'] == token;
  final adapter = DriveOperationHttpAdapter(
    client: client,
    scope: scope,
    isCurrent: current,
  );
  final store = DriveOperationStore(
    scope: scope,
    readValue: readValue,
    writeValue: writeValue,
    deleteValue: deleteValue,
    flush: flush,
    isCurrent: current,
  );
  final c = DriveOperationRecoveryController(
    store: store,
    transport: adapter.transport,
  );
  try {
    await c.load(); // absence requires store's genuine native flush first
    if (!current()) throw StateError('Drive owner retired');
    final bridge = RetainedRemoteDriveRepository(
      underlying: repository,
      controller: c,
      adapter: adapter,
      current: current,
    );
    var retired = false;
    void retireOwned() {
      if (retired) return;
      retired = true;
      bridge.dispose();
      adapter.retire();
      c.dispose();
      _driveEntryOwners.remove(scope.identity);
    }

    return _RemoteDriveEntry(
      controller: c,
      adapter: adapter,
      repository: bridge,
      vault: vault,
      beforePlay: beforePlay,
      current: current,
      english: english,
      release: retireOwned,
    );
  } catch (_) {
    adapter.retire();
    c.dispose();
    _driveEntryOwners.remove(scope.identity);
    rethrow;
  }
}

class RetainedRemoteDriveRepository extends DriveRepository {
  RetainedRemoteDriveRepository({
    required this.underlying,
    required this.controller,
    required this.adapter,
    required this.current,
  });
  final DriveRepository underlying;
  final DriveOperationRecoveryController controller;
  final DriveOperationHttpAdapter adapter;
  final bool Function() current;
  bool _closed = false, _mutating = false;
  final _calls = <AttachmentCancellation>{};
  void guard() {
    if (_closed || !current()) throw StateError('Drive scope retired');
  }

  @override
  bool get local => false;
  Future<T> work<T>(
    Future<T> Function(AttachmentCancellation) call,
    AttachmentCancellation? external,
  ) async {
    guard();
    external?.check();
    final token = AttachmentCancellation();
    _calls.add(token);
    if (external != null) {
      unawaited(external.signal.then((_) => token.cancel()));
    }
    try {
      final result = await call(token);
      guard();
      token.check();
      return result;
    } finally {
      _calls.remove(token);
    }
  }

  Future<void> mutate(
    DriveOperationKind kind, {
    DriveNode? source,
    String destination = '',
    AttachmentCancellation? cancellation,
  }) async {
    guard();
    cancellation?.check();
    if (_mutating || controller.busy || controller.blocked) {
      throw StateError('Resolve the retained drive operation first');
    }
    _mutating = true;
    try {
      DriveOperationObservation? actual, parent, targetParent, target;
      if (source != null) {
        actual = await adapter.observe(source.path);
        guard();
        cancellation?.check();
        if (actual.state != DriveObservationState.found ||
            driveMetadataDigest(driveNodeMetadata(actual.node!)) !=
                driveMetadataDigest(driveNodeMetadata(source))) {
          throw DriveConflict(source, actual.node);
        }
        parent = await adapter.observe(driveParent(source.path));
        guard();
        cancellation?.check();
      }
      if (destination.isNotEmpty) {
        targetParent = await adapter.observe(driveParent(destination));
        guard();
        cancellation?.check();
        target = await adapter.observe(destination);
        guard();
        cancellation?.check();
        if (target.state != DriveObservationState.missing) {
          throw StateError('Destination already exists');
        }
      }
      final key = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final pending = DriveOperationRecord(
        scope: adapter.scope,
        key: key,
        kind: kind,
        state: DriveOperationState.pending,
        source: actual,
        sourceParent: parent,
        destination: destination,
        destinationParent: targetParent,
        destinationBefore: target,
        createdAt: DateTime.now().toUtc(),
      );
      guard();
      cancellation?.check();
      await controller.beginAndSubmit(pending);
      guard();
      if (controller.record?.key != key ||
          !controller.serverAcknowledged ||
          controller.record?.state != DriveOperationState.acknowledged) {
        throw StateError('Drive result retained for review');
      }
    } finally {
      _mutating = false;
    }
  }

  @override
  Future<DriveNode> mkdir(
    String parent,
    String name, {
    AttachmentCancellation? cancellation,
  }) async {
    final target = driveChild(parent, name);
    await mutate(
      DriveOperationKind.mkdir,
      destination: target,
      cancellation: cancellation,
    );
    final observed = await adapter.observe(target);
    guard();
    if (observed.state != DriveObservationState.found ||
        !observed.node!.directory) {
      throw StateError(
        'Directory acknowledgment retained; refresh without retrying',
      );
    }
    return observed.node!;
  }

  @override
  Future<void> rename(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => mutate(
    DriveOperationKind.rename,
    source: source,
    destination: drivePath(target),
    cancellation: cancellation,
  );
  @override
  Future<void> copy(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => mutate(
    DriveOperationKind.copy,
    source: source,
    destination: drivePath(target),
    cancellation: cancellation,
  );
  @override
  Future<void> remove(
    DriveNode source, {
    AttachmentCancellation? cancellation,
  }) => mutate(
    DriveOperationKind.remove,
    source: source,
    cancellation: cancellation,
  );
  @override
  Future<DriveProfile> profile({AttachmentCancellation? cancellation}) =>
      work((token) => underlying.profile(cancellation: token), cancellation);
  @override
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  }) =>
      work((token) => underlying.list(path, cancellation: token), cancellation);
  @override
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  }) async {
    guard();
    cancellation?.check();
    final token = AttachmentCancellation();
    _calls.add(token);
    if (cancellation != null) {
      unawaited(cancellation.signal.then((_) => token.cancel()));
    }
    try {
      final value = await underlying.open(
        file,
        range: range,
        ifRange: ifRange,
        cancellation: token,
      );
      guard();
      token.check();
      Stream<List<int>> body() async* {
        try {
          await for (final chunk in value.stream) {
            guard();
            token.check();
            yield chunk;
          }
        } finally {
          _calls.remove(token);
        }
      }

      return DriveRead(
        stream: body(),
        status: value.status,
        headers: value.headers,
        length: value.length,
      );
    } catch (_) {
      token.cancel();
      _calls.remove(token);
      rethrow;
    }
  }

  @override
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) => work(
    (token) => underlying.upload(
      source,
      target: target,
      expected: expected,
      cancellation: token,
      onSent: (a, b) {
        if (!_closed && current()) onSent?.call(a, b);
      },
    ),
    cancellation,
  );
  @override
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  }) => work(
    (token) => underlying.saveText(document, content, cancellation: token),
    cancellation,
  );
  @override
  Future<Uri> publish(
    DriveNode file,
    String publicPath, {
    AttachmentCancellation? cancellation,
  }) => work(
    (token) => underlying.publish(file, publicPath, cancellation: token),
    cancellation,
  );
  @override
  Future<void> unpublish(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  }) => work(
    (token) => underlying.unpublish(file, cancellation: token),
    cancellation,
  );
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final token in _calls.toList()) {
      token.cancel();
    }
  }
}

class _RemoteDriveEntry extends StatefulWidget {
  const _RemoteDriveEntry({
    required this.controller,
    required this.adapter,
    required this.repository,
    required this.vault,
    required this.current,
    required this.english,
    required this.release,
    this.beforePlay,
  });
  final DriveOperationRecoveryController controller;
  final DriveOperationHttpAdapter adapter;
  final RetainedRemoteDriveRepository repository;
  final FileDraftVault vault;
  final bool Function() current;
  final bool english;
  final VoidCallback release;
  final Future<void> Function()? beforePlay;
  @override
  State<_RemoteDriveEntry> createState() => _RemoteDriveEntryState();
}

class _RemoteDriveEntryState extends State<_RemoteDriveEntry> {
  int epoch = 0;
  String? prior;
  @override
  void initState() {
    super.initState();
    prior = widget.controller.record?.key;
    widget.controller.addListener(changed);
  }

  void changed() {
    final next = widget.controller.record?.key;
    if (prior != null && next == null) {
      epoch++; // clears legacy volatile uncertainty only after explicit EndRecord
    }
    prior = next;
    if (mounted && widget.current()) setState(() {});
  }

  Future<void> review() async {
    if (!widget.current()) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DriveOperationRecoveryPage(
          controller: widget.controller,
          english: widget.english,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    widget.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!widget.current()) {
      return const Scaffold(body: Center(child: Text('Space changed')));
    }
    return Column(
      children: [
        if (c.blocked || c.busy)
          SafeArea(
            bottom: false,
            child: Material(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(
                      widget.english
                          ? 'A retained operation blocks folder changes.'
                          : '保留操作记录阻止继续修改文件夹。',
                    ),
                    TextButton(
                      onPressed: c.busy ? null : review,
                      child: Text(
                        widget.english ? 'Review retained operation' : '核对保留操作',
                      ),
                    ),
                    if (!c.ready)
                      TextButton(
                        onPressed: c.busy ? null : c.load,
                        child: Text(widget.english ? 'Reload record' : '重读记录'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: DrivePage(
            key: ValueKey(epoch),
            repository: widget.repository,
            vault: widget.vault,
            beforePlay: widget.beforePlay,
            mutationBlocked: () => c.blocked || c.busy,
          ),
        ),
      ],
    );
  }
}

/// Retire a prepared page if its route was abandoned before mounting.
void retireRemoteDriveEntry(Widget page) {
  if (page is _RemoteDriveEntry) page.release();
}
