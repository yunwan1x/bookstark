import '../../core/local_presentation_image_owner.dart';
import '../../core/local_presentation_local_files.dart';
import '../../core/local_mindmap_image_owner.dart';
import '../../core/local_drawing_image_owner.dart';
import '../../core/local_mindmap_local_files.dart';
import '../../core/local_drawing_local_files.dart';
import '../../core/local_richdoc_image_owner.dart';
import '../../core/local_richdoc_local_files.dart';
import 'dart:async';
import '../../core/native_complex_source_io.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/draft_vault.dart';
import '../../core/local_article_draft_handoff.dart';
import '../../core/local_article_draft_archive.dart';
import '../../core/native_recovery_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/complex_recovery_store.dart';
import '../../core/complex_recovery_vault.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/local_store.dart';
import '../../core/local_attachments.dart';
import '../html/html_editor_lease.dart';
import 'local_complex_note_page.dart';
import 'local_complex_read_page.dart';

Future<bool> openLocalComplexNote(
  BuildContext context, {
  required LocalStore store,
  required int id,
  required String collection,
  required ComplexEditorKind kind,
  bool english = false,
  ComplexSourceIoScope? sourceIoScope,
  ComplexRecoveryBytesStore? recoveryStore,
  DraftVault? legacyMarkdownDrafts,
  bool forceLegacyReview = false,
  LocalArticleDraftRestoreApproval? approvedLegacyDraft,
  bool Function()? isCurrentScope,
}) async {
  String t(String zh, String en) => english ? en : zh;
  bool current() {
    if (!context.mounted || store.maintenance.retired) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted || !current()) return false;
  if (approvedLegacyDraft != null &&
      (kind != ComplexEditorKind.markdown ||
          collection != 'article' ||
          !forceLegacyReview)) {
    throw ArgumentError('Archive approval requires a Markdown article restore');
  }
  if (kind == ComplexEditorKind.markdown && collection != 'article') {
    throw ArgumentError('Only Markdown articles use this WebView');
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalComplexReadPage(
          store: store,
          id: id,
          collection: collection,
          kind: kind,
          english: english,
        ),
      ),
    );
    return true;
  }
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['local', store.path, collection, id]),
  );
  if (lease == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t('此文档已打开，请返回原页面。', 'Document already open. Return to its page.'),
        ),
      ),
    );
    return false;
  }
  final repository = LocalComplexNotesRepository(
    store,
    kind: kind,
    collection: collection,
  );
  LocalComplexEditorController? controller;
  LocalRichdocLocalFiles? localRichdocFiles;
  LocalMindmapLocalFiles? localMindmapFiles;
  LocalDrawingLocalFiles? localDrawingFiles;
  LocalPresentationLocalFiles? localPresentationFiles;
  var transferred = false;
  try {
    final baseline = await repository.read(id);
    final vault = ComplexRecoveryVault(
      scope: repository.scope,
      collection: collection,
      kind: kind,
      store: recoveryStore ?? NativeComplexRecoveryStore(),
      maintenance: store.maintenance,
    );
    ComplexRecoveryRecord? recovery;
    try {
      recovery = await vault.read(id);
    } catch (_) {
      if (!context.mounted || !current()) return false;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('本机恢复记录无法读取', 'Unable to read recovery record')),
          content: Text(
            t(
              '恢复记录与已保存内容均已保留。请返回后重试。',
              'Recovery and saved content are retained. Return and retry.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('返回', 'Back')),
            ),
          ],
        ),
      );
      return false;
    }
    if (!context.mounted || !current()) return false;
    var restoredLegacy = false;
    if (kind == ComplexEditorKind.markdown &&
        (recovery == null || forceLegacyReview)) {
      final namespace = jsonEncode([
        store.dataPaths!.draftNamespace,
        'article',
      ]);
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
      );
      final legacy =
          legacyMarkdownDrafts ??
          DraftVault(
            namespace: namespace,
            maintenance: store.maintenance,
            readValue: (key) => storage.read(key: key),
            writeValue: (key, value) => storage.write(key: key, value: value),
            deleteValue: (key) => storage.delete(key: key),
          );
      if (approvedLegacyDraft != null) {
        if (!forceLegacyReview ||
            approvedLegacyDraft.namespace != namespace ||
            approvedLegacyDraft.id != id) {
          throw StateError('Archived article approval scope mismatch');
        }
        final fingerprint =
            await NativeRecoveryStorage.localArticleDraftFingerprint(
              legacy.metadataKey(id),
            );
        if (!context.mounted || !current()) return false;
        if (fingerprint != approvedLegacyDraft.ciphertextSHA256) {
          throw StateError('Archived article draft changed after approval');
        }
      }
      final handoff = LocalArticleDraftHandoff(
        legacy: legacy,
        expectedLegacyNamespace: namespace,
        recovery: vault,
        maintenance: store.maintenance,
        readCurrent: repository.read,
        flushMarker: NativeRecoveryStorage.flush,
        fingerprintLegacyDraft: (id) =>
            NativeRecoveryStorage.localArticleDraftFingerprint(
              legacy.metadataKey(id),
            ),
        isCurrentScope: current,
      );
      final candidate = await handoff.inspect(
        baseline,
        forceReview: forceLegacyReview,
      );
      if (!context.mounted || !current()) return false;
      if (approvedLegacyDraft != null &&
          candidate != null &&
          candidate.digest != approvedLegacyDraft.digest) {
        throw StateError('Archived article source changed after approval');
      }
      if (candidate != null && recovery != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('请先核对现有恢复记录', 'Review existing recovery first')),
            content: Text(
              t(
                '原有草稿和 WebView 恢复记录均已保留，请先处理当前恢复记录。',
                'The old draft and WebView recovery are retained. Review the current recovery first.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('返回', 'Back')),
              ),
            ],
          ),
        );
        return false;
      }
      if (candidate != null) {
        final restore = approvedLegacyDraft != null
            ? true
            : await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(t('发现原有文章草稿', 'Original article draft found')),
                  content: Text(
                    t(
                      '已保存内容和旧草稿均已保留。恢复后仍需手动保存。',
                      'Saved content and the old draft are retained. Restore still requires an explicit save.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('暂不恢复', 'Not now')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('恢复草稿', 'Restore draft')),
                    ),
                  ],
                ),
              );
        if (!context.mounted || !current() || restore == null) return false;
        if (restore) {
          recovery = await handoff.restore(candidate, baseline);
          restoredLegacy = true;
        } else {
          await handoff.skip(candidate, baseline);
        }
      }
    }
    if (!context.mounted || !current()) return false;
    if (!restoredLegacy &&
        recovery != null &&
        !recovery.pending &&
        recovery.baselineMatches(baseline)) {
      final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('发现本机草稿', 'Local draft found')),
          content: Text(
            t(
              '恢复草稿后仍需手动保存。取消会保留草稿。',
              'Restoring requires an explicit save later. Cancel retains the draft.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('放弃草稿', 'Discard draft')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      if (!context.mounted || !current() || restore == null) return false;
      if (!restore) {
        await vault.remove(id);
        recovery = null;
      }
    }
    if (!context.mounted || !current()) return false;
    final editor = LocalComplexEditorController(
      repository: repository,
      vault: vault,
      baseline: baseline,
      recovery: recovery,
    );
    controller = editor;
    if (kind == ComplexEditorKind.richdoc &&
        sourceIoScope != null &&
        store.dataPaths != null) {
      final images = LocalRichdocImageOwner.open(
        store: store,
        controller: editor,
        sourceOwner: sourceIoScope,
        isCurrentScope: current,
      );
      localRichdocFiles = LocalRichdocLocalFiles(images);
    }
    if (kind == ComplexEditorKind.mindmap &&
        sourceIoScope != null &&
        store.dataPaths != null) {
      final images = LocalMindmapImageOwner.open(
        store: store,
        controller: editor,
        sourceOwner: sourceIoScope,
        isCurrentScope: current,
      );
      localMindmapFiles = LocalMindmapLocalFiles(images);
    }
    if (kind == ComplexEditorKind.drawing &&
        sourceIoScope != null &&
        store.dataPaths != null) {
      final images = LocalDrawingImageOwner.open(
        store: store,
        controller: editor,
        sourceOwner: sourceIoScope,
        isCurrentScope: current,
      );
      localDrawingFiles = LocalDrawingLocalFiles(images);
    }
    if (kind == ComplexEditorKind.presentation &&
        sourceIoScope != null &&
        store.dataPaths != null) {
      final images = LocalPresentationImageOwner.open(
        store: store,
        controller: editor,
        sourceOwner: sourceIoScope,
        isCurrentScope: current,
      );
      localPresentationFiles = LocalPresentationLocalFiles(images);
    }
    var pageBuilt = false;
    final route = MaterialPageRoute<void>(
      builder: (_) {
        pageBuilt = true;
        return LocalComplexNotePage(
          controller: editor,
          sourceIoScope: sourceIoScope,
          localRichdocFiles: localRichdocFiles,
          localMindmapFiles: localMindmapFiles,
          localDrawingFiles: localDrawingFiles,
          localPresentationFiles: localPresentationFiles,
          attachments:
              kind == ComplexEditorKind.markdown &&
                  collection == 'article' &&
                  store.dataPaths != null
              ? LocalAttachments(
                  store.dataPaths!.attachments,
                  maintenance: store.maintenance,
                )
              : null,
          english: english,
          onDisposed: lease.release,
        );
      },
    );
    final result = Navigator.of(context).push<void>(route);
    transferred = true;
    unawaited(
      route.completed.then((_) async {
        if (!pageBuilt) {
          await localRichdocFiles?.retireAndDrain();
          await localRichdocFiles?.owner.retireAndDrain();
          await localMindmapFiles?.retireAndDrain();
          await localMindmapFiles?.owner.retireAndDrain();
          await localDrawingFiles?.retireAndDrain();
          await localPresentationFiles?.retireAndDrain();
          await localDrawingFiles?.owner.retireAndDrain();
          await localPresentationFiles?.owner.retireAndDrain();
          editor.dispose();
        }
        lease.release();
      }),
    );
    await result;
    return true;
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法打开文档，原始内容已保留。',
              'Unable to open document. Original content retained.',
            ),
          ),
        ),
      );
    }
    return false;
  } finally {
    if (!transferred) {
      await localRichdocFiles?.retireAndDrain();
      await localRichdocFiles?.owner.retireAndDrain();
      await localMindmapFiles?.retireAndDrain();
      await localMindmapFiles?.owner.retireAndDrain();
      await localDrawingFiles?.retireAndDrain();
      await localPresentationFiles?.retireAndDrain();
      await localDrawingFiles?.owner.retireAndDrain();
      await localPresentationFiles?.owner.retireAndDrain();
      controller?.dispose();
      repository.dispose();
      lease.release();
    }
  }
}
