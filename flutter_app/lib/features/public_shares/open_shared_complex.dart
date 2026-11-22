import '../../core/attachments.dart';
import '../../core/protected_shared_markdown_controller.dart';
import '../../core/protected_shared_markdown_repository.dart';
import 'share_edit_page.dart';
import '../../core/protected_shared_complex_session.dart';
import '../../core/protected_shared_identity.dart';
import '../../core/protected_shared_journal.dart';
import '../../core/protected_shared_lifetime.dart';
import '../../core/protected_shared_services.dart';
import 'protected_shared_record_actions.dart';
import 'protected_shared_review_page.dart';
import 'protected_shared_routes.dart';
import '../../core/native_complex_source_io.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/anonymous_shared_capability.dart';
import '../../core/public_complex_source.dart';
import '../../core/public_edit_link.dart';
import '../../core/shared_complex_session.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_recovery_store.dart';
import '../../core/local_complex_editor_controller.dart';
import '../html/html_editor_lease.dart';
import '../complex_editors/local_complex_note_page.dart';

/// False ONLY for existing Markdown dispatch. All six complex outcomes, including
/// cancelled/locked/unavailable, are handled without a fallback owner editor.
Future<bool> openSharedComplex(
  BuildContext context, {
  required PublicEditLink link,
  required bool Function() isCurrentScope,
  Future<void> Function()? onReturnToReader,
  ComplexRecoveryBytesStore? recoveryStore,
  ComplexSourceIoScope? sourceIoScope,
  ProtectedSharedServices? protectedServices,
  AttachmentRepository? markdownAttachments,
  AnonymousSharedCapability Function(PublicEditLink, bool Function())?
  capabilityFactory,
  AnonymousPublicComplexSource Function(bool Function())? sourceFactory,
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

  if (!context.mounted || !current()) return true;
  final probe =
      sourceFactory?.call(current) ??
      AnonymousPublicComplexSource(isCurrent: current);
  AnonymousSharedCapability? transport;
  SharedComplexSession? session;
  ProtectedSharedLifetime? protectedOwner;
  ProtectedSharedComplexSession? protectedSession;
  LocalComplexEditorController? controller;
  HtmlEditorLease? lease;
  var transferred = false;
  try {
    final identity = await probe.inspect(link.reference);
    if (!context.mounted || !current()) return true;
    if (identity.markdown && protectedServices == null) return false;
    final kind = ComplexEditorKind.parse(identity.format);
    if (!identity.markdown &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android)) {
      throw StateError('Android editor required');
    }
    lease = HtmlEditorLease.acquire(
      context,
      'shared-complex:${sha256.convert(utf8.encode(link.requestPath))}',
    );
    if (lease == null) throw StateError('Shared editor already open');
    final owned = transport =
        capabilityFactory?.call(link, current) ??
        AnonymousSharedCapability(link, isCurrent: current);
    final services = protectedServices;
    if (services != null) {
      final owner = ProtectedSharedLifetime(
        transport: owned,
        isCurrentScope: current,
        onDrained: services.unregisterOwner,
      );
      protectedOwner = owner;
      services.registerOwner(
        owner,
      ); // Before any password dialog/engine awaits.
      if (!owner.current) throw StateError('Shared owner retired');
    }
    SharedCapabilitySource source;
    String? password;
    try {
      source = await owned.read();
    } on SharedCapabilityFailure catch (error) {
      if (error.status != 423) rethrow;
      if (!context.mounted || !current()) return true;
      final owner = protectedOwner;
      final dialog = DialogRoute<(SharedCapabilitySource, String)>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SharedUnlock(
          transport: owned,
          title: identity.title,
          english: english,
          isCurrent: () => current() && (owner?.current ?? true),
          canReturnToReader: onReturnToReader != null,
        ),
      );
      final unlocked = owner == null
          ? await Navigator.of(context).push(dialog)
          : await pushProtectedSharedRoute<(SharedCapabilitySource, String)>(
              context,
              owner,
              dialog,
            );
      if (unlocked == null) {
        if (current()) await onReturnToReader?.call();
        return true;
      }
      if (!context.mounted || !current()) return true;
      source = unlocked.$1;
      password = unlocked.$2;
    }
    if (source.identity.targetId != identity.targetId ||
        source.identity.shareId != identity.shareId ||
        source.identity.kind != kind ||
        source.identity.protected != identity.protected ||
        source.identity.shareType != identity.kind.name) {
      throw StateError('Shared identity changed');
    }
    final owner = protectedOwner;
    ProtectedSharedJournal? journal;
    if (owner != null && services != null) {
      journal = ProtectedSharedJournal(
        capabilityPrincipal: ProtectedSharedJournal.capabilityFor(
          server: link.reference.server.toString(),
          shareId: source.identity.shareId,
          capabilityHash: sha256
              .convert(utf8.encode(link.requestPath))
              .toString(),
        ),
        identity: protectedSharedIdentity(source.identity),
        isCurrent: () => owner.current,
        listKeys: services.listKeys,
        readValue: services.readValue,
        writeValue: services.writeValue,
        deleteValue: services.deleteValue,
        flush: services.flush,
      );
      owner.bindJournal(journal);
      final records = await journal.loadGroup();
      if (!context.mounted || !owner.current) return true;
      if (records.isNotEmpty) {
        final rememberedPassword = password;
        await pushProtectedSharedRoute<bool>(
          context,
          owner,
          MaterialPageRoute<bool>(
            builder: (_) => ProtectedSharedReviewPage(
              owner: owner,
              journal: journal!,
              initial: source,
              records: records,
              readFresh: () => owned.read(password: rememberedPassword),
              server: link.reference.server,
              english: english,
            ),
          ),
        );
        return true; // Reopen fresh after explicit ending; never reuse an old body.
      }
    }
    if (source.identity.kind == ComplexEditorKind.markdown) {
      if (!source.identity.protected) return false;
      if (owner == null || journal == null || markdownAttachments == null) {
        throw StateError(
          'Protected Markdown storage/attachment services required',
        );
      }
      final rememberedPassword = password;
      final repository = ProtectedSharedMarkdownRepository(
        owner: owner,
        journal: journal,
        initial: source,
        password: rememberedPassword,
      );
      final markdownController = ProtectedSharedMarkdownController(
        repository,
        link,
        journal: journal,
      );
      try {
        await markdownController.initialize(password: rememberedPassword);
        if (!context.mounted || !owner.current) return true;
        await pushProtectedSharedRoute<void>(
          context,
          owner,
          MaterialPageRoute<void>(
            builder: (_) => ShareEditPage(
              controller: markdownController,
              attachments: markdownAttachments,
              english: english,
              registerPreview: owner.registerPreview,
              unregisterPreview: owner.unregisterPreview,
              retentionNotice: t(
                '正文仅保留在本次内存。关闭后未保存正文无法恢复；恢复存储仅含不含正文的提交核对记录。',
                'Body remains only in this session memory. Unsaved body cannot be recovered after closing. Recovery storage retains only a submission review record without the body.',
              ),
              retentionActionsBuilder: () => ProtectedSharedRecordActions(
                owner: owner,
                journal: journal!,
                readFresh: () => owned.read(password: rememberedPassword),
                english: english,
              ),
            ),
          ),
        );
      } finally {
        markdownController.close();
      }
      return true;
    }
    if (source.identity.protected) {
      if (owner == null || journal == null) {
        throw StateError('Protected shared storage services required');
      }
      final rememberedPassword = password;
      final protectedEditorSession = await ProtectedSharedComplexSession.open(
        owner: owner,
        journal: journal,
        initial: source,
        password: rememberedPassword,
      );
      protectedSession = protectedEditorSession;
      final editor = protectedEditorSession.controller;
      controller = editor;
      if (!context.mounted || !owner.current) return true;
      final ownedLease = lease;
      var built = false;
      final route = MaterialPageRoute<void>(
        builder: (_) {
          built = true;
          return LocalComplexNotePage(
            controller: editor,
            english: english,
            documentBodyOnly: true,
            anonymousSharedServer: link.reference.server,
            sourceIoScope: sourceIoScope,
            retirementController: owner.preview,
            renewRetirementController: () async {
              await owner.nextPreview();
              return owner.preview;
            },
            originLabel: t('受保护的共享编辑', 'Protected shared editing'),
            retentionNotice: t(
              '正文仅保留在本次内存。关闭后未保存正文无法恢复；恢复存储仅含不含正文的提交核对记录。',
              'Body remains only in this session memory. Unsaved body cannot be recovered after closing. Recovery storage retains only a submission review record without the body.',
            ),
            retentionActions: ProtectedSharedRecordActions(
              owner: owner,
              journal: journal!,
              controller: editor,
              readFresh: () => owned.read(password: rememberedPassword),
              english: english,
            ),
          );
        },
      );
      transferred = true;
      unawaited(
        route.completed.then((_) {
          if (!built) editor.dispose();
          ownedLease.release();
        }),
      );
      await pushProtectedSharedRoute<void>(context, owner, route);
      return true;
    }
    session = await SharedComplexSession.inspect(
      transport: owned,
      initial: source,
      password: password,
      isCurrent: current,
      recoveryStore: recoveryStore,
    );
    password = null;
    if (!context.mounted || !current()) return true;
    var choice = SharedComplexDraftChoice.restore;
    if (session.requiresChoice) {
      final choiceRoute = DialogRoute<SharedComplexDraftChoice>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('发现本机草稿', 'Local draft found')),
          content: SingleChildScrollView(
            child: Text(
              t(
                '恢复仅加载本机草稿，仍需明确保存。编辑令牌和密码不会写入恢复记录。',
                'Restore loads only the local draft; saving remains explicit. Editing token and password are never stored in recovery.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialog, SharedComplexDraftChoice.cancel),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialog, SharedComplexDraftChoice.discard),
              child: Text(t('放弃草稿', 'Discard draft')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialog, SharedComplexDraftChoice.restore),
              child: Text(t('恢复草稿', 'Restore draft')),
            ),
          ],
        ),
      );
      final selected = owner == null
          ? await Navigator.of(context).push(choiceRoute)
          : await pushProtectedSharedRoute<SharedComplexDraftChoice>(
              context,
              owner,
              choiceRoute,
            );
      if (selected == null ||
          selected == SharedComplexDraftChoice.cancel ||
          !current()) {
        return true;
      }
      choice = selected;
    }
    final editor = await session.enter(choice);
    if (editor == null) return true;
    controller = editor;
    if (!context.mounted || !current()) return true;
    var built = false;
    final ownedSession = session, ownedLease = lease;
    final route = MaterialPageRoute<void>(
      builder: (_) {
        built = true;
        return LocalComplexNotePage(
          controller: editor,
          english: english,
          documentBodyOnly: true,
          retirementController: owner?.preview,
          renewRetirementController: owner == null
              ? null
              : () async {
                  await owner.nextPreview();
                  return owner.preview;
                },
          anonymousSharedServer: link.reference.server,
          sourceIoScope: sourceIoScope,
          originLabel: t('共享编辑', 'Shared editing'),
        );
      },
    );
    final done = owner == null
        ? Navigator.of(context).push<void>(route)
        : pushProtectedSharedRoute<void>(context, owner, route);
    transferred = true;
    unawaited(
      route.completed.then((_) {
        if (!built) editor.dispose();
        ownedSession.retire();
        ownedLease.release();
      }),
    );
    await done;
    return true;
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法打开此共享编辑。请核对能力、密码或服务器版本；原文和本机草稿均保留。',
              'Unable to open shared editing. Check capability, password or server version. Source and local draft are retained.',
            ),
          ),
        ),
      );
    }
    return true;
  } finally {
    probe.close();
    // Includes pre-editor password/review routes and exact native preview drain.
    // Do not let a late anonymous response survive Root's principal barrier.
    if (protectedSession != null) {
      await protectedSession.retire();
    } else if (protectedOwner != null) {
      await protectedOwner.retire();
    }
    if (!transferred) {
      controller?.dispose();
      session?.retire();
      transport?.close();
      lease?.release();
    }
  }
}

class _SharedUnlock extends StatefulWidget {
  const _SharedUnlock({
    required this.transport,
    required this.title,
    required this.english,
    required this.isCurrent,
    required this.canReturnToReader,
  });
  final AnonymousSharedCapability transport;
  final String title;
  final bool english, canReturnToReader;
  final bool Function() isCurrent;
  @override
  State<_SharedUnlock> createState() => _UnlockState();
}

class _UnlockState extends State<_SharedUnlock> {
  final password = TextEditingController();
  bool busy = false, visible = false, failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || password.text.isEmpty || !widget.isCurrent()) return;
    final value = password.text;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final source = await widget.transport.read(password: value);
      if (!mounted || !widget.isCurrent()) return;
      password.clear();
      Navigator.pop(context, (source, value));
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('解锁共享编辑', 'Unlock shared editing')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          Text(
            t(
              '密码和编辑令牌不会传给画布',
              'Password and editing token never enter the canvas',
            ),
          ),
          TextField(
            controller: password,
            obscureText: !visible,
            enabled: !busy,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: t('内容密码', 'Content password'),
              suffixIcon: IconButton(
                tooltip: t('显示或隐藏密码', 'Show or hide password'),
                onPressed: busy
                    ? null
                    : () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          if (failed)
            Text(
              t(
                '无法解锁，请核对密码、权限和网络',
                'Unable to unlock; check password, permission and connection',
              ),
            ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(
          widget.canReturnToReader
              ? t('返回只读', 'Return to read-only')
              : t('取消', 'Cancel'),
        ),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(t('解锁编辑', 'Unlock editing')),
      ),
    ],
  );
}
