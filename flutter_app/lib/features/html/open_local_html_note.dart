import '../../core/local_html_note_attachments.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/local_html_scope.dart';
export '../../core/local_html_scope.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/html_editor_controller.dart';
import '../../core/html_recovery_vault.dart';
import '../../core/local_html_notes_repository.dart';
import '../../core/local_store.dart';
import '../../core/labels_repository.dart';
import '../../core/native_recovery_storage.dart';
import 'html_editor_lease.dart';
import 'html_code_source_surface.dart';
import 'html_note_page.dart';
import 'html_preview.dart';
import 'local_html_preview_panel.dart';

Future<bool> openLocalHtmlNote(
  BuildContext context, {
  required LocalStore store,
  required int id,
  required String collection,
  bool english = false,
  bool Function()? isCurrentScope,
  bool observed = false,
  ComplexSourceIoScope? sourceIoScope,
  HtmlRecoveryVault? recoveryVault,
  HtmlSourceSurfaceBuilder sourceSurfaceBuilder = defaultHtmlSourceSurface,
  HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder,
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
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['local', store.path, collection, id]),
  );
  if (lease == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            '这篇 HTML 已在编辑中，请返回已打开的页面。',
            'This HTML note is already open. Return to its editor.',
          ),
        ),
      ),
    );
    return false;
  }
  final repository = LocalHtmlNotesRepository(
    store,
    collection: collection,
    isCurrentScope: current,
  );
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      sharedPreferencesName: NativeRecoveryStorage.preferencesName,
    ),
  );
  final vault =
      recoveryVault ??
      HtmlRecoveryVault(
        localDatabase: true,
        maintenance: store.maintenance,
        server: localHtmlRecoveryScope(store.path),
        memberId: 1,
        collection: collection,
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
  HtmlEditorController? controller;
  LocalHtmlNoteAttachments? localAttachments;
  var localAttachmentsUnavailable = false;
  var transferred = false;
  try {
    final note = await repository.read(id);
    if (!context.mounted || !current()) return false;
    HtmlRecoveryRecord? record;
    try {
      record = await vault.read(id);
    } on FormatException {
      if (!context.mounted || !current()) return false;
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('本机恢复记录无法读取', 'Recovery record could not be read')),
          content: Text(
            t(
              '原记录不会自动删除。删除后将打开本机已保存的版本。',
              'The record will not be deleted automatically. Removing it opens the saved device version.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('删除损坏的本机记录', 'Remove damaged device record')),
            ),
          ],
        ),
      );
      if (!current() || remove != true) return false;
      await vault.remove(id);
    }
    if (!context.mounted || !current()) return false;
    if (record != null && record.protected) {
      throw const FormatException(
        'Protected remote record cannot be opened as local HTML',
      );
    }
    if (record != null && !record.pending) {
      if (!context.mounted) return false;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('发现未保存的 HTML 草稿', 'Unsaved HTML draft found')),
          content: Text(
            t(
              '恢复草稿不会修改已保存的内容。有更新时会先展示冲突。',
              'Restoring does not change saved content. Any changed baseline will open for review.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(
                t('放弃草稿，打开已保存版本', 'Discard draft and open saved version'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      if (!current() || choice == null) return false;
      if (choice == 'discard') {
        await vault.remove(id);
        record = null;
      }
    }
    if (!context.mounted || !current()) return false;
    final editor = record == null
        ? HtmlEditorController(
            repository,
            note,
            recovery: vault,
            observed: observed,
          )
        : HtmlEditorController.restore(
            repository,
            note,
            record,
            recovery: vault,
          );
    controller = editor;
    if (!await editor.flushRecovery()) {
      throw StateError(
        t(
          '本机恢复记录更新失败，请稍后重试。',
          'Recovery storage could not be updated. Retry later.',
        ),
      );
    }
    if (!context.mounted || !current()) return false;
    final fileOwner = sourceIoScope;
    if (fileOwner != null) {
      try {
        localAttachments = await LocalHtmlNoteAttachments.open(
          store: store, editor: editor, sourceOwner: fileOwner,
          isCurrentScope: current,
        );
      } catch (_) {
        // Body editing keeps its original strict repository. File capability is
        // explicitly unavailable, never replaced by account/network access.
        localAttachmentsUnavailable = true;
      }
    }
    if (!context.mounted || !current()) return false;
    var pageBuilt = false;
    final pageRoute = MaterialPageRoute<void>(
      builder: (_) {
        pageBuilt = true;
        return HtmlNotePage(
          controller: editor,
          labels: LocalLabelsRepository(store),
          english: english,
          local: true,
          sourceIoScope: sourceIoScope,
          localHtmlAttachments: localAttachments,
          localAttachmentsUnavailable: localAttachmentsUnavailable,
          localInteractiveAvailable:
              !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
          onDisposed: lease.release,
          sourceSurfaceBuilder: sourceSurfaceBuilder,
          readOnlySourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
          fullPreviewBuilder: (_, source) =>
              !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? LocalHtmlPreviewHost(
                  store: store,
                  noteId: id,
                  collection: collection,
                  source: source,
                  english: english,
                  isCurrentScope: current,
                  baselineFingerprint: htmlNoteFingerprint(editor.baseline),
                  sourceIoScope: sourceIoScope,
                )
              : NativeHtmlPreview(source: source, english: english),
        );
      },
    );
    if (!context.mounted || !current()) return false;
    final result = Navigator.of(context).push<void>(pageRoute);
    transferred = true;
    unawaited(
      pageRoute.completed.then((_) {
        if (!pageBuilt) {
          final files = localAttachments;
          if (files != null) unawaited(files.retireAndDrain());
          editor.dispose();
          lease.release();
        }
      }),
    );
    await result;
    return true;
  } finally {
    if (!transferred) {
      await localAttachments?.retireAndDrain();
      controller?.dispose();
      repository.dispose();
      lease.release();
    }
  }
}
