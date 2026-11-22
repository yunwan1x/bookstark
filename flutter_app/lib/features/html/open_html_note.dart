import 'package:bookstark_flutter/core/complex_editor_document.dart';

import 'package:bookstark_flutter/core/complex_editor_transport.dart';

import '../../core/owned_html_note_images.dart';
import '../complex_editors/complex_editor_browser.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
import '../../core/html_notes_repository.dart';
import '../../core/html_editor_controller.dart';
import '../../core/html_recovery_vault.dart';
import '../../core/native_recovery_storage.dart';
import '../../core/labels_repository.dart';
import '../notes/note_unlock_dialog.dart';
import 'html_note_page.dart';
import 'html_editor_lease.dart';
import 'html_code_source_surface.dart';
import 'html_browser_preview.dart';
import 'html_recovery_review.dart';

Future<bool> openHtmlNote(
  BuildContext context, {
  required BookstarkClient client,
  required int id,
  required String collection,
  bool english = false,
  bool creationObserved = false,
  bool Function()? isCurrentScope,
  HtmlRecoveryVault? recoveryVault,
  Widget Function(BuildContext, String)? fullPreviewBuilder,
  HtmlSourceSurfaceBuilder sourceSurfaceBuilder = defaultHtmlSourceSurface,
  HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder,
}) async {
  String t(String zh, String en) => english ? en : zh;
  final session = client.exportSession()['token'];
  final revision = client.sessionRevision;
  bool current() {
    try {
      return context.mounted && (isCurrentScope?.call() ?? true);
    } catch (_) {
      return false;
    }
  }

  void guard() {
    if (!current() ||
        session == null ||
        session.isEmpty ||
        client.exportSession()['token'] != session ||
        client.sessionRevision != revision) {
      throw StateError('HTML owner session ended');
    }
  }

  guard();
  final profile = await client.profileSettingsJson();
  final owner = profile['member_id'];
  if (owner is! int || owner <= 0) throw StateError('HTML owner required');
  guard();
  if (!context.mounted) return false;
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      sharedPreferencesName: NativeRecoveryStorage.preferencesName,
    ),
  );
  final vault =
      recoveryVault ??
      HtmlRecoveryVault(
        server: client.baseUri,
        memberId: owner,
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
  final repository = RemoteHtmlNotesRepository(
    client,
    memberId: owner,
    collection: collection,
  );
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode([
      'remote',
      BookstarkClient.normalizeServer(client.baseUri.toString()).toString(),
      owner,
      collection,
      id,
    ]),
  );
  if (lease == null) {
    repository.dispose();
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
  Widget browser(BuildContext context, String source) =>
      fullPreviewBuilder?.call(context, source) ??
      HtmlBrowserPreview(client: client, source: source, english: english);
  OwnedHtmlNoteImages? activeImages;
  var transferred = false;
  HtmlEditorController? unownedController;
  try {
    HtmlNote? note;
    try {
      note = await repository.read(id);
    } on HtmlNoteLocked {
      if (!context.mounted) return false;
      note = await showDialog<HtmlNote>(
        context: context,
        barrierDismissible: false,
        builder: (_) => NoteUnlockDialog<HtmlNote>(
          english: english,
          onUnlock: (password) => repository.read(id, password: password),
        ),
      );
    }
    guard();
    if (!context.mounted || note == null) return false;
    HtmlRecoveryRecord? record;
    try {
      record = await vault.read(id);
    } on FormatException {
      if (!context.mounted) return false;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('本机恢复记录无法读取', 'Recovery record could not be read')),
          content: Text(
            t(
              '原记录不会自动删除。删除后将打开服务器上的版本。',
              'The record will not be deleted automatically. Removing it opens the server version.',
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
      guard();
      if (discard != true) return false;
      await vault.remove(id);
    }
    guard();
    if (!context.mounted) return false;
    var observed = creationObserved;
    if (record != null && record.protected) {
      final adopt = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => HtmlRecoveryReviewPage(
            note: note!,
            record: record!,
            english: english,
            sourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
          ),
        ),
      );
      guard();
      if (adopt != true || !context.mounted) return false;
      final latest = await repository.read(id, password: note.unlockPassword);
      guard();
      if (!latest.metadata.same(note.metadata) ||
          htmlNoteFingerprint(latest) != htmlNoteFingerprint(note)) {
        throw const HtmlNoteChanged();
      }
      await vault.remove(id);
      note = latest;
      record = null;
      observed = true;
    } else if (record != null && !record.pending) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('发现未保存的 HTML 草稿', 'Unsaved HTML draft found')),
          content: Text(
            t(
              '恢复草稿不会修改服务器。服务器有更新时会先展示冲突。',
              'Restoring does not change the server. Any changed baseline will open for review.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(t('放弃草稿，打开服务器版本', 'Discard draft and open server')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      guard();
      if (choice == null) return false;
      if (choice == 'discard') {
        await vault.remove(id);
        record = null;
      }
    }
    guard();
    if (!context.mounted) return false;
    final controller = record == null
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
    unownedController = controller;
    // Convert a formerly ordinary draft to digest-only storage as soon as a
    // protected server baseline is observed, before exposing any editable page.
    if (!await controller.flushRecovery()) {
      controller.dispose();
      throw StateError(
        t(
          '本机恢复记录更新失败，请稍后重试。',
          'Recovery storage could not be updated. Retry later.',
        ),
      );
    }
    guard();
    if (!context.mounted) {
      controller.dispose();
      return false;
    }
    final images = OwnedHtmlNoteImages(
      client: client,
      memberId: owner,
      resourceId: id,
      namespace: 'remote-html-v1',
      isCurrent: () =>
          current() &&
          client.sessionRevision == revision &&
          client.exportSession()['token'] == session,
      editor: controller,
    );
    activeImages = images;
    await images.open();
    guard();
    if (!context.mounted) return false;
    Widget ownedSurface(
      BuildContext context, {
      required Key key,
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required bool readOnly,
      required Future<void> Function(ComplexEditorTransport) onReady,
      required void Function(ComplexEditorState) onState,
      required Future<void> Function() onSaveRequested,
      required Future<void> Function(ComplexEditorTransport) beforeRetire,
      required Future<void> Function() onReloadRequested,
      required Future<void> Function(Uri) onExternalLink,
    }) => ComplexEditorBrowser(
      key: key,
      document: document,
      title: title,
      english: english,
      readOnly: readOnly,
      ownedResourceFactory: images.resourceFactory,
      onReady: onReady,
      onState: onState,
      onSaveRequested: onSaveRequested,
      beforeRetire: beforeRetire,
      onReloadRequested: onReloadRequested,
      onExternalLink: onExternalLink,
    );
    var pageBuilt = false;
    final pageRoute = MaterialPageRoute<void>(
      builder: (_) {
        pageBuilt = true;
        return HtmlNotePage(
          controller: controller,
          labels: RemoteLabelsRepository(client),
          english: english,
          fullPreviewBuilder: browser,
          sourceSurfaceBuilder:
              identical(sourceSurfaceBuilder, defaultHtmlSourceSurface)
              ? ownedSurface
              : sourceSurfaceBuilder,
          ownedImages: images,
          readOnlySourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
          onDisposed: lease.release,
        );
      },
    );
    final route = Navigator.of(context).push<void>(pageRoute);
    transferred = true;
    unawaited(
      pageRoute.completed.then((_) {
        if (!pageBuilt) {
          unawaited(images.retireAndDrain());
          controller.dispose();
          lease.release();
        }
      }),
    );
    await route;
    await images.retireAndDrain();
    return true;
  } finally {
    if (!transferred) {
      await activeImages?.retireAndDrain();
      unownedController?.dispose();
      repository.dispose();
      lease.release();
    }
  }
}
