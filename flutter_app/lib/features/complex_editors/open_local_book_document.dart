import 'dart:async';
import '../../core/native_complex_source_io.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/features/html/html_editor_lease.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import '../../core/book_document_complex_session.dart';

/// Existing book document only; Root selects this from the real document route.
Future<bool> openLocalBookDocumentComplex(
  BuildContext context, {
  required LocalStore store,
  required int bookId,
  required int documentId,
  required ComplexEditorKind kind,
  required bool Function() isCurrentScope,
  ComplexRecoveryBytesStore? recoveryStore,
  bool english = false,
  ComplexSourceIoScope? sourceIoScope,
}) async {
  String t(String zh, String en) => english ? en : zh;
  bool current() =>
      context.mounted && !store.maintenance.retired && isCurrentScope();
  if (!context.mounted || !current()) return false;
  if (kind == ComplexEditorKind.markdown) {
    throw ArgumentError('Book Markdown uses native editing');
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            '当前平台不支持此编辑器。原文已保留。',
            'This editor is unavailable on this platform. Original source retained.',
          ),
        ),
      ),
    );
    return false;
  }
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['local-book-document', store.path, bookId, documentId]),
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
  BookDocumentComplexSession? session;
  LocalComplexEditorController? controller;
  var transferred = false;
  try {
    session = await BookDocumentComplexSession.inspect(
      store: store,
      bookId: bookId,
      documentId: documentId,
      kind: kind,
      recoveryStore: recoveryStore ?? NativeComplexRecoveryStore(),
      isCurrent: current,
    );
    if (!context.mounted || !current()) return false;
    var choice = BookDocumentDraftChoice.restore;
    if (session.requiresExplicitDraftChoice) {
      final selected = await showDialog<BookDocumentDraftChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('发现本机草稿', 'Local draft found')),
          content: SingleChildScrollView(
            child: Text(
              t(
                '恢复后仍需明确保存。取消会保留草稿与已保存内容。',
                'Restoring still requires an explicit save. Cancel retains both draft and saved content.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, BookDocumentDraftChoice.cancel),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, BookDocumentDraftChoice.discard),
              child: Text(t('放弃草稿', 'Discard draft')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, BookDocumentDraftChoice.restore),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      if (!current() ||
          selected == null ||
          selected == BookDocumentDraftChoice.cancel) {
        return false;
      }
      choice = selected;
    }
    final editor = await session.enter(choice: choice);
    if (editor == null) return false;
    controller = editor;
    if (!context.mounted || !current()) return false;
    final ownedSession = session;
    var built = false;
    final route = MaterialPageRoute<void>(
      builder: (_) {
        built = true;
        return LocalComplexNotePage(
          controller: editor,
          english: english,
          documentBodyOnly: true,
          sourceIoScope: sourceIoScope,
        );
      },
    );
    if (!context.mounted || !current()) return false;
    final result = Navigator.of(context).push<void>(route);
    transferred = true;
    unawaited(
      route.completed.then((_) {
        if (!built) editor.dispose();
        ownedSession.retire();
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
              '无法打开书籍文档，已保存内容和恢复记录均已保留。',
              'Unable to open book document. Saved content and recovery records retained.',
            ),
          ),
        ),
      );
    }
    return false;
  } finally {
    if (!transferred) {
      controller?.dispose();
      session?.retire();
      lease.release();
    }
  }
}
