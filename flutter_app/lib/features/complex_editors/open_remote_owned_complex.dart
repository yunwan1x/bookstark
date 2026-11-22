import '../../core/owned_complex_images.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/features/html/html_editor_lease.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import '../../core/remote_owned_complex_session.dart';

/// True means the real engine route opened, never a Save receipt.
/// New owned-source endpoints are required. No server-page fallback is used.
Future<bool> openRemoteOwnedComplex(
  BuildContext context, {
  required BookstarkClient client,
  required int memberId,
  required int resourceId,
  required int bookId,
  required bool note,
  required ComplexEditorKind kind,
  required String recoveryNamespace,
  required bool Function() isCurrentScope,
  ComplexRecoveryBytesStore? recoveryStore,
  ComplexSourceIoScope? sourceIoScope,
  bool english = false,
}) async {
  String t(String zh, String en) => english ? en : zh;
  bool current() {
    try {
      return context.mounted && isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted || !current()) return false;
  if (kind == ComplexEditorKind.markdown) {
    throw ArgumentError('Markdown routes remain unchanged');
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t('当前平台不支持此编辑器。', 'This editor is unavailable on this platform.'),
        ),
      ),
    );
    return false;
  }
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode([
      'owned-remote-complex',
      client.baseUri.toString(),
      memberId,
      recoveryNamespace,
      note ? 'remote-note' : 'remote-book-document',
      bookId,
      resourceId,
    ]),
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
  RemoteOwnedComplexSession? session;
  LocalComplexEditorController? controller;
  OwnedComplexImages? images;
  var transferred = false;
  try {
    session = await RemoteOwnedComplexSession.inspect(
      client: client,
      memberId: memberId,
      resourceId: resourceId,
      bookId: bookId,
      note: note,
      kind: kind,
      recoveryNamespace: recoveryNamespace,
      isCurrent: current,
      recoveryStore: recoveryStore,
    );
    if (!context.mounted || !current()) return false;
    var choice = RemoteComplexDraftChoice.restore;
    if (session.requiresChoice) {
      final selected = await showDialog<RemoteComplexDraftChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('发现本机草稿', 'Local draft found')),
          content: SingleChildScrollView(
            child: Text(
              t(
                '恢复后仍需明确保存。取消保留草稿和服务器原文。',
                'Restoring still requires explicit Save. Cancel retains draft and server source.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, RemoteComplexDraftChoice.cancel),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, RemoteComplexDraftChoice.discard),
              child: Text(t('放弃草稿', 'Discard draft')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, RemoteComplexDraftChoice.restore),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      if (!current() ||
          selected == null ||
          selected == RemoteComplexDraftChoice.cancel) {
        return false;
      }
      choice = selected;
    }
    final editor = await session.enter(choice);
    if (editor == null) return false;
    controller = editor;
    if (!context.mounted || !current()) return false;
    final imageCapability = OwnedComplexImages(
      client: client,
      memberId: memberId,
      resourceId: resourceId,
      bookId: bookId,
      note: note,
      namespace: recoveryNamespace,
      isCurrent: current,
      editor: editor,
    );
    images = imageCapability;
    await imageCapability.open();
    if (!context.mounted || !current()) return false;
    var built = false;
    final ownedSession = session;
    final route = MaterialPageRoute<void>(
      builder: (_) {
        built = true;
        return LocalComplexNotePage(
          controller: editor,
          ownedImages: imageCapability,
          english: english,
          documentBodyOnly: !note,
          sourceIoScope: sourceIoScope,
          originLabel: t('远端自有', 'Owned remote'),
        );
      },
    );
    if (!context.mounted || !current()) return false;
    final result = Navigator.of(context).push<void>(route);
    transferred = true;
    unawaited(
      route.completed.then((_) async {
        try {
          if (!built) editor.dispose();
          await imageCapability.retireAndDrain();
        } finally {
          ownedSession.retire();
          lease.release();
        }
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
              '无法打开远端复杂文档。可能需要专用保护入口或服务器升级；原文和恢复记录均已保留。',
              'Unable to open remote complex document. A protected editor or server upgrade may be required. Source and recovery retained.',
            ),
          ),
        ),
      );
    }
    return false;
  } finally {
    if (!transferred) {
      try {
        await images?.retireAndDrain();
      } finally {
        controller?.dispose();
        session?.retire();
        lease.release();
      }
    }
  }
}
