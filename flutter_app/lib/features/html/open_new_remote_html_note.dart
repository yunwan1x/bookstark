import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/html_creation_vault.dart';
import '../../core/html_recovery_vault.dart';
import '../../core/api_client.dart';
import '../../core/remote_html_creation_controller.dart';
import '../../core/remote_html_creation_repository.dart';
import '../../core/labels_repository.dart';
import '../../core/native_recovery_storage.dart';
import 'remote_html_create_page.dart';
import 'html_note_page.dart';
import 'html_editor_lease.dart';
import 'html_code_source_surface.dart';
import 'open_html_note.dart';

Future<bool> openNewRemoteHtmlNote(
  BuildContext context, {
  required BookstarkClient client,
  required String collection,
  bool english = false,
  bool Function()? isCurrentScope,
  HtmlCreationVault? creationVault,
  HtmlRecoveryVault? noteRecoveryVault,
  HtmlSourceSurfaceBuilder sourceSurfaceBuilder = defaultHtmlSourceSurface,
  HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder,
}) async {
  String t(String zh, String en) => english ? en : zh;
  final session = client.exportSession()['token'];
  final revision = client.sessionRevision;
  void guard() {
    if (!(isCurrentScope?.call() ?? true) ||
        session == null ||
        session.isEmpty ||
        client.exportSession()['token'] != session ||
        client.sessionRevision != revision) {
      throw StateError('HTML creation owner session ended');
    }
  }

  guard();
  final profile = await client.profileSettingsJson();
  guard();
  final owner = profile['member_id'];
  if (owner is! int || owner <= 0) throw StateError('HTML owner required');
  if (!context.mounted) return false;
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['remote-new', client.baseUri.toString(), owner, collection]),
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
  final repository = RemoteHtmlCreationRepository(
    client,
    memberId: owner,
    collection: collection,
  );
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      sharedPreferencesName: NativeRecoveryStorage.preferencesName,
    ),
  );
  final vault =
      creationVault ??
      HtmlCreationVault(
        server: client.baseUri,
        memberId: owner,
        collection: collection,
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
  RemoteHtmlCreationController? controller;
  var transferred = false;
  try {
    Object? record;
    try {
      record = await vault.readRecovery();
      guard();
    } on FormatException {
      if (!context.mounted) return false;
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('新建草稿记录无法读取', 'Creation record could not be read')),
          content: Text(
            t(
              '原记录不会自动删除。删除后无法继续用它核对上次新建结果，请先查看服务器笔记。',
              'The record will not be deleted automatically. Removing it prevents further review of that creation. Check your saved server notes first.',
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
      if (remove != true || !context.mounted) return false;
      await vault.remove();
    }
    guard();
    if (!context.mounted) return false;
    final editor = RemoteHtmlCreationController(
      repository,
      vault,
      record: record,
    );
    controller = editor;
    var built = false;
    final pageRoute = MaterialPageRoute<int>(
      builder: (_) {
        built = true;
        return RemoteHtmlCreatePage(
          controller: editor,
          labels: RemoteLabelsRepository(client),
          serverLabel: client.baseUri.toString(),
          english: english,
          onDisposed: lease.release,
          sourceSurfaceBuilder: sourceSurfaceBuilder,
          readOnlySourceSurfaceBuilder: readOnlySourceSurfaceBuilder,
        );
      },
    );
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
    if (id == null || !context.mounted) return false;
    guard();
    return await openHtmlNote(
      context,
      client: client,
      id: id,
      collection: collection,
      english: english,
      recoveryVault: noteRecoveryVault,
      creationObserved: !editor.receiptKnown,
      isCurrentScope: isCurrentScope,
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
