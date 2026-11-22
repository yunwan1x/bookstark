import '../../core/owned_preview_controller.dart';
import '../../core/app_theme.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/attachments.dart';
import '../../core/public_edit_controller.dart';
import '../../core/public_edit_snapshot.dart';
import '../../widgets/bookstark_markdown.dart';
import 'public_article_markdown_body.dart';
import 'shared_article_edit_page.dart';

enum _ConflictAction { remote, overwrite }

class ShareEditPage extends StatefulWidget {
  const ShareEditPage({
    super.key,
    required this.controller,
    required this.attachments,
    this.english = false,
    this.retentionNotice,
    this.retentionActionsBuilder,
    this.registerPreview,
    this.unregisterPreview,
  });
  final PublicEditController controller;
  final AttachmentRepository attachments;
  final bool english;
  final String? retentionNotice;
  final Widget Function()? retentionActionsBuilder;
  final void Function(OwnedPreviewController)? registerPreview,
      unregisterPreview;
  @override
  State<ShareEditPage> createState() => _ShareEditPageState();
}

class _ShareEditPageState extends State<ShareEditPage> {
  late final _text = TextEditingController(
    text: widget.controller.snapshot?.content ?? '',
  );
  final _undo = UndoHistoryController();
  bool _preview = false, _working = false, _leaving = false, _dialog = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  PublicEditController get _controller => widget.controller;
  bool get _editable =>
      !_working &&
      !_controller.busy &&
      {
        PublicEditPhase.ready,
        PublicEditPhase.acknowledged,
        PublicEditPhase.conflict,
      }.contains(_controller.phase);
  bool get _dirty => _text.text != _controller.snapshot?.content;
  String _lastText = '';
  @override
  void initState() {
    super.initState();
    _lastText = _text.text;
    _text.addListener(_changed);
  }

  void _changed() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _text.dispose();
    _undo.dispose();
    _controller.close();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('已复制本次内容', 'Local content copied'))),
      );
    }
  }

  Future<void> _leave() async {
    if (_working || _controller.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('正在核对或保存，请稍候。', 'Checking or saving. Please wait.')),
        ),
      );
      return;
    }
    final uncertain = {
      PublicEditPhase.unknown,
      PublicEditPhase.unverified,
      PublicEditPhase.conflict,
    }.contains(_controller.phase);
    if (_dirty || uncertain) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => _EditDialog(
          title: Text(t('离开共享编辑？', 'Leave shared editing?')),
          content: Text(
            uncertain
                ? t(
                    '保存结果仍需核对。本次内容和编辑能力只保留在当前会话，离开会清除内存记录。',
                    'The save still needs verification. Content and editing capability are kept only in this session and are cleared when you leave.',
                  )
                : t(
                    '本次修改尚未保存，离开将放弃这些修改。',
                    'Your changes have not been saved. Leaving discards them.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => _copy(),
              child: Text(t('复制本次内容', 'Copy local content')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续编辑', 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('离开', 'Leave')),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working || _controller.busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '操作未完成，请保留本次内容并核对权限、正文大小和网络。',
            'The action did not complete. Keep your content and check permission, content size and connection.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save({PublicEditSnapshot? observed}) async {
    if (!_editable) return;
    await _run(() => _controller.save(_text.text, overwriteObserved: observed));
    if (!mounted) return;
    if (_controller.phase == PublicEditPhase.conflict) await _conflict();
  }

  String _excerpt(String value) {
    final units = value.runes.take(6001).toList();
    return String.fromCharCodes(units.take(6000)) +
        (units.length > 6000
            ? t('\n（仅显示开头6000字）', '\n(First 6000 characters shown)')
            : '');
  }

  Future<void> _conflict() async {
    final observed = _controller.conflict;
    if (_dialog || observed == null) return;
    _dialog = true;
    FocusScope.of(context).unfocus();
    final action = await showDialog<_ConflictAction>(
      context: context,
      builder: (context) => _EditDialog(
        title: Text(t('远端正文已更新', 'Remote content has changed')),
        content: SizedBox(
          width: 540,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _controller.receipt == null
                    ? t(
                        '你的修改尚未覆盖远端。请先核对两个版本。',
                        'Your changes have not overwritten the remote content. Review both versions first.',
                      )
                    : t(
                        '已收到保存回执，但远端内容已再次变化。请核对当前版本。',
                        'A save receipt was received, but remote content has changed again. Review the current version.',
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                t('本次内容', 'Local content'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _versionBox(_excerpt(_text.text)),
              const SizedBox(height: 16),
              Text(
                t('当前远端', 'Current remote content'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _versionBox(_excerpt(observed.content)),
              const SizedBox(height: 16),
              Text(
                t(
                  '覆盖前会再次核对，但旧服务无法保证同时编辑时不互相覆盖。',
                  'The content is checked again before overwriting, but this server cannot guarantee atomic conflict protection.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  '关闭对话框会保留本次修改。',
                  'Closing this dialog keeps your local changes.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _copy,
            child: Text(t('复制本次内容', 'Copy local content')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _ConflictAction.remote),
            child: Text(t('载入远端', 'Load remote')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ConflictAction.overwrite),
            child: Text(t('确认覆盖', 'Confirm overwrite')),
          ),
        ],
      ),
    );
    _dialog = false;
    if (!mounted) return;
    if (action == _ConflictAction.remote) {
      _controller.acceptRemote();
      _text.text = _controller.snapshot!.content;
      setState(() => _error = null);
    }
    if (action == _ConflictAction.overwrite) await _save(observed: observed);
  }

  Widget _versionBox(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff0f3f8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: SingleChildScrollView(
        child: SelectableText(text, semanticsLabel: text),
      ),
    ),
  );
  Future<void> _verify() async {
    await _run(() => _controller.verify());
    if (!mounted) return;
    if (_controller.phase == PublicEditPhase.conflict) await _conflict();
  }

  Future<void> _retry() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _EditDialog(
        title: Text(t('核对后再次保存？', 'Save again after verification?')),
        content: Text(
          t(
            '刚才读取的远端仍为旧版本。再次保存前会重新核对，但上次请求可能曾到达服务端。',
            'The last read still showed the old version. It will be checked again before saving, but the previous request may have reached the server.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('再次保存', 'Save again')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _controller.acknowledgeRetry();
    setState(() {});
    await _save();
  }

  void _wrap(String before, String after) {
    if (!_editable) return;
    final value = _text.value;
    final start = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid ? value.selection.end : start;
    final selected = value.text.substring(start, end),
        insert = '$before$selected$after';
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, insert),
      selection: TextSelection(
        baseOffset: start + before.length,
        extentOffset: start + before.length + selected.length,
      ),
    );
    setState(() => _error = null);
  }

  String get _selectedText {
    final value = _text.value;
    return value.selection.isValid
        ? value.text.substring(value.selection.start, value.selection.end)
        : '';
  }

  void _replaceSelection(String replacement) {
    if (!_editable) return;
    final value = _text.value,
        start = value.selection.isValid
            ? value.selection.start
            : value.text.length,
        end = value.selection.isValid ? value.selection.end : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void _list() {
    if (!_editable) return;
    final value = _text.value,
        start = value.selection.isValid
            ? value.selection.start
            : value.text.length,
        end = value.selection.isValid ? value.selection.end : value.text.length;
    final lineStart = start == 0
        ? 0
        : value.text.lastIndexOf('\n', start - 1) + 1;
    final target = end > start && value.text[end - 1] == '\n' ? end - 1 : end;
    final next = value.text.indexOf('\n', target),
        lineEnd = next < 0 ? value.text.length : next;
    final replacement = value.text
        .substring(lineStart, lineEnd)
        .split('\n')
        .map((line) => '- $line')
        .join('\n');
    _text.value = TextEditingValue(
      text: value.text.replaceRange(lineStart, lineEnd, replacement),
      selection: start == end
          ? TextSelection.collapsed(offset: start + 2)
          : TextSelection(
              baseOffset: lineStart,
              extentOffset: lineStart + replacement.length,
            ),
    );
  }

  Future<void> _link() async {
    if (!_editable) return;
    final markup = await showDialog<String>(
      context: context,
      builder: (_) => _InsertLinkDialog(
        english: widget.english,
        initialLabel: _selectedText,
      ),
    );
    if (markup != null && mounted) _replaceSelection(markup);
  }

  String _status() {
    final phase = _controller.phase;
    if (_working || _controller.busy) {
      return t('正在核对或保存…', 'Checking or saving…');
    }
    if (phase == PublicEditPhase.unknown) {
      return t(
        '保存结果未知，请先核对远端。',
        'Save result unknown. Verify the remote content first.',
      );
    }
    if (phase == PublicEditPhase.unverified) {
      return t(
        '已收到保存回执，仍需重新读取核对。',
        'Save receipt received. Reload to verify the content.',
      );
    }
    if (phase == PublicEditPhase.conflict) {
      return t(
        '远端正文已更新，请核对冲突。',
        'Remote content changed. Review the conflict.',
      );
    }
    if (phase == PublicEditPhase.blocked) {
      return t(
        '编辑权限或内容状态已变化，已停止保存。',
        'Permission or content state changed. Saving has stopped.',
      );
    }
    if (_dirty) return t('有未保存修改', 'Unsaved changes');
    if (phase == PublicEditPhase.acknowledged) {
      return _controller.confirmedByRead
          ? t('远端正文已一致', 'Remote content matches')
          : t('保存已确认', 'Save confirmed');
    }
    return t('已载入远端正文', 'Remote content loaded');
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    if (snapshot != null &&
        !snapshot.locked &&
        snapshot.format == 'markdown' &&
        publicShareUsesMarkdownWebView(snapshot.detail)) {
      const purple = Color(0xff6530ad);
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      );
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(centerTitle: true),
          colorScheme: theme.colorScheme.copyWith(
            primary: purple,
            onPrimary: Colors.white,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              shape: shape,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: purple,
              side: const BorderSide(color: purple),
              minimumSize: const Size(48, 48),
              shape: shape,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: purple, shape: shape),
          ),
        ),
        child: SharedArticleEditPage(
          controller: _controller,
          attachments: widget.attachments,
          english: widget.english,
          retentionNotice: widget.retentionNotice,
          retentionActionsBuilder: widget.retentionActionsBuilder,
          registerPreview: widget.registerPreview,
          unregisterPreview: widget.unregisterPreview,
        ),
      );
    }
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Text(
            t('共享编辑', 'Shared editing'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: _editable ? () => _save() : null,
              child: Text(t('保存', 'Save')),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.retentionNotice != null)
                      Text(widget.retentionNotice!),
                    if (widget.retentionActionsBuilder != null)
                      widget.retentionActionsBuilder!(),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xffe3edff),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(
                              '持有编辑链接可修改正文',
                              'Anyone with this editing link can change the content',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xff155af5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t(
                              '请勿公开此链接。标题和权限由分享者管理。',
                              'Keep this link private. The sharer manages the title and permissions.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snapshot?.detail.title ?? '',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t('Markdown · 仅编辑正文', 'Markdown · Content only'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final preview in [false, true])
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _preview == preview
                                        ? const Color(0xff155af5)
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => _preview = preview),
                                child: Text(
                                  preview
                                      ? t('预览', 'Preview')
                                      : t('编辑', 'Edit'),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xffcbd5e1)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_preview)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: BookstarkMarkdown(
                                data: _text.text,
                                attachments: widget.attachments,
                                english: widget.english,
                              ),
                            )
                          else
                            TextField(
                              key: const ValueKey('shared-markdown-input'),
                              controller: _text,
                              undoController: _undo,
                              enabled: _editable,
                              minLines: 12,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                height: 1.6,
                              ),
                              onChanged: (_) => setState(() => _error = null),
                              decoration: InputDecoration(
                                labelText: t('Markdown正文', 'Markdown content'),
                                alignLabelWithHint: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          const Divider(height: 1),
                          ValueListenableBuilder<UndoHistoryValue>(
                            valueListenable: _undo,
                            builder: (context, value, _) => Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  onPressed: _editable
                                      ? () => _wrap('**', '**')
                                      : null,
                                  tooltip: t('加粗', 'Bold'),
                                  icon: const Icon(Icons.format_bold),
                                ),
                                IconButton(
                                  onPressed: _editable
                                      ? () => _wrap('*', '*')
                                      : null,
                                  tooltip: t('斜体', 'Italic'),
                                  icon: const Icon(Icons.format_italic),
                                ),
                                IconButton(
                                  onPressed: _editable ? _link : null,
                                  tooltip: t('插入链接', 'Insert link'),
                                  icon: const Icon(Icons.link),
                                ),
                                IconButton(
                                  onPressed: _editable ? _list : null,
                                  tooltip: t('列表', 'List'),
                                  icon: const Icon(Icons.format_list_bulleted),
                                ),
                                IconButton(
                                  onPressed: _editable && value.canUndo
                                      ? _undo.undo
                                      : null,
                                  tooltip: t('撤销', 'Undo'),
                                  icon: const Icon(Icons.undo),
                                ),
                                IconButton(
                                  onPressed: _editable && value.canRedo
                                      ? _undo.redo
                                      : null,
                                  tooltip: t('重做', 'Redo'),
                                  icon: const Icon(Icons.redo),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(liveRegion: true, child: Text(_status())),
                          const SizedBox(height: 8),
                          Text(
                            '${utf8.encode(_text.text).length} / 512000 B · ${t('本次会话保留', 'Kept in this session')}',
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: _copy,
                                child: Text(t('复制本次内容', 'Copy local content')),
                              ),
                              if ({
                                PublicEditPhase.unknown,
                                PublicEditPhase.unverified,
                              }.contains(_controller.phase))
                                OutlinedButton(
                                  onPressed: _working ? null : _verify,
                                  child: Text(t('重新读取核对', 'Reload to verify')),
                                ),
                              if (_controller.phase ==
                                      PublicEditPhase.unknown &&
                                  _controller.remoteStillBaseline)
                                FilledButton(
                                  onPressed: _working ? null : _retry,
                                  child: Text(
                                    t(
                                      '核对后再次保存',
                                      'Save again after verification',
                                    ),
                                  ),
                                ),
                              if (_controller.phase == PublicEditPhase.conflict)
                                OutlinedButton(
                                  onPressed: _conflict,
                                  child: Text(t('核对冲突', 'Review conflict')),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InsertLinkDialog extends StatefulWidget {
  const _InsertLinkDialog({required this.english, required this.initialLabel});
  final bool english;
  final String initialLabel;
  @override
  State<_InsertLinkDialog> createState() => _InsertLinkDialogState();
}

class _InsertLinkDialogState extends State<_InsertLinkDialog> {
  late final _label = TextEditingController(text: widget.initialLabel);
  final _url = TextEditingController();
  String? _issue;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  void _insert() {
    final target = Uri.tryParse(_url.text.trim());
    if (target == null ||
        !{'http', 'https'}.contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty ||
        _label.text.trim().isEmpty) {
      setState(
        () => _issue = t(
          '请输入链接文字和有效HTTP/HTTPS地址',
          'Enter link text and a valid HTTP/HTTPS URL',
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      markdownAttachment(_label.text.trim(), target, image: false),
    );
  }

  @override
  Widget build(BuildContext context) => _EditDialog(
    title: Text(t('插入链接', 'Insert link')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _label,
          decoration: InputDecoration(labelText: t('链接文字', 'Link text')),
        ),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: t('地址', 'URL'),
            errorText: _issue,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(onPressed: _insert, child: Text(t('插入', 'Insert'))),
    ],
  );
}

/// Title, content and actions share the same scroll area so a large font and
/// visible keyboard can never push confirmation buttons out of the dialog.
class _EditDialog extends StatelessWidget {
  const _EditDialog({
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle.merge(
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              child: title,
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}
