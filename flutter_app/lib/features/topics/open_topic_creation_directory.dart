import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/topic_creation_controller.dart';
import '../../core/topic_creation_directory.dart';
import '../../core/topic_creation_http_adapter.dart';
import '../../core/topic_creation_metadata.dart';
import '../../core/topic_creation_slot.dart';
import '../../core/topic_creation_store.dart';
import '../../core/topic_creation_attempt.dart';
import 'topic_creation_directory_page.dart';
import 'topic_creation_recovery_page.dart';

Future<void> openTopicCreationDirectory({
  required BuildContext context,
  required BookstarkClient client,
  required int memberId,
  required String namespace,
  required bool Function() isCurrent,
  required Future<Object?> Function() metadata,
  required Future<String?> Function(String) read,
  required Future<void> Function(String, String) write,
  required Future<void> Function(String) remove,
  required Future<void> Function() flush,
  bool english = false,
}) async {
  final adapter = TopicCreationHttpAdapter(
    client: client,
    memberId: memberId,
    namespace: namespace,
    isCurrent: isCurrent,
  );
  final directory = TopicCreationDirectory(
    scope: adapter.scope,
    metadata: metadata,
    read: read,
    isCurrent: () => isCurrent() && client.sessionRevision == adapter.revision,
  );
  Future<void> open(
    BuildContext routeContext,
    TopicCreationDirectoryEntry entry,
  ) async {
    adapter.guard();
    final store = TopicCreationStore(
      scope: adapter.scope,
      key: entry.attemptKey,
      read: read,
      write: write,
      remove: remove,
      flush: flush,
      isCurrent: directory.isCurrent,
    );
    final c = TopicCreationController(
      store: store,
      prepare: adapter.prepare,
      inspect: adapter.inspect,
    );
    try {
      await c.reload();
      adapter.guard();
      if (c.error != null) throw StateError('Record cannot be read');
      if (!routeContext.mounted) return;
      if (c.record == null) {
        final yes = await showDialog<bool>(
          context: routeContext,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: Text(english ? 'End recovery record?' : '结束恢复记录？'),
            content: Text(
              english
                  ? 'No resource result can be inferred from this incomplete storage record. Ending it does not mean the server did not execute the request.'
                  : '记录尚未初始化或已结束，无法推断服务器结果。结束记录不代表请求未执行。',
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
        if (!routeContext.mounted || yes != true) return;
        await flush();
        adapter.guard();
        if (await read(entry.recordKey) != null) {
          throw StateError('Record changed');
        }
      } else {
        await Navigator.of(routeContext).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                TopicCreationRecoveryPage(controller: c, english: english),
          ),
        );
        adapter.guard();
        if (c.record != null) return;
      }
      await flush();
      adapter.guard();
      if (await read(entry.recordKey) != null) {
        throw StateError('Record changed before directory cleanup');
      }
      adapter.guard();
      final slotKey = entry.slotKey;
      if (slotKey != null) {
        final parsed = TopicCreationMetadata.parse(slotKey);
        if (!parsed.slot || parsed.scope != adapter.scope) {
          throw const FormatException('Slot scope differs');
        }
        final tuple =
            jsonDecode(utf8.decode(base64Url.decode(parsed.identity))) as List;
        final slot = TopicCreationSlot(
          scope: adapter.scope,
          kind: TopicCreationKind.values.byName(tuple[1] as String),
          topicId: tuple[2] as int,
          target: tuple[3] as String,
          targetId: tuple[4] as int,
          read: read,
          write: write,
          remove: remove,
          flush: flush,
          isCurrent: directory.isCurrent,
        );
        await slot.clear(entry.attemptKey);
      }
    } finally {
      c.dispose();
    }
  }

  try {
    adapter.guard();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TopicCreationDirectoryPage(
          directory: directory,
          onOpen: open,
          english: english,
        ),
      ),
    );
  } finally {
    adapter.retire();
  }
}
