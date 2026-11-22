import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';
import '../../core/file_draft_vault.dart';
import '../../core/file_editor_controller.dart';
import '../../core/drive_attachments.dart';
import '../../widgets/file_text_field.dart';
import '../../widgets/bookstark_markdown.dart';

class FileEditorPage extends StatefulWidget {
  const FileEditorPage({
    super.key,
    required this.repository,
    required this.file,
    required this.vault,
  });
  final DriveRepository repository;
  final DriveNode file;
  final FileDraftVault vault;
  @override
  State<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<FileEditorPage> {
  late final session = FileEditorController(widget.repository, widget.vault);
  final text = TextEditingController();
  final undo = UndoHistoryController();
  Timer? debounce;
  Future<void> chain = Future.value();
  Object? error;
  bool working = true, preview = false, leaving = false, changed = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await session.load(widget.file);
      if (mounted) text.text = session.content;
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> persist() {
    final value = text.text;
    final next = chain.then((_) async {
      if (session.content != value || session.draft?.content != value) {
        await session.edit(value);
      }
    });
    chain = next.catchError((Object e) {
      if (mounted) setState(() => error = e);
    });
    return next;
  }

  void edited(String _) {
    setState(() {
      changed = true;
      error = null;
    });
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(persist().catchError((Object _) {}));
    });
  }

  Future<void> action(Future<void> Function() callback) async {
    if (working) return;
    debounce?.cancel();
    setState(() {
      working = true;
      error = null;
    });
    try {
      await callback();
    } catch (e) {
      error = e;
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> save() => action(() async {
    await persist();
    await session.save();
    changed = true;
  });
  Future<void> review() => action(() async {
    final current = await widget.repository.lookup(widget.file.path);
    if (current == null || current.id != widget.file.id) {
      throw const FormatException('文件已移动、删除或被替换');
    }
    final actual = await widget.repository.readText(current);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('比较文件版本'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(actual.node.isPublic ? '当前文件已公开，保存会更新公开内容。' : '当前文件未公开。'),
            const Text('服务端当前内容'),
            SelectableText(actual.content),
            const Divider(),
            const Text('我的草稿'),
            SelectableText(text.text),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留草稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('采用此基准继续编辑'),
          ),
        ],
      ),
    );
    if (accepted == true) await session.acceptReviewedBase(actual);
  });
  Future<void> close() async {
    if (working || leaving) return;
    debounce?.cancel();
    if (session.document != null &&
        (text.text != session.document!.content ||
            session.pendingHash != null ||
            session.cleanupPending)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('离开编辑？'),
          content: const Text('可保留草稿稍后继续。待确认的保存不会自动重发。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('保留草稿并离开'),
            ),
          ],
        ),
      );
      if (choice != 'keep') return;
      if (session.writable) {
        try {
          await persist();
        } catch (e) {
          if (mounted) setState(() => error = e);
          return;
        }
      }
    }
    await chain;
    if (mounted) {
      setState(() => leaving = true);
      Navigator.pop(context, changed);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    text.dispose();
    undo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = session.document != null;
    final editable = ready && !working && session.writable;
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '关闭',
            onPressed: working ? null : close,
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.file.name),
          actions: [
            TextButton(
              onPressed: editable && text.text != session.document!.content
                  ? save
                  : null,
              child: const Text('保存'),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (working) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  '$error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!ready && !working)
              Center(
                child: FilledButton(
                  onPressed: load,
                  child: const Text('重新读取文件'),
                ),
              ),
            if (ready) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (session.document!.node.isPublic)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('此文件已公开，保存会更新公开地址的内容。'),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ValueListenableBuilder<UndoHistoryValue>(
                      valueListenable: undo,
                      builder: (context, value, _) => Row(
                        children: [
                          IconButton(
                            tooltip: '撤销',
                            onPressed: editable && value.canUndo
                                ? () {
                                    undo.undo();
                                    edited(text.text);
                                  }
                                : null,
                            icon: const Icon(Icons.undo),
                          ),
                          IconButton(
                            tooltip: '重做',
                            onPressed: editable && value.canRedo
                                ? () {
                                    undo.redo();
                                    edited(text.text);
                                  }
                                : null,
                            icon: const Icon(Icons.redo),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => preview = !preview),
                      child: Text(preview ? '编辑' : '预览'),
                    ),
                    if (session.pendingHash != null)
                      TextButton(
                        onPressed: working
                            ? null
                            : () => action(() async {
                                await session.verifyPending();
                              }),
                        child: const Text('核对保存结果'),
                      ),
                    if (session.conflict)
                      TextButton(
                        onPressed: working ? null : review,
                        child: const Text('比较版本'),
                      ),
                    if (session.cleanupPending)
                      TextButton(
                        onPressed: working
                            ? null
                            : () => action(session.retryCleanup),
                        child: const Text('重试清理草稿'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: preview
                    ? BookstarkMarkdown(
                        scrollable: true,
                        data: text.text,
                        attachments: DriveAttachments(
                          widget.repository,
                          directory: driveParent(widget.file.path),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (_) => false,
                        child: FileTextField(
                          controller: text,
                          undoController: undo,
                          enabled: editable,
                          onChanged: edited,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'UTF-8${session.document!.hasBom ? ' BOM' : ''} · ${session.document!.encode(text.text).length} 字节 · ${session.pendingHash != null
                      ? '保存待核对'
                      : session.cleanupPending
                      ? '已保存，草稿待清理'
                      : text.text != session.document!.content
                      ? '未保存'
                      : '已保存'}',
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
