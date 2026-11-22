import '../../core/owned15_generation_attachments.dart';
import '../../core/complex_editor_document.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/complex_recovery_vault.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/owned15_complex_repository.dart';
import '../../core/owned15_editor_lifetime.dart';
import '../../core/owned15_native_notes_repository.dart';
import '../../core/owned15_save_journal.dart';
import '../../core/owned_writable_generation15.dart';
import '../../core/protected_complex_lifetime.dart';
import '../../core/protected_complex_memory_store.dart';
import '../admin/admin_asset_secure_window.dart';
import '../complex_editors/local_complex_note_page.dart';
import '../complex_editors/protected_owned_review_page.dart';
import '../html/html_editor_lease.dart';
import '../notes/note_unlock_dialog.dart';
import '../notes/notes_page.dart';
import 'owned15_memory_editor_guard.dart';
import 'owned15_native_memory_editor.dart';

/// Actual owned15 resource entry for all seven formats. Required metadata guard
/// is keys-only/all-owner and must fail closed on corrupt/overbound keys.
Future<bool> openOwned15Resource(
  BuildContext context, {
  required OwnedWritableGeneration15 database,
  required GenerationContentMetadata metadata,
  required bool Function() isCurrentScope,
  required Future<void> Function() checkRecoveryMetadata,
  required Owned15SaveJournal Function(
    String collection,
    int id,
    bool Function() current,
  )
  createJournal,
  required void Function(ProtectedComplexOwner) registerOwner,
  required void Function(ProtectedComplexOwner) unregisterOwner,
  required ComplexSourceIoScope sourceIoScope,
  bool english = false,
}) async {
  bool current() => context.mounted && database.current && isCurrentScope();
  if (!current() ||
      metadata.generationId != database.pointer.generation ||
      metadata.id <= 0 ||
      !{'note', 'article'}.contains(metadata.collection)) {
    return false;
  }
  await checkRecoveryMetadata();
  if (!context.mounted || !current()) return false;
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode([
      'owned15-resource',
      database.pointer.encode(),
      metadata.collection,
      metadata.id,
    ]),
  );
  if (lease == null) return false;
  final secure = AdminAssetSecureWindow();
  Owned15EditorLifetime? lifetime;
  try {
    final journal = createJournal(metadata.collection, metadata.id, current);
    final owner = Owned15EditorLifetime(
      journal: journal,
      isCurrentScope: current,
      drainCrypto: database.content.crypto.drain,
      onDrained: unregisterOwner,
      afterDrained: () async {
        await secure.close();
        lease.release();
      },
    );
    lifetime = owner;
    registerOwner(owner);
    final navigator = Navigator.of(context);
    Future<T?> route<T>(TransitionRoute<T> page) async {
      if (!owner.current) return null;
      owner.bindRoute(() async {
        if (page.isActive) navigator.removeRoute(page);
        await page.completed;
      });
      final value = await navigator.push<T>(page);
      await page.completed;
      if (owner.current) owner.bindRoute(null);
      return value;
    }

    // Before password or any local protected plaintext can enter a route.
    if (metadata.isProtected) await secure.acquire();
    if (!context.mounted || !owner.current) return false;
    final marker = await journal.load();
    if (!context.mounted || !owner.current) return false;
    final native =
        metadata.collection == 'note' && metadata.format.name == 'markdown';
    Owned15NativeNotesRepository? nativeRepository;
    Owned15ComplexRepository? complexRepository;
    Future<bool> open(String? password) async {
      if (!owner.current) throw StateError('Owned15 resource retired');
      if (native) {
        final repo = await owner.run(
          (cancellation) => Owned15NativeNotesRepository.open(
            owner: database,
            journal: journal,
            resourceId: metadata.id,
            isCurrentScope: () => owner.current,
            cancellation: cancellation,
            password: password,
          ),
          onLateResult: (repo) => repo.dispose(),
        );
        nativeRepository = repo;
        owner.bindRepository(close: repo.dispose, drain: repo.drain);
      } else {
        final repo = await owner.run(
          (cancellation) => Owned15ComplexRepository.open(
            owner: database,
            journal: journal,
            collection: metadata.collection,
            resourceId: metadata.id,
            isCurrentScope: () => owner.current,
            cancellation: cancellation,
            password: password,
          ),
          onLateResult: (repo) => repo.dispose(),
        );
        complexRepository = repo;
        owner.bindRepository(close: repo.dispose, drain: repo.drain);
      }
      return true;
    }

    if (metadata.isProtected) {
      final unlocked = await route<bool>(
        DialogRoute<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => NoteUnlockDialog<bool>(
            english: english,
            onUnlock: (password) => open(password),
          ),
        ),
      );
      if (unlocked != true || !owner.current) return false;
    } else {
      await open(null);
    }
    if (!context.mounted || !owner.current) return false;
    if (native) {
      final repo = nativeRepository!;
      if (marker != null) repo.reviewRequired.value = true;
      final initialSource = repo.baseline.content;
      final resources = marker != null
          ? null
          : await repo.resourcesForDocument(
              ComplexEditorDocument.parse(
                ComplexEditorKind.markdown,
                initialSource,
              ),
            );
      final attachments = resources == null
          ? null
          : Owned15GenerationAttachments(resources);
      if (!context.mounted || !owner.current) return false;
      try {
        await route<void>(
          MaterialPageRoute<void>(
            builder: (_) => Owned15MemoryEditorGuard(
              owner: owner,
              english: english,
              child: Owned15NativeMemoryEditor(
                repository: repo,
                isCurrent: () => owner.current,
                english: english,
                onReviewed: () async {
                  if (!owner.current) return;
                  await owner.retire();
                },
                editorBuilder: (_) => NoteEditorPage(
                  repository: repo,
                  note: repo.baseline,
                  drafts: null,
                  english: english,
                  attachments: attachments,
                  allowAttachmentInsertion: false,
                  onMemoryDraftChanged: (snapshot) {
                    if (snapshot.content != initialSource) {
                      unawaited(repo.revokeResources());
                    }
                  },
                ),
              ),
            ),
          ),
        );
      } finally {
        attachments?.close();
        await repo.revokeResources();
      }
      return true;
    }
    final repo = complexRepository!;
    var baseline = repo.baseline;
    if (marker != null) {
      final ended = await route<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ProtectedOwnedReviewPage(
            initial: baseline,
            owner: owner,
            localSource: true,
            english: english,
            readFresh: () => repo.read(metadata.id),
            finishReviewed: repo.endWarmReview,
          ),
        ),
      );
      if (ended != true || !context.mounted || !owner.current) return false;
      await owner.nextPreview();
      baseline = await repo.read(metadata.id);
      if (!context.mounted || !owner.current) return false;
    }
    final memory = ProtectedComplexMemoryStore(journal);
    owner.bindMemory(memory);
    final controller = LocalComplexEditorController(
      repository: repo,
      vault: ComplexRecoveryVault(
        scope: repo.scope,
        collection: repo.collection,
        kind: repo.kind,
        store: memory,
      ),
      baseline: baseline,
      ephemeralDrafts: true,
      beforeAdoptReviewed: repo.endWarmReview,
    );
    bool built = false;
    try {
      await route<void>(
        MaterialPageRoute<void>(
          builder: (_) {
            built = true;
            return LocalComplexNotePage(
              controller: controller,
              english: english,
              generationResourceFactory: repo.resourcesForDocument,
              sourceIoScope: sourceIoScope,
              retirementController: owner.preview,
              renewRetirementController: () async {
                await owner.nextPreview();
                return owner.preview;
              },
              onUnplannedBackground: () => owner.retire(),
              retentionNotice: english
                  ? 'Content stays only in this session memory. Closing or background locking loses unsaved content. Unknown saves require reviewing the current local version. Explicit file export writes only to the location you choose.'
                  : '正文只保留在本次会话内存。关闭或后台锁定会丢失未保存正文；未知保存需核对当前本机版本。主动导出文件只写入您选择的位置。',
              originLabel: english ? 'Owned local space' : '本机资料空间',
            );
          },
        ),
      );
    } finally {
      if (!built) controller.dispose();
    }
    return true;
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Unable to open this resource. Recovery records are retained.'
                : '无法打开此资料，恢复记录仍保留。',
          ),
        ),
      );
    }
    return false;
  } finally {
    if (lifetime != null) {
      await lifetime.retire();
    } else {
      await secure.close();
      lease.release();
    }
  }
}
