import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../core/label_creation_attempt.dart';
import '../../core/label_creation_resolution.dart';
import '../../core/label_management_repository.dart';
import '../../core/local_draft_namespace.dart';
import '../../core/local_label_creation_controller.dart';
import '../../core/local_label_creation_review.dart';
import '../../core/local_label_creation_slot.dart';
import '../../core/local_label_creation_store.dart';
import '../../core/local_store.dart';
import 'label_creation_recovery_page.dart';

/// name==null opens only the existing cold slot; it cannot create an allocation.
Future<LabelCreationResolution?> openLocalLabelCreation({
  required BuildContext context,
  required LocalStore store,
  required String namespace,
  required Future<ManagedLabel> Function(String) create,
  required Future<String?> Function(String) read,
  required Future<void> Function(String, String) write,
  required Future<void> Function(String) remove,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  String? name,
  bool english = false,
}) async {
  if (!LocalDraftNamespace.isLocal(namespace)) {
    throw const FormatException('Actual local generation namespace required');
  }
  void guard() {
    if (!isCurrent() || store.maintenance.retired) {
      throw StateError('Local label owner retired');
    }
  }

  if (store.dataPaths != null && store.dataPaths!.draftNamespace != namespace) {
    throw const FormatException(
      'Local store generation and draft namespace differ',
    );
  }
  guard();
  final scope = sha256
      .convert(utf8.encode(jsonEncode(['local-label', namespace])))
      .toString();
  final slot = LocalLabelCreationSlot(
    scope: scope,
    read: read,
    write: write,
    remove: remove,
    flush: flush,
    isCurrent: isCurrent,
  );
  LocalLabelCreationController? controller;
  try {
    final String key;
    final bool allocated;
    if (name == null) {
      final retained = await read(slot.metadataKey);
      guard();
      if (retained == null) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              scrollable: true,
              title: Text(english ? 'Local label recovery' : '本地标签恢复'),
              content: Text(
                english
                    ? 'No recovery record for this local space.'
                    : '当前本地空间没有标签创建恢复记录。',
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
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(retained)) {
        throw const FormatException('Invalid local label slot');
      }
      key = retained;
      allocated = false;
    } else {
      final allocation = await slot.open();
      guard();
      key = allocation.key;
      allocated = allocation.created;
    }
    final journal = LocalLabelCreationStore(
      scope: scope,
      key: key,
      read: read,
      write: write,
      remove: remove,
      flush: flush,
      isCurrent: isCurrent,
    );
    final reader = LocalLabelCreationMetadataReader(
      store: store,
      isCurrent: isCurrent,
    );
    final c = LocalLabelCreationController(
      store: journal,
      create: create,
      inspect: reader.inspect,
    );
    controller = c;
    await c.reload();
    guard();
    if (c.error != null) {
      throw StateError('Retained local creation record unavailable');
    }
    final retained = c.record != null;
    if (c.record == null && !allocated) {
      if (!context.mounted) return null;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(english ? 'End recovery record?' : '结束恢复记录？'),
          content: Text(
            english
                ? 'This local record is incomplete or already ended. It does not prove creation never happened. No automatic creation will run.'
                : '本地记录不完整或已结束，不能证明创建从未发生，不会自动再次创建。',
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
      if (!context.mounted || yes != true) return null;
      await flush();
      guard();
      if (await read(journal.metadataKey) != null) {
        throw StateError('Local record changed');
      }
      guard();
      await slot.clear(key);
      return null;
    }
    if (c.record == null) {
      await c.begin(
        LabelCreationAttempt(
          scope: scope,
          key: key,
          body: {'label_name': name!},
        ),
      );
      guard();
      if (c.error == null) await c.submit();
      guard();
    }
    if (retained ||
        c.record?.phase != LabelCreationPhase.knownID ||
        c.storageUnconfirmed) {
      if (!context.mounted) {
        throw StateError('Local creation requires recovery');
      }
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LabelCreationRecoveryPage(
            controller: c,
            local: true,
            serverLabel: namespace,
            initiatorId: 0,
            english: english,
          ),
        ),
      );
      guard();
      if (c.endedDurably) {
        await slot.clear(key);
        return null;
      }
      if (accepted != true) throw StateError('Local creation record retained');
    }
    final actual = c.record;
    if (actual == null ||
        actual.phase != LabelCreationPhase.knownID ||
        c.storageUnconfirmed) {
      throw StateError('Local creation unresolved; SQL was not replayed');
    }
    final fresh = await reader.inspect(actual, actual.actualId!);
    guard();
    if (!fresh.matchesFrozenInput ||
        (name != null && actual.body['label_name'] != name)) {
      throw StateError(
        'Retained local ID differs; inspect actual ID explicitly',
      );
    }
    return LabelCreationResolution(origin: actual.origin!, wire: fresh.wire);
  } finally {
    controller?.dispose();
  }
}
