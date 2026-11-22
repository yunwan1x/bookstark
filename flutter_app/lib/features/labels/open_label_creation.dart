import '../../core/label_creation_resolution.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/label_creation_attempt.dart';
import '../../core/label_creation_controller.dart';
import '../../core/label_creation_http_adapter.dart';
import '../../core/label_creation_slot.dart';
import '../../core/label_creation_store.dart';
import 'label_creation_recovery_page.dart';

Future<LabelCreationResolution> submitRecoverableLabelCreation({
  required BuildContext context,
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required Map<String, Object?> body,
  required Future<String?> Function(String) read,
  required Future<void> Function(String, String) write,
  required Future<void> Function(String) remove,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  bool english = false,
}) async {
  final adapter = LabelCreationHttpAdapter(
    client: client,
    memberId: memberId,
    namespace: namespace,
    isCurrent: isCurrent,
  );
  final slot = LabelCreationSlot(
    scope: adapter.scope,
    read: read,
    write: write,
    remove: remove,
    flush: flush,
    isCurrent: isCurrent,
  );
  LabelCreationController? controller;
  try {
    final allocation = await slot.open();
    adapter.guard();
    final key = allocation.key;
    final store = LabelCreationStore(
      scope: adapter.scope,
      key: key,
      read: read,
      write: write,
      remove: remove,
      flush: flush,
      isCurrent: isCurrent,
    );
    final c = LabelCreationController(
      store: store,
      prepare: adapter.prepare,
      inspect: adapter.inspect,
    );
    controller = c;
    await c.reload();
    adapter.guard();
    if (c.error != null) {
      throw StateError('Retained creation record unavailable');
    }
    final retained = c.record != null;
    if (c.record == null && !allocation.created) {
      if (!context.mounted) {
        throw StateError('Creation recovery requires an active page');
      }
      await _reviewMissingAllocation(
        context,
        store,
        slot,
        key,
        adapter.guard,
        english,
      );
      throw StateError(
        'Retained allocation requires an explicit new create action',
      );
    }
    if (c.record == null) {
      await c.begin(
        LabelCreationAttempt(scope: adapter.scope, key: key, body: body),
      );
      adapter.guard();
      if (c.error == null) await c.submit();
    }
    adapter.guard();
    if (retained ||
        c.record?.phase != LabelCreationPhase.knownID ||
        c.storageUnconfirmed) {
      if (!context.mounted) {
        throw StateError('Creation result requires recovery');
      }
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LabelCreationRecoveryPage(
            controller: c,
            serverLabel: client.baseUri.toString(),
            initiatorId: memberId,
            english: english,
          ),
        ),
      );
      adapter.guard();
      if (c.record != null && accepted != true) {
        throw StateError('Retained record kept; no result adopted');
      }
    }
    final record = c.record;
    if (record == null) {
      if (c.endedDurably) {
        await slot.clear(key);
      } else {
        if (!context.mounted) {
          throw StateError('Creation recovery requires an active page');
        }
        await _reviewMissingAllocation(
          context,
          store,
          slot,
          key,
          adapter.guard,
          english,
        );
      }
      throw StateError(
        'Recovery record ended or kept; server result was not inferred',
      );
    }
    if (record.phase != LabelCreationPhase.knownID || c.storageUnconfirmed) {
      throw StateError('Creation remains unresolved; it was not replayed');
    }
    final review = await adapter.inspect(record, record.actualId!);
    adapter.guard();
    // Returned current source must still equal this invocation, not an older
    // same-slot draft. Caller can explicitly reopen actual ID if it differs.
    final expected = LabelCreationAttempt(
      scope: adapter.scope,
      key: key,
      body: body,
    );
    if (expected.inputDigest != record.inputDigest ||
        !review.matchesFrozenInput) {
      throw StateError('Retained result differs; open actual ID for review');
    }
    // Inspect contains all fields; return the exact wire row, not a synthetic ID.
    return LabelCreationResolution(origin: record.origin!, wire: review.wire);
  } finally {
    controller?.dispose();
    adapter.retire();
  }
}

Future<void> _reviewMissingAllocation(
  BuildContext context,
  LabelCreationStore store,
  LabelCreationSlot slot,
  String key,
  void Function() guard,
  bool english,
) async {
  guard();
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(english ? 'End recovery record?' : '结束恢复记录？'),
      content: Text(
        english
            ? 'The storage record is incomplete or already ended. This does not prove that the server did not execute the request. No automatic creation will occur.'
            : '记录尚未初始化或已结束。这不能证明服务器未执行请求，不会自动重新创建。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(english ? 'Keep record' : '保留记录'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(english ? 'End record' : '确认结束'),
        ),
      ],
    ),
  );
  guard();
  if (!context.mounted || yes != true) return;
  await store.flush();
  guard();
  if (await store.read(store.metadataKey) != null) {
    throw StateError('Record changed; reload first');
  }
  guard();
  await slot.clear(key);
}
