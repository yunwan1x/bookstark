import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/complex_recovery_vault.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/local_protected_article_repository.dart';
import '../../core/local_store.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/native_local_content_crypto.dart';
import '../../core/owned_preview_controller.dart';
import '../admin/admin_asset_secure_window.dart';
import '../html/html_editor_lease.dart';
import '../notes/note_unlock_dialog.dart';
import 'local_complex_note_page.dart';

/// Existing ordinary article, original SQL ID/cipher format, no disk plaintext.
Future<bool> openLocalProtectedArticle(
  BuildContext context, {
  required LocalStore store,
  required int id,
  required bool Function() isCurrentScope,
  required ComplexSourceIoScope sourceIoScope,
  bool english = false,
}) async {
  if (!context.mounted || !isCurrentScope()) return false;
  sourceIoScope.guard();
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['ordinary-protected-article', store.path, id]),
  );
  if (lease == null) return false;
  final session = _ProtectedArticleSession(
    Navigator.of(context),
    isCurrentScope,
    lease,
  );
  sourceIoScope.addRetirementDrain(session.retire);
  WidgetsBinding.instance.addObserver(session);
  try {
    // Acquire before password input or plaintext can enter any route.
    await session.secure.acquire();
    if (!session.current) return false;
    final dialog = DialogRoute<LocalProtectedArticleRepository>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NoteUnlockDialog<LocalProtectedArticleRepository>(
        english: english,
        onUnlock: (password) async {
          try {
            final repo = await LocalProtectedArticleRepository.open(
              store: store,
              id: id,
              password: password,
              isCurrentScope: () => session.current,
              crypto: session.crypto,
              cancellation: session.unlockCancellation,
            );
            if (!session.current) {
              repo.dispose();
              await session.retire();
              throw const _ProtectedArticleUnlockMessage('');
            }
            session.repository = repo;
            return repo;
          } catch (error) {
            if (!session.current ||
                error is LocalContentCryptoFailure &&
                    error.reason == LocalContentCryptoReason.cancelled) {
              await session
                  .retire(); // Remove dialog before a cancelled Future completes.
              throw const _ProtectedArticleUnlockMessage('');
            }
            throw _ProtectedArticleUnlockMessage(
              english
                  ? 'Incorrect password or damaged content. Original encrypted content retained.'
                  : '密码错误或内容损坏，原始密文已保留。',
            );
          }
        },
      ),
    );
    session.route = dialog;
    final repo = await session.navigator.push(dialog);
    await dialog.completed;
    session.route = null;
    if (repo == null || !session.current) return false;
    final baseline = await repo.read(id);
    if (!session.current) return false;
    final controller = LocalComplexEditorController(
      repository: repo,
      vault: ComplexRecoveryVault(
        scope: repo.scope,
        collection: repo.collection,
        kind: repo.kind,
        store: session.memory,
      ),
      baseline: baseline,
      ephemeralDrafts: true,
    );
    var built = false;
    final page = MaterialPageRoute<void>(
      builder: (_) {
        built = true;
        return LocalComplexNotePage(
          controller: controller,
          english: english,
          retirementController: session.preview,
          onUnplannedBackground: session.retire,
          onDisposed: () => unawaited(session.retire()),
          // No sourceIoScope/files/resources: plaintext stays in route memory.
          originLabel: english ? 'Protected local article' : '本机受保护文章',
          retentionNotice: english
              ? 'Content stays only in this session memory. Closing or background locking loses unsaved content. Save explicitly keeps the original article encrypted.'
              : '正文只保留在本次会话内存。关闭或后台锁定会丢失未保存正文；明确保存后原文章仍以密文存储。',
        );
      },
    );
    session.route = page;
    try {
      await session.navigator.push(page);
      await page.completed;
    } finally {
      if (!built) controller.dispose();
    }
    return true;
  } catch (_) {
    if (context.mounted && session.current) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Unable to open this protected article. Original encrypted content retained.'
                : '无法打开受保护文章，原始密文已保留。',
          ),
        ),
      );
    }
    return false;
  } finally {
    await session.retire();
    sourceIoScope.removeRetirementDrain(session.retire);
    WidgetsBinding.instance.removeObserver(session);
  }
}

final class _ProtectedArticleSession with WidgetsBindingObserver {
  _ProtectedArticleSession(this.navigator, this.isCurrentScope, this.lease);
  final NavigatorState navigator;
  final bool Function() isCurrentScope;
  final HtmlEditorLease lease;
  final secure = AdminAssetSecureWindow();
  final crypto = NativeLocalContentCrypto();
  final preview = OwnedPreviewController();
  final memory = LocalProtectedArticleMemoryStore();
  final unlockCancellation = AttachmentCancellation();
  LocalProtectedArticleRepository? repository;
  TransitionRoute<dynamic>? route;
  bool _closed = false;
  Future<void>? _retiring;
  bool get current {
    if (_closed) return false;
    try {
      return isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(retire().catchError((Object _) {}));
    }
  }

  Future<void> retire() {
    _closed = true;
    unlockCancellation.cancel();
    repository?.dispose();
    return _retiring ??= _close();
  }

  Future<void> _close() async {
    try {
      await preview.retire();
      await repository?.drain();
      final active = route;
      if (active != null) {
        if (active.isActive) navigator.removeRoute(active);
        await active.completed;
      }
      memory.close();
      await crypto.drain();
    } finally {
      memory.close();
      await secure.close();
      lease.release();
      preview.dispose();
      repository = null;
      route = null;
    }
  }
}

final class _ProtectedArticleUnlockMessage implements Exception {
  const _ProtectedArticleUnlockMessage(this.message);
  final String message;
  @override
  String toString() => message;
}
