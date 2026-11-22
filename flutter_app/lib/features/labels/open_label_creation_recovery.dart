import '../../core/label_creation_resolution.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/label_creation_attempt.dart';
import '../../core/label_creation_controller.dart';
import '../../core/label_creation_http_adapter.dart';
import '../../core/label_creation_slot.dart';
import '../../core/label_creation_store.dart';
import 'label_creation_recovery_page.dart';

/// Cold entry loads the account slot read-only. Merely opening recovery cannot
/// allocate a new attempt, infer success by URL, or authorize another POST.
Future<LabelCreationResolution?> openLabelCreationRecovery({
  required BuildContext context,
  required BookstarkClient client,
  required int memberId,
  required String namespace,
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
  LabelCreationController? controller;
  try {
    final slot = LabelCreationSlot(
      scope: adapter.scope,
      read: read,
      write: write,
      remove: remove,
      flush: flush,
      isCurrent: isCurrent,
    );
    final key = await read(slot.metadataKey);
    adapter.guard();
    if (key == null) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: Text(english ? 'Label creation recovery' : '标签创建恢复'),
            content: Text(
              english
                  ? 'No creation recovery record for this account.'
                  : '当前账号没有标签创建恢复记录。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(english ? 'Close' : '关闭'),
              ),
            ],
          ),
        );
      }
      return null;
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
      throw const FormatException('Invalid retained label slot');
    }
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
    if (c.error != null) throw StateError('Retained label record unavailable');
    if (c.record == null) {
      if (!context.mounted) return null;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(english ? 'End recovery record?' : '结束恢复记录？'),
          content: Text(
            english
                ? 'The storage record is incomplete or ended. This does not prove the server did not execute the request. Ending this record deletes no server label.'
                : '记录尚未初始化或已结束，不能证明服务器未执行请求。结束记录不会删除服务器标签。',
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
      adapter.guard();
      if (context.mounted && yes == true) {
        await flush();
        adapter.guard();
        if (await read(store.metadataKey) != null) {
          throw StateError('Record changed; reload first');
        }
        adapter.guard();
        await slot.clear(key);
      }
      return null;
    }
    if (!context.mounted) return null;
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
    if (c.endedDurably) {
      await slot.clear(key);
      return null;
    }
    final record = c.record;
    if (accepted != true ||
        record == null ||
        record.phase != LabelCreationPhase.knownID ||
        c.storageUnconfirmed) {
      return null;
    }
    final actual = await adapter.inspect(record, record.actualId!);
    adapter.guard();
    if (!actual.matchesFrozenInput) {
      throw StateError('Actual label changed; review again');
    }
    return LabelCreationResolution(origin: record.origin!, wire: actual.wire);
  } finally {
    controller?.dispose();
    adapter.retire();
  }
}
