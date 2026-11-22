import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/html_creation_vault.dart';
import '../../core/html_recovery_vault.dart';
import '../../core/local_html_creation_controller.dart';
import '../../core/local_html_notes_repository.dart';
import '../../core/local_store.dart';
import '../../core/labels_repository.dart';
import '../../core/native_recovery_storage.dart';
import 'html_create_page.dart';
import 'html_note_page.dart';
import 'html_editor_lease.dart';
import 'html_code_source_surface.dart';
import 'open_local_html_note.dart';

Future<bool> openNewLocalHtmlNote(
  BuildContext context, {
  required LocalStore store,
  required String collection,
  bool english = false,
  bool Function()? isCurrentScope,
  HtmlCreationVault? creationVault,
  HtmlRecoveryVault? noteRecoveryVault,
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
    jsonEncode(['local-new', store.path, collection]),
  );
  if (lease == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            '已有HTML新建页面，请返回该页面。',
            'An HTML creation page is already open. Return to it.',
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
      creationVault ??
      HtmlCreationVault(
        server: localHtmlRecoveryScope(store.path),
        memberId: 1,
        collection: collection,
        localDatabase: true,
        maintenance: store.maintenance,
        readValue: (k) => storage.read(key: k),
        writeValue: (k, v) async {
          await storage.write(key: k, value: v);
          await NativeRecoveryStorage.flush();
        },
        deleteValue: (k) async {
          await storage.delete(key: k);
          await NativeRecoveryStorage.flush();
        },
      );
  LocalHtmlCreationController? controller;
  var transferred = false;
  try {
    HtmlCreationRecord? record;
    try {
      record = await vault.read();
    } on FormatException {
      if (!context.mounted || !current()) return false;
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('新建草稿记录无法读取', 'Creation record could not be read')),
          content: Text(
            t(
              '原记录不会自动删除。删除后无法继续用它核对上次新建结果，请先查看本机笔记。',
              'The record will not be deleted automatically. Removing it prevents further review of that creation. Check your saved device notes first.',
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
      if (remove != true || !current()) return false;
      await vault.remove();
    }
    if (!context.mounted || !current()) return false;
    final editor = LocalHtmlCreationController(
      repository,
      vault,
      record: record,
    );
    controller = editor;
    var built = false;
    final pageRoute = MaterialPageRoute<int>(
      builder: (_) {
        built = true;
        return HtmlCreatePage(
          controller: editor,
          labels: LocalLabelsRepository(store),
          english: english,
          onDisposed: lease.release,
          sourceSurfaceBuilder: sourceSurfaceBuilder,
          readOnlySourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
        );
      },
    );
    if (!context.mounted || !current()) return false;
    final result = Navigator.of(context).push<int>(pageRoute);
    transferred = true;
    unawaited(
      pageRoute.completed.then((_) {
        if (!built) {
          editor.dispose();
          lease.release();
        }
      }),
    );
    final id = await result;
    if (id == null || !context.mounted || !current()) return false;
    return await openLocalHtmlNote(
      context,
      store: store,
      id: id,
      collection: collection,
      english: english,
      recoveryVault: noteRecoveryVault,
      observed: !editor.receiptKnown,
      isCurrentScope: current,
      sourceSurfaceBuilder: sourceSurfaceBuilder,
      readOnlySourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
    );
  } finally {
    if (!transferred) {
      controller?.dispose();
      repository.dispose();
      lease.release();
    }
  }
}
