import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/attachments.dart';
import '../../core/complex_editor_document.dart';
import '../../core/owned_preview_controller.dart';
import '../../core/public_edit_controller.dart';
import '../../core/shared_markdown_session.dart';
import '../complex_editors/complex_editor_browser.dart';

/// ShareEditPage owns the capability controller and clears it on final exit.
class SharedArticleEditPage extends StatefulWidget {
  const SharedArticleEditPage({
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
  State<SharedArticleEditPage> createState() => _SharedArticleEditPageState();
}

class _SharedArticleEditPageState extends State<SharedArticleEditPage> {
  late final _session = SharedMarkdownSession(widget.controller);
  OwnedPreviewController _lease = OwnedPreviewController();
  late ComplexEditorDocument _document;
  int _generation = 0, _resourceFailed = 0;
  GlobalKey _editorAnchor = GlobalKey(debugLabel: 'shared-editor-0');
  double _lastKeyboardInset = 0;
  bool _acting = false;
  bool _leaving = false,
      _uploading = false,
      _dialog = false,
      _liveDirty = false;
  String? _error, _attachmentMarkup;
  String t(String zh, String en) => widget.english ? en : zh;
  PublicEditController get _controller => widget.controller;
  @override
  void initState() {
    super.initState();
    _document = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      _session.body,
    );
    _session.addListener(_changed);
    widget.registerPreview?.call(_lease);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _lastKeyboardInset) {
      _lastKeyboardInset = keyboard;
      if (keyboard > 0) _revealEditorForKeyboard();
    }
  }

  void _revealEditorForKeyboard() {
    if (!mounted || MediaQuery.viewInsetsOf(context).bottom <= 0) return;
    final anchor = _editorAnchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(anchor, _editorAnchor) ||
          _lease.retired ||
          _session.paused ||
          _dialog ||
          _uploading ||
          !_session.canEdit) {
        return;
      }
      final target = anchor.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 1,
            duration: const Duration(milliseconds: 120),
          ),
        );
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _releasePreview(_lease);
    _session.dispose();
    super.dispose();
  }

  void _releasePreview(OwnedPreviewController lease) {
    final unregister = widget.unregisterPreview;
    unawaited(
      lease.retire().then<void>(
        (_) {
          unregister?.call(lease);
          lease.dispose();
        },
        onError: (Object _, StackTrace _) {
          // Keep the failed preview in its Root owner's retirement barrier so
          // activation cannot proceed on an unconfirmed native close.
        },
      ),
    );
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_session.busy || _acting) return;
    setState(() {
      _error = null;
      _acting = true;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = utf8.encode(_session.body).length > 500 * 1024
              ? t(
                  '共享正文保存上限为500 KiB，本次内容未截断，请先复制并缩减正文。',
                  'Shared content is limited to 500 KiB. Nothing was truncated. Copy your content before reducing its size.',
                )
              : t(
                  '操作未完成，请保留本次内容并核对权限、网络及正文大小。',
                  'Action incomplete. Keep your working copy and check permission, connection and size.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _copy() => _run(() async {
    if (!_session.paused && !_session.captureFailed) await _session.capture();
    await Clipboard.setData(ClipboardData(text: _session.body));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _session.captureFailed
                ? t('已复制上次成功快照', 'Last successful snapshot copied')
                : t('已复制本次内容', 'Working copy copied'),
          ),
        ),
      );
    }
  });
  Future<bool> _confirm(String title, String content) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('确认', 'Confirm')),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _leave() async {
    if (_session.busy || _uploading || _dialog || _acting) return;
    await _run(() async {
      if (!_session.paused && !_session.captureFailed) {
        try {
          await _session.capture();
        } catch (_) {}
      }
      if (!mounted) return;
      final lostCapture = _session.captureFailed;
      if ((lostCapture ||
              _session.dirty ||
              _liveDirty ||
              {
                PublicEditPhase.unknown,
                PublicEditPhase.unverified,
                PublicEditPhase.conflict,
              }.contains(_controller.phase)) &&
          !await _confirm(
            t('离开共享编辑？', 'Leave shared editing?'),
            lostCapture
                ? t(
                    '最新修改未能读取，离开会丢弃尚未捕获的修改。可取消并先复制上次快照。',
                    'Latest changes could not be captured. Leaving discards them. Cancel to copy the last successful snapshot.',
                  )
                : t(
                    '本次内容仅在当前会话保留。离开会清除未保存或未核对的内容，请先复制。',
                    'Copy any unsaved or unverified content before leaving this session.',
                  ),
          )) {
        return;
      }
      if (lostCapture) _session.acknowledgeDiscardForExit();
      await _lease.retire();
      if (!lostCapture && _session.captureFailed) {
        throw StateError('Final capture failed; explicit discard required');
      }
      if (mounted) {
        setState(() => _leaving = true);
        Navigator.pop(context);
      }
    });
  }

  Future<void> _save() => _run(() async {
    await _session.save();
    if (mounted && _controller.phase == PublicEditPhase.conflict) {
      await _conflict();
    }
  });
  void _replaceBrowser() {
    final old = _lease;
    _lease = OwnedPreviewController();
    widget.registerPreview?.call(_lease);
    _document = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      _session.body,
    );
    setState(() {
      _generation++;
      _editorAnchor = GlobalKey(debugLabel: 'shared-editor-$_generation');
      _resourceFailed = 0;
      _liveDirty = _session.dirty;
    });
    _releasePreview(old);
  }

  Future<void> _resume() => _run(() async {
    if (!_session.paused) await _lease.retire();
    await _session.resume();
    if (!mounted) return;
    if (_controller.phase == PublicEditPhase.conflict) {
      await _conflict();
    } else if (!_session.paused) {
      _replaceBrowser();
    }
  });
  Widget _review(String text) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 180),
    child: SingleChildScrollView(child: SelectableText(text)),
  );
  Future<void> _conflict() async {
    final observed = _controller.conflict;
    if (_dialog || observed == null || !mounted) return;
    _dialog = true;
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('远端已变化', 'Remote content changed')),
          content: SizedBox(
            width: 540,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('本次内容', 'Working copy')),
                _review(_session.body),
                const SizedBox(height: 12),
                Text(t('当前远端', 'Current remote')),
                _review(observed.content),
                const SizedBox(height: 12),
                Text(
                  t(
                    '覆盖前会再次核对，但服务端无法保证同时修改不会互相覆盖。',
                    'The version is checked again before overwrite. The server cannot guarantee atomic conflict protection.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _session.body)),
              child: Text(
                _session.captureFailed
                    ? t('复制上次快照', 'Copy last snapshot')
                    : t('复制本次内容', 'Copy working copy'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'remote'),
              child: Text(t('采用远端', 'Use remote')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'overwrite'),
              child: Text(t('确认覆盖', 'Overwrite')),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'remote') {
        await _lease.retire();
        await _session.adoptRemoteWhilePaused();
        await _session.resume();
        if (mounted && !_session.paused) _replaceBrowser();
      } else if (_session.paused) {
        await _session.overwriteRetained(observed);
      } else {
        await _session.save(observed: observed);
      }
    } finally {
      _dialog = false;
    }
  }

  Future<void> _external(Uri uri) async {
    if (_dialog || _uploading || _session.busy || _lease.retired) return;
    _dialog = true;
    try {
      if (!await _confirm(
        t('打开外部链接？', 'Open external link?'),
        uri.toString(),
      )) {
        return;
      }
      await _lease.retire();
      if (_session.captureFailed) throw StateError('Capture failed');
      if (mounted) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '未打开链接，请先保留本次内容。',
            'Link not opened. Keep your working copy.',
          ),
        );
      }
    } finally {
      _dialog = false;
    }
  }

  Future<void> _attachment() async {
    if (_uploading || _session.busy || !_session.canEdit) return;
    SharedMarkdownInsertion? insertion;
    var completed = false;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      insertion = await _session.beginInsertion();
      if (!mounted) return;
      final markup = await showDialog<String>(
        context: context,
        builder: (_) => _SharedAttachmentDialog(
          attachments: widget.attachments,
          english: widget.english,
        ),
      );
      if (markup == null || !mounted) return;
      _attachmentMarkup = markup;
      await _session.finishInsertion(insertion, markup);
      completed = true;
      if (mounted) setState(() => _attachmentMarkup = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '链接未插入，可在下方复制后重新核对。',
            'Link not inserted. Copy it below and recheck the source.',
          ),
        );
      }
    } finally {
      if (insertion != null && !completed && mounted) {
        try {
          await _session.finishInsertion(insertion, null);
        } catch (_) {}
      }
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _retry() => _run(() async {
    if (!await _confirm(
      t('核对后再次保存？', 'Retry after verification?'),
      t(
        '远端刚才仍为旧版本。再次保存前会重新核对，但上次请求可能已到达服务端。',
        'The last read showed the old version. The previous request may still have reached the server.',
      ),
    )) {
      return;
    }
    _controller.acknowledgeRetry();
    if (_session.paused) {
      await _session.resume();
      if (mounted && !_session.paused) _replaceBrowser();
    } else {
      await _session.save();
    }
  });

  String _status() {
    if (_session.captureFailed) {
      return t(
        '最新正文未能读取，仅保留上次成功快照',
        'Latest source unavailable; only the last successful copy is retained',
      );
    }
    if (_session.busy) return t('正在核对…', 'Checking…');
    if (_controller.phase == PublicEditPhase.unknown) {
      return t('保存结果未知，请先核对远端', 'Save result unknown. Verify remote content.');
    }
    if (_controller.phase == PublicEditPhase.unverified) {
      return t(
        '已有保存回执，正文仍待核对',
        'Save receipt received. Content awaits verification.',
      );
    }
    if (_controller.phase == PublicEditPhase.conflict) {
      return t('远端已变化 · 本次内容已保留', 'Remote changed · working copy retained');
    }
    if (_controller.phase == PublicEditPhase.blocked) {
      return t(
        '权限或正文状态变化，已停止编辑',
        'Permission or content changed. Editing stopped.',
      );
    }
    if (_session.paused) {
      return t(
        '已暂停 · 本次内容保留在当前会话',
        'Paused · working copy retained in this session',
      );
    }
    if (_controller.phase == PublicEditPhase.acknowledged &&
        !_liveDirty &&
        !_session.dirty) {
      return t('远端已核实', 'Remote verified');
    }
    return _liveDirty || _session.dirty
        ? t('本次内容未保存', 'Unsaved working copy')
        : t('已载入正文 · 仅编辑内容', 'Content loaded · body editing only');
  }

  Widget _chip(String label, IconData icon, {bool warning = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: warning ? const Color(0xfffff0cb) : const Color(0xfff1e8fc),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: warning
                  ? const Color(0xffa76000)
                  : const Color(0xff6530ad),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: warning
                      ? const Color(0xff754300)
                      : const Color(0xff40206c),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
  Widget _notice(String title, String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfffff0cb),
      border: Border.all(color: const Color(0xffffd369)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xffa76000)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(message),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _copyButton(bool available) => OutlinedButton(
    onPressed: available ? _copy : null,
    child: Text(
      _session.captureFailed
          ? t('复制上次快照', 'Copy last snapshot')
          : t('复制本次内容', 'Copy working copy'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final detail = _controller.snapshot!.detail;
    final available = !_session.busy && !_uploading && !_acting;
    final pending = {
      PublicEditPhase.unknown,
      PublicEditPhase.unverified,
    }.contains(_controller.phase);
    final conflict = _controller.phase == PublicEditPhase.conflict;
    final blocked = _controller.phase == PublicEditPhase.blocked;
    final verified =
        _controller.phase == PublicEditPhase.acknowledged &&
        !_liveDirty &&
        !_session.dirty &&
        !_session.paused;
    final excerpt = _session.body.runes.take(4001).toList();
    final media = MediaQuery.of(context);
    final preferredEditorHeight =
        media.size.height.clamp(400, 850).toDouble() *
        ((pending ||
                conflict ||
                blocked ||
                _session.paused ||
                _session.captureFailed)
            ? .48
            : .60);
    final editorHeight = media.viewInsets.bottom <= 0
        ? preferredEditorHeight
        : (media.size.height -
                  media.viewInsets.bottom -
                  kToolbarHeight -
                  media.padding.top -
                  media.padding.bottom -
                  32)
              .clamp(140.0, preferredEditorHeight)
              .toDouble();
    final needsActions =
        pending ||
        conflict ||
        blocked ||
        _session.paused ||
        _session.captureFailed;
    final canResume = {
      PublicEditPhase.ready,
      PublicEditPhase.acknowledged,
      PublicEditPhase.blocked,
    }.contains(_controller.phase);
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xfffdfcfe),
        appBar: AppBar(
          backgroundColor: const Color(0xff6530ad),
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          leading: BackButton(onPressed: _leave),
          title: Text(
            t('共享编辑', 'Shared editing'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: available && _session.canEdit ? _attachment : null,
              icon: const Icon(Icons.attach_file),
              tooltip: t('插入附件', 'Insert attachment'),
            ),
            TextButton(
              onPressed: available && _session.canEdit ? _save : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white54,
              ),
              child: Text(t('保存', 'Save')),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.retentionNotice != null) Text(widget.retentionNotice!),
              if (widget.retentionActionsBuilder != null)
                widget.retentionActionsBuilder!(),
              Text(
                detail.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    blocked
                        ? t('权限待核对', 'Permission needs rechecking')
                        : _session.paused
                        ? t('编辑已暂停', 'Editing paused')
                        : t('编辑权限已验证', 'Editing permission verified'),
                    blocked
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    warning: blocked,
                  ),
                  if (detail.blogType == null)
                    _chip(t('兼容模式', 'Compatibility'), Icons.info_outline),
                  if (verified)
                    _chip(t('远端已核实', 'Remote verified'), Icons.done),
                ],
              ),
              if (pending || conflict || _session.captureFailed || blocked) ...[
                const SizedBox(height: 16),
                _notice(
                  _session.captureFailed
                      ? t('最新正文未能读取', 'Latest source unavailable')
                      : pending
                      ? t('保存结果待核实', 'Save result needs verification')
                      : conflict
                      ? t('远端已变化', 'Remote content changed')
                      : t('编辑已停止', 'Editing stopped'),
                  _session.captureFailed
                      ? t(
                          '仅保留上次成功快照，请重新读取或复制后明确退出。',
                          'Only the last successful snapshot is retained. Recapture or copy before explicitly leaving.',
                        )
                      : pending
                      ? t(
                          '先核对远端内容，再决定后续操作。',
                          'Verify remote content before deciding what to do next.',
                        )
                      : conflict
                      ? t(
                          '本次内容已保留，核对两个版本后再选择。',
                          'The working copy is retained. Review both versions before choosing.',
                        )
                      : t(
                          '请重新核对权限。本次内容仍在当前会话。',
                          'Recheck permission. The working copy remains in this session.',
                        ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                key: _editorAnchor,
                height: editorHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ComplexEditorBrowser(
                        document: _document,
                        title: detail.title,
                        english: widget.english,
                        publicServer: detail.reference.server,
                        sharedMarkdownEditing: true,
                        readOnly: false,
                        retirementController: _lease,
                        onReady: (transport) async {
                          await _session.attach(transport);
                          _revealEditorForKeyboard();
                        },
                        onState: (state) {
                          if (mounted && _liveDirty != state.dirty) {
                            setState(() => _liveDirty = state.dirty);
                            _revealEditorForKeyboard();
                          }
                        },
                        onSaveRequested: _save,
                        beforeRetire: _session.beforeRetire,
                        onReloadRequested: _resume,
                        onExternalLink: _external,
                        onPublicResourceStatus: (_, failed) {
                          if (mounted && failed != _resourceFailed) {
                            setState(() => _resourceFailed = failed);
                          }
                        },
                      ),
                    ),
                    if (_session.paused && !_session.busy)
                      Positioned.fill(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xffeff0f5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              String.fromCharCodes(
                                    _session.body.runes.take(4000),
                                  ) +
                                  (excerpt.length > 4000
                                      ? t(
                                          '\n（仅显示开头，复制可取得完整内容）',
                                          '\n(Opening excerpt; copying retrieves the full working copy)',
                                        )
                                      : ''),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (needsActions)
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (pending)
                      FilledButton(
                        onPressed: available
                            ? () => _run(_session.verify)
                            : null,
                        child: Text(t('核对远端', 'Verify remote')),
                      ),
                    if (conflict)
                      FilledButton(
                        onPressed: available ? () => _run(_conflict) : null,
                        child: Text(t('核对冲突', 'Review conflict')),
                      ),
                    if ((_session.paused || blocked) && canResume)
                      FilledButton(
                        onPressed: available && !_session.captureFailed
                            ? _resume
                            : null,
                        child: Text(t('重新核对并继续', 'Recheck and resume')),
                      ),
                    if (_session.captureFailed && _session.canRecapture)
                      FilledButton(
                        onPressed: available
                            ? () => _run(_session.capture)
                            : null,
                        child: Text(t('重新读取本次内容', 'Recapture working copy')),
                      ),
                    _copyButton(available),
                    if (_controller.remoteStillBaseline &&
                        _controller.phase == PublicEditPhase.unknown)
                      OutlinedButton(
                        onPressed: available ? _retry : null,
                        child: Text(t('确认再次保存', 'Confirm retry')),
                      ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xfff1e8fc),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        verified
                            ? Icons.check_circle_outline
                            : Icons.edit_outlined,
                        color: const Color(0xff6530ad),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            verified
                                ? t('本次内容已保存', 'Working copy saved')
                                : _status(),
                            style: const TextStyle(color: Color(0xff40206c)),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: available ? _copy : null,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        color: const Color(0xff6530ad),
                        tooltip: t('复制本次内容', 'Copy working copy'),
                      ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_resourceFailed > 0) ...[
                const SizedBox(height: 8),
                Text(
                  t(
                    '部分预览图片未能载入，保存不会替换其链接。',
                    'Some preview images could not load. Saving preserves their links.',
                  ),
                ),
              ],
              if (_attachmentMarkup != null) ...[
                const SizedBox(height: 8),
                SelectableText(_attachmentMarkup!),
                TextButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _attachmentMarkup!),
                  ),
                  child: Text(t('复制附件链接', 'Copy attachment link')),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                t(
                  '本次内容仅保留在当前会话，退出前请保存或复制。',
                  'Working copy is kept in this session only. Save or copy before leaving.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedAttachmentDialog extends StatefulWidget {
  const _SharedAttachmentDialog({
    required this.attachments,
    required this.english,
  });
  final AttachmentRepository attachments;
  final bool english;
  @override
  State<_SharedAttachmentDialog> createState() =>
      _SharedAttachmentDialogState();
}

class _SharedAttachmentDialogState extends State<_SharedAttachmentDialog> {
  final _name = TextEditingController(), _url = TextEditingController();
  bool _image = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _insert() {
    final text = _url.text.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        text.length > 8192 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) ||
        _name.text.trim().isEmpty ||
        _name.text.trim().length > 180 ||
        _image && !widget.attachments.owns(uri)) {
      setState(
        () => _error = t(
          '请填写名称和公开 HTTP(S) 地址；图片须使用此服务器的公开附件地址。',
          'Enter a name and public HTTP(S) URL. Images must use this server’s public attachment URL.',
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      markdownAttachment(_name.text.trim(), uri, image: _image),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t('插入附件链接', 'Insert attachment link')),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              '当前共享 Markdown 接口不支持上传，可插入已有公开链接。',
              'This shared Markdown API supports existing public links, without file uploads.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('shared-attachment-name'),
            controller: _name,
            decoration: InputDecoration(labelText: t('名称', 'Name')),
          ),
          TextField(
            key: const ValueKey('shared-attachment-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: t('公开地址', 'Public URL')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _image,
            onChanged: (value) => setState(() => _image = value),
            title: Text(t('作为图片显示', 'Display as image')),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
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
