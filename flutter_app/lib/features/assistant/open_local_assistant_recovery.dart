import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/local_assistant_creation_receipts.dart';
import '../../core/draft_vault.dart';
import '../../core/task_draft_vault.dart';
import '../../core/local_assistant_retained_draft.dart';
import 'local_assistant_retained_draft_page.dart';
import '../../core/local_assistant_draft_ledger.dart';
import '../../core/local_assistant_editor_drafts.dart';
import '../../core/local_assistant_save_review.dart';
import '../../core/local_assistant_write_journal.dart';
import '../../core/local_recovery_resolver.dart';
import '../../core/local_store.dart';
import '../../core/native_recovery_storage.dart';
import 'local_assistant_save_review_page.dart';

typedef ResumeLocalAssistantEditor =
    Future<void> Function(
      BuildContext context,
      LocalAssistantWriteMarker identity,
    );
typedef ResumeSavedLocalAssistantEditor =
    Future<void> Function(
      BuildContext context,
      LocalAssistantWriteMarker identity,
      int expectedResourceId,
      String? reviewedFingerprint,
    );
typedef OpenLocalAssistantResource =
    Future<void> Function(
      BuildContext context,
      LocalAssistantCreationInspection inspection,
    );

/// Only native-readable, current Markdown/task states can resume the AI-owned
/// editor. Format/protection/read failures use the existing typed resource route.
bool canResumeSavedAssistantReview(
  LocalAssistantCreationInspection inspection,
) =>
    inspection.receipt != null &&
    {
      LocalAssistantCreationResourceState.matching,
      LocalAssistantCreationResourceState.changed,
    }.contains(inspection.state);

/// Explicit recovery only: pending write identities never enter ordinary
/// null-ID editors. Missing/corrupt records remain preserved and blocking.
class LocalAssistantRecovery {
  LocalAssistantRecovery({
    required this.store,
    required this.drainOriginatingSave,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    this.isCurrent,
  });
  factory LocalAssistantRecovery.secure({
    required LocalStore store,
    required Future<void> Function(LocalAssistantWriteMarker)
    drainOriginatingSave,
    bool Function()? isCurrent,
  }) {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
    );
    return LocalAssistantRecovery(
      store: store,
      drainOriginatingSave: drainOriginatingSave,
      isCurrent: isCurrent,
      readValue: (key) => storage.read(key: key),
      writeValue: (key, value) async {
        await storage.write(key: key, value: value);
        await NativeRecoveryStorage.flush();
      },
      deleteValue: (key) async {
        await storage.delete(key: key);
        await NativeRecoveryStorage.flush();
      },
    );
  }
  final LocalStore store;
  final Future<void> Function(LocalAssistantWriteMarker) drainOriginatingSave;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  final bool Function()? isCurrent;
  void guard() {
    if (store.maintenance.retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  LocalAssistantWriteMarker identity(LocalRecoveryDestination destination) {
    guard();
    final marker = destination.assistant;
    final base = store.dataPaths?.draftNamespace;
    if (marker == null ||
        base == null ||
        marker.namespace != base ||
        destination.id != null ||
        (destination.assistantResourceId != null &&
            (destination.kind != 'ai-editor' ||
                destination.assistantResourceId! <= 0)) ||
        marker.inputHash != null ||
        !{'ai-create', 'ai-editor'}.contains(destination.kind)) {
      throw StateError('Invalid assistant recovery destination');
    }
    final expected = destination.kind == 'ai-create'
        ? base
        : LocalAssistantEditorDrafts.editorNamespace(
            base: base,
            binding: marker.bindingId,
            draft: marker.draftId,
            kind: marker.kind,
          );
    if (destination.namespace != expected) {
      throw StateError('Assistant recovery scope changed');
    }
    return marker;
  }

  LocalAssistantDraftLedger ledger(LocalAssistantWriteMarker marker) =>
      LocalAssistantDraftLedger(
        namespace: LocalAssistantEditorDrafts.ledgerNamespace(
          store.path,
          marker.bindingId,
        ),
        readValue: readValue,
        writeValue: writeValue,
        isCurrent: () {
          return !store.maintenance.retired && isCurrent?.call() != false;
        },
      );
  LocalAssistantWriteJournal journal(LocalAssistantWriteMarker marker) =>
      LocalAssistantWriteJournal(
        namespace: marker.namespace,
        bindingId: marker.bindingId,
        maintenance: store.maintenance,
        readValue: readValue,
        writeValue: writeValue,
        deleteValue: deleteValue,
        isCurrent: () =>
            !store.maintenance.retired && isCurrent?.call() != false,
      );

  LocalAssistantRetainedDraft retained(LocalRecoveryDestination destination) {
    final marker = identity(destination);
    final namespace = LocalAssistantEditorDrafts.editorNamespace(
      base: marker.namespace,
      binding: marker.bindingId,
      draft: marker.draftId,
      kind: marker.kind,
    );
    return LocalAssistantRetainedDraft(
      store: store,
      identity: marker,
      ledger: ledger(marker),
      journal: journal(marker),
      notes: DraftVault(
        namespace: namespace,
        maintenance: store.maintenance,
        readValue: readValue,
        writeValue: writeValue,
        deleteValue: deleteValue,
      ),
      tasks: TaskDraftVault(
        namespace: namespace,
        maintenance: store.maintenance,
        readValue: readValue,
        writeValue: writeValue,
        deleteValue: deleteValue,
      ),
      resourceId: destination.assistantResourceId,
      drainOriginatingSave: () => drainOriginatingSave(marker),
      isCurrent: isCurrent,
    );
  }

  /// Drains even when no marker exists, preventing a late Save from creating
  /// content after the decision to resume. Does not read receipt SQL on schema14.
  Future<bool> needsReview(LocalRecoveryDestination destination) async {
    final marker = identity(destination);
    await drainOriginatingSave(marker);
    guard();
    final pending = await journal(marker).readMarker(marker);
    guard();
    if (pending != null) return true;
    final records = await ledger(marker).load();
    guard();
    final record = records
        .where((record) => record.id == marker.draftId)
        .single;
    if (record.payload.kind != marker.kind) {
      throw StateError('Assistant editor kind changed');
    }
    if (record.state == LocalAssistantDraftState.cancelled) {
      await retained(destination).inspect();
      guard();
      return false;
    }
    if (record.state == LocalAssistantDraftState.created) {
      await createdReceipt(destination);
      guard();
      return destination.kind == 'ai-create';
    }
    if (destination.kind != 'ai-editor' ||
        destination.assistantResourceId != null ||
        record.state != LocalAssistantDraftState.pending) {
      throw StateError('Assistant editor requires recovery');
    }
    return false;
  }

  /// Read-only ownership proof for same-ID editing. Never authorizes creation,
  /// changes ledger state, deletes a draft, or adopts an uncertain write.
  Future<LocalAssistantCreationReceipt> createdReceipt(
    LocalRecoveryDestination destination,
  ) async {
    final marker = identity(destination);
    final records = await ledger(marker).load();
    guard();
    final record = records
        .where((record) => record.id == marker.draftId)
        .single;
    if (record.state != LocalAssistantDraftState.created ||
        record.payload.kind != marker.kind ||
        record.resourceId == null) {
      throw StateError('A known committed resource is required');
    }
    final receipt = await LocalAssistantCreationReceipts(
      store,
      isCurrent: isCurrent,
    ).lookup(marker.draftId);
    guard();
    if (receipt == null ||
        receipt.kind != marker.kind ||
        receipt.inputHash != record.inputHash ||
        receipt.resourceId != record.resourceId ||
        (destination.assistantResourceId != null &&
            destination.assistantResourceId != receipt.resourceId)) {
      throw StateError('Assistant receipt and editor identity differ');
    }
    return receipt;
  }

  Future<void> open(
    BuildContext context,
    LocalRecoveryDestination destination, {
    required ResumeLocalAssistantEditor onResumeEditor,
    required OpenLocalAssistantResource onOpenResource,
    ResumeSavedLocalAssistantEditor? onResumeSavedEditor,
    bool english = false,
  }) async {
    final marker = identity(destination);
    final reviewNeeded = await needsReview(destination);
    guard();
    if (!context.mounted) return;
    if (!reviewNeeded) {
      final records = await ledger(marker).load();
      guard();
      final record = records
          .where((record) => record.id == marker.draftId)
          .single;
      if (record.state == LocalAssistantDraftState.cancelled) {
        final archive = retained(destination);
        final snapshot = await archive.inspect();
        guard();
        if (!context.mounted || snapshot == null) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => LocalAssistantRetainedDraftPage(
              inspect: archive.inspect,
              clear: archive.clear,
              initialSnapshot: snapshot,
              english: english,
            ),
          ),
        );
      } else if (record.state == LocalAssistantDraftState.created) {
        final receipt = await createdReceipt(destination);
        guard();
        if (!context.mounted) return;
        if (onResumeSavedEditor == null) {
          throw StateError('Saved editor recovery is unavailable');
        }
        await onResumeSavedEditor(context, marker, receipt.resourceId, null);
      } else {
        if (record.state != LocalAssistantDraftState.pending ||
            destination.assistantResourceId != null) {
          throw StateError('New editor is not authorized');
        }
        if (!context.mounted) return;
        await onResumeEditor(context, marker);
      }
      guard();
      return;
    }
    final review = LocalAssistantSaveReview(
      receipts: LocalAssistantCreationReceipts(store, isCurrent: isCurrent),
      ledger: ledger(marker),
      journal: journal(marker),
      identity: marker,
      drainOriginatingSave: () => drainOriginatingSave(marker),
      isCurrent: isCurrent,
      expectedResourceId: destination.assistantResourceId,
    );
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LocalAssistantSaveReviewPage(
          english: english,
          inspect: review.inspect,
          resolve: review.resolve,
          onOpenResource: (inspection) async {
            guard();
            final fresh = await review.inspect();
            guard();
            if (fresh.key != inspection.key ||
                fresh.fingerprint != inspection.fingerprint ||
                fresh.receipt == null ||
                fresh.state == LocalAssistantCreationResourceState.missing) {
              throw StateError('Assistant resource changed');
            }
            if (!context.mounted) return;
            final pending = await journal(marker).readMarker(marker);
            guard();
            if (!context.mounted) return;
            if (pending == null &&
                onResumeSavedEditor != null &&
                canResumeSavedAssistantReview(fresh)) {
              final receipt = await createdReceipt(destination);
              guard();
              if (!context.mounted) return;
              await onResumeSavedEditor(
                context,
                marker,
                receipt.resourceId,
                fresh.fingerprint,
              );
            } else {
              // Root resolves actual collection/format through its typed opener.
              await onOpenResource(context, fresh);
            }
            guard();
          },
        ),
      ),
    );
    guard();
  }
}
