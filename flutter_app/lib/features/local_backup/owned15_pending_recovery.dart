import '../../core/attachments.dart';
import '../../core/owned15_creation_marker_metadata.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/local_recovery_inventory.dart';
import '../../core/owned15_save_journal.dart';
import '../../core/owned15_save_marker_metadata.dart';
import '../../core/owned_writable_generation15.dart';
import 'local_pending_recovery_page.dart';

/// Resolve opaque local15 records from current metadata, never body/title
/// guessing. A bounded enumeration failure retains every unresolved record.
Future<LocalPendingRecoveryView> loadOwned15Pending({
  required OwnedWritableGeneration15 owner,
  required Future<LocalRecoverySummary> Function() readInventory,
  required bool Function() isCurrent,
  required Future<void> Function(GenerationContentMetadata) openResource,
  required AttachmentCancellation cancellation,
  Future<void> Function()? openCreationRecovery,
  bool english = false,
}) async {
  void check() {
    cancellation.check();
    if (!owner.current || !isCurrent()) {
      throw StateError('Owned15 recovery retired');
    }
  }

  check();
  await owner.confirmCurrent();
  check();
  final summary = await readInventory();
  check();
  final currentOwner = Owned15SaveJournal.ownerTagForGeneration(
    owner.generation.draftNamespace,
  );
  final wanted = <String>{};
  for (final reference in summary.references) {
    if (reference.kind != 'owned15-save') continue;
    final metadata = Owned15SaveMarkerMetadata.parse(reference.key);
    if (metadata.ownerTag == currentOwner) wanted.add(metadata.scope);
  }
  final resolved = <String, GenerationContentMetadata>{};
  if (wanted.isNotEmpty) {
    for (var page = 1; page <= 200; page++) {
      check();
      final entries = await owner.content.list(
        collection: 'all',
        page: page,
        cancellation: cancellation,
      );
      check();
      for (final entry in entries) {
        final value = entry.metadata;
        if (value.generationId != owner.pointer.generation) {
          throw StateError('Owned15 metadata owner changed');
        }
        final scope = Owned15SaveJournal.scopeForResource(
          draftNamespace: owner.generation.draftNamespace,
          collection: value.collection,
          resourceId: value.id,
        );
        if (wanted.contains(scope)) {
          if (resolved.containsKey(scope)) {
            throw StateError('Duplicate local resource identity');
          }
          resolved[scope] = value;
        }
      }
      if (entries.length < 20 || resolved.length == wanted.length) break;
      // At the bound unresolved slots stay visible and cannot be cleared.
    }
  }
  check();
  return LocalPendingRecoveryView(summary, [
    for (final reference in summary.references)
      _item(reference, resolved, currentOwner, check, openResource, english,
        openCreationRecovery),
  ]);
}

LocalPendingRecoveryItem _item(
  LocalRecoveryReference ref,
  Map<String, GenerationContentMetadata> resolved,
  String ownerTag,
  void Function() check,
  Future<void> Function(GenerationContentMetadata) open,
  bool english,
  Future<void> Function()? openCreationRecovery,
) {
  if(ref.kind=='owned15-create') {
    final key=Owned15CreationMarkerMetadata.parse(ref.key);
    final open=key.ownerTag==ownerTag?openCreationRecovery:null;
    return LocalPendingRecoveryItem(reference:ref,
      title:english?'Unfinished creation result':'尚未核对的新建结果',
      detail:english?
        'The operation record contains no draft body or password. Review the exact receipt; creation is never repeated.':
        '操作记录没有正文或密码。只能核对此操作的真实回执，不会再次创建。',
      actionLabel:open==null?null:(english?'Review creation result':'核对新建结果'),
      open:open==null?null:()async{check();await open();});
  }
  GenerationContentMetadata? actual;
  if (ref.kind == 'owned15-save') {
    final key = Owned15SaveMarkerMetadata.parse(ref.key);
    if (key.ownerTag == ownerTag) actual = resolved[key.scope];
  }
  final value = actual;
  return LocalPendingRecoveryItem(
    reference: ref,
    title:
        value?.title ??
        (english ? 'Unresolved local recovery record' : '尚未定位的本机恢复记录'),
    detail: value == null
        ? (english
              ? 'Record retained. It may belong to another space, deleted content, or content outside the bounded metadata scan. No retry or deletion is authorized.'
              : '记录已保留，可能属于另一空间、已删除资料，或超出有界元数据核对范围。不会重试保存或删除记录。')
        : (english
              ? 'Review the current local content. Previous unsaved content was not retained.'
              : '只读核对当前本机资料；上次未保存正文没有保留。'),
    actionLabel: value == null ? null : (english ? 'Read-only review' : '只读核对'),
    open: value == null
        ? null
        : () async {
            check();
            await open(value);
          },
  );
}
