import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_factory.dart';
import 'complex_editor_browser.dart';
import 'local_article_creation_source_surface.dart';
import 'remote_article_creation_source_binding.dart';

/// Article bodies always use the real WebView. Native controls handle metadata
/// and explicit recovery choices only; they never render an editable body.
class RemoteArticleCreationPage extends StatefulWidget {
  const RemoteArticleCreationPage({
    super.key,
    required this.binding,
    required this.openKnown,
    this.sourceIoScope,
    this.surfaceBuilder = defaultArticleCreationSurface,
  });
  final RemoteMarkdownCreationBinding binding;
  final Future<void> Function(int id, MarkdownKnownIDOrigin origin) openKnown;
  final ArticleCreationSurfaceBuilder surfaceBuilder;
  final ComplexSourceIoScope? sourceIoScope;
  @override
  State<RemoteArticleCreationPage> createState() => _ArticleState();
}

class _ArticleState extends State<RemoteArticleCreationPage> {
  late final RemoteMarkdownCreationBinding _binding;
  late RemoteArticleCreationSourceBinding _source;
  OwnedPreviewController _preview = OwnedPreviewController();
  Timer? _debounce;
  int _epoch = 0, _view = 0;
  int? _lastScheduledRevision;
  bool _busy = false,
      _checkpointing = false,
      _durable = false,
      _server = false,
      _reviewReady = false;
  late bool _editingPreview;
  String? _error;
  final _id = TextEditingController();
  ComplexEditorTransport? _reviewTransport;
  NativeComplexSourceIo? _exportJob;
  RemoteMarkdownCreationController get c => _binding.controller;
  bool get current =>
      mounted && identical(widget.binding, _binding) && _binding.isCurrent();
  String t(String zh, String en) => widget.binding.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _binding = widget.binding;
    _bind();
  }

  void _bind() {
    if (_binding.collection.name != 'article' ||
        c.vault.scope.collection != 'article') {
      throw StateError('Article scope required');
    }
    _editingPreview = c.canEdit;
    _lastScheduledRevision = null;
    if (c.record.knownId != null) _id.text = c.record.knownId.toString();
    _source = RemoteArticleCreationSourceBinding(
      controller: c,
      isCurrent: () => current,
    );
  }

  @override
  void didUpdateWidget(covariant RemoteArticleCreationPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.binding, widget.binding)) {
      _epoch++;
      _debounce?.cancel();
      _exportJob?.retire();
      _source.source.invalidate();
      _binding.controller.retire();
      widget.binding.controller.retire();
      unawaited(_source.retireAndDrain());
      unawaited(_preview.retire().catchError((Object _) {}));
    }
  }

  Future<void> _replacePreview() async {
    await _preview.retire();
    if (!current) throw StateError('Article owner retired');
    final old = _preview;
    _preview = OwnedPreviewController();
    _view++;
    _reviewReady = false;
    _reviewTransport = null;
    old.dispose();
  }

  Future<void> _syncSurfaceMode() async {
    final editable =
        c.phase == MarkdownCreationPhase.editing &&
        !c.record.pending &&
        c.record.knownId == null;
    if (!current || _editingPreview == editable) return;
    await _replacePreview();
    _editingPreview = editable;
    _server = false;
    if (c.record.knownId != null) _id.text = c.record.knownId.toString();
  }

  void _changed() {
    if (!current || _busy || !c.canEdit) return;
    final state = _source.source.state;
    if (state == null ||
        !state.ready ||
        state.revision == _lastScheduledRevision) {
      return;
    }
    _lastScheduledRevision = state.revision;
    setState(() => _durable = false);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (current && !_busy && c.canEdit) unawaited(_checkpoint());
    });
  }

  Future<bool> _checkpoint() async {
    if (!current || _busy || _checkpointing || !c.canEdit) return false;
    setState(() => _checkpointing = true);
    try {
      final ok = await _source.source.checkpoint();
      await _syncSurfaceMode();
      if (current) {
        setState(() {
          _durable = ok;
          _error = ok
              ? null
              : t(
                  '草稿尚未确认保存，请保留此页重试。',
                  'Draft retention is not confirmed. Keep this page and retry.',
                );
        });
      }
      return ok;
    } catch (_) {
      if (current) {
        setState(() {
          _durable = false;
          _error = t(
            '草稿或旧预览关闭尚未确认，请保留此页重试。',
            'Draft retention or previous preview closure is unconfirmed. Keep this page and retry.',
          );
        });
      }
      return false;
    } finally {
      if (current) setState(() => _checkpointing = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (!current || _busy || _checkpointing || c.busy) return;
    _debounce?.cancel();
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (current && epoch == _epoch) {
        _error = t(
          '操作未完成，原稿已保留，请核对状态。',
          'Action did not finish. The original draft is retained; review its state.',
        );
      }
    } finally {
      if (current && epoch == _epoch) {
        try {
          await _syncSurfaceMode();
        } catch (_) {
          _error = t(
            '旧编辑页尚未关闭，请保留原稿并重试。',
            'Previous editor closure is not confirmed. Retain the draft and retry.',
          );
        }
        if (current && epoch == _epoch) setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() => _act(() async {
    if (c.record.input.title.trim().isEmpty) {
      _error = t('请先填写文章标题，再保存文章。', 'Add an article title before saving.');
      return;
    }
    final completed = await _source.source.submit();
    if (!completed && c.canEdit) {
      _durable = false;
      throw StateError('Complete durable checkpoint required');
    }
  });
  Future<void> _inspect() => _act(() async {
    final id = c.record.knownId ?? int.tryParse(_id.text.trim());
    if (id == null || id <= 0) throw StateError('Positive ID required');
    await _replacePreview();
    await c.inspect(id);
    if (!current) return;
    setState(() {
      _server = true;
      _reviewReady = false;
    });
  });
  Future<void> _switch(bool server) => _act(() async {
    if (server && c.observed == null) {
      throw StateError('Read full server version first');
    }
    await _replacePreview();
    if (current) setState(() => _server = server);
  });
  Future<void> _adopt() => _act(() async {
    final actual = c.observed;
    if (!_server || !_reviewReady || actual == null) {
      throw StateError('Full server review required');
    }
    c.markReviewed(actual);
    await _preview.retire();
    await c.adopt();
    if (current) {
      await _replacePreview();
      setState(() => _server = false);
    }
  });
  Future<void> _retry() => _act(() async {
    // Storage-only: the controller never submits again from cleanup.
    await c.retryCleanup();
  });
  Future<void> _open() => _act(() async {
    final openKnown = widget.openKnown;
    final id = c.record.knownId;
    if (id == null || c.phase != MarkdownCreationPhase.finished) {
      throw StateError('Known durable ID required');
    }
    final actual = await c.transport.inspect(id);
    if (!current ||
        actual.id != id ||
        actual.scope.namespace != c.vault.scope.namespace) {
      throw StateError('Known identity changed');
    }
    await _preview.retire();
    await widget.binding.beforeOpenSaved?.call();
    if (!current) return;
    widget.binding.onSaved?.call(id);
    await openKnown(id, c.record.knownIDOrigin);
    if (current) {
      await _replacePreview();
      setState(() {});
    }
  });
  Future<void> _export() => _act(() async {
    final owner = widget.sourceIoScope, transport = _reviewTransport;
    if (owner == null || transport == null || c.canEdit) {
      throw StateError('Owned read-only review required');
    }
    owner.guard();
    final observed = c.observed;
    final input = _server && observed != null ? observed.input : c.record.input;
    final fingerprint = _server ? observed?.fingerprint : c.record.fingerprint;
    final document = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      input.content,
    );
    final identity = await transport.reviewExportIdentity();
    if (!current ||
        !identical(transport, _reviewTransport) ||
        (_server ? c.observed?.fingerprint : c.record.fingerprint) !=
            fingerprint) {
      throw StateError('Review source changed');
    }
    owner.guard();
    final native = NativeComplexSourceIo(
      owner: owner,
      lease: identity['lease']! as String,
      generation: identity['generation']! as int,
      allowMarkdown: true,
    );
    _exportJob = native;
    try {
      final saved = await native.export(document, name: 'article-draft.md');
      if (current) {
        _error = saved
            ? t(
                '原稿已导出，原恢复记录仍保留。',
                'Draft exported. The recovery record is retained.',
              )
            : t(
                '导出已取消，原稿仍保留。',
                'Export cancelled. The original draft is retained.',
              );
      }
    } finally {
      native.retire();
      if (identical(_exportJob, native)) _exportJob = null;
      if (current) {
        owner.guard();
        await _replacePreview();
        setState(() {});
      }
    }
  });
  Future<void> _metadata() => _act(() async {
    if (!c.canEdit) return;
    if (!await _source.source.prepareLeave()) {
      throw StateError('Draft checkpoint failed');
    }
    final title = TextEditingController(text: c.record.input.title);
    final labels = TextEditingController(
      text: c.record.input.labels.join(', '),
    );
    try {
      if (!mounted || !current) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('文章信息', 'Article details')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: t('标题', 'Title')),
                ),
                TextField(
                  controller: labels,
                  decoration: InputDecoration(
                    labelText: t('标签（逗号分隔）', 'Labels (comma separated)'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('返回', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('应用', 'Apply')),
            ),
          ],
        ),
      );
      if (!current || !c.canEdit) return;
      if (result == true) {
        final input = c.record.input;
        await c.edit(
          MarkdownCreationInput(
            title: title.text,
            content: input.content,
            labels: labels.text
                .split(',')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toSet()
                .toList(),
          ),
        );
        _durable = true;
      }
    } finally {
      title.dispose();
      labels.dispose();
      if (current && c.canEdit) await _source.source.unlock();
    }
  });
  Future<void> _leave() async {
    if (_busy || _checkpointing || !current) return;
    if (c.canEdit && !await _checkpoint()) return;
    try {
      await _preview.retire();
      if (mounted && current) Navigator.pop(context);
    } catch (_) {
      if (current) {
        setState(
          () => _error = t(
            '旧预览关闭尚未确认，原稿仍保留。',
            'Preview closure is not confirmed. The original draft is retained.',
          ),
        );
      }
    }
  }

  Widget _editing() => LocalArticleCreationSourceSurface(
    key: ValueKey('article-source-$_view'),
    coordinator: _source.source,
    source: c.record.input.content,
    title: c.record.input.title,
    english: widget.binding.english,
    retirementController: _preview,
    onChanged: _changed,
    onSaveRequested: _save,
    onReloadRequested: () async {
      if (_busy || _checkpointing || !current) return;
      await _act(() async {
        await _source.retireAndDrain();
        await _replacePreview();
        if (current) {
          _bind();
          setState(() {});
        }
      });
    },
    builder:
        (
          context, {
          required key,
          required document,
          required title,
          required english,
          required retirementController,
          required onReady,
          required onState,
          required onSaveRequested,
          required beforeRetire,
          required onReloadRequested,
        }) => widget.surfaceBuilder(
          context,
          key: key,
          document: document,
          title: title,
          english: english,
          retirementController: retirementController,
          onReady: (transport) async {
            await transport.setInputLocked(true);
            await transport.setMarkdownByteLimit(4 * 1024 * 1024);
            if (!current) {
              throw StateError('Article retired before source ready');
            }
            await onReady(transport);
            if (current && c.canEdit) await transport.setInputLocked(false);
          },
          onState: onState,
          onSaveRequested: onSaveRequested,
          beforeRetire: beforeRetire,
          onReloadRequested: onReloadRequested,
        ),
  );
  Widget _readonly() {
    final observed = c.observed;
    final input = _server && observed != null ? observed.input : c.record.input;
    final fingerprint = _server ? observed?.fingerprint : c.record.fingerprint;
    final view = _view, preview = _preview;
    return ComplexEditorBrowser(
      key: ValueKey('article-review-$_view'),
      document: ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        input.content,
      ),
      title: input.title,
      english: widget.binding.english,
      readOnly: true,
      ownedReviewExport: widget.sourceIoScope != null,
      retirementController: _preview,
      onExternalLink: (_) async {},
      onReady: (transport) async {
        if (!current ||
            view != _view ||
            !identical(preview, _preview) ||
            preview.retired) {
          return;
        }
        setState(() {
          _reviewTransport = transport;
          _reviewReady =
              _server &&
              observed != null &&
              c.observed?.fingerprint == fingerprint;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(widget.binding, _binding)) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              t(
                '编辑空间已变更，请重新打开文章。',
                'Editing scope changed. Reopen the article.',
              ),
            ),
          ),
        ),
      );
    }
    final editing =
            c.phase == MarkdownCreationPhase.editing &&
            !c.record.pending &&
            c.record.knownId == null,
        known = c.record.knownId;
    final needsReview =
        !editing &&
        const {
          MarkdownCreationPhase.unknown,
          MarkdownCreationPhase.review,
        }.contains(c.phase);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _busy || _checkpointing ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('新建文章', 'New article')),
          actions: [
            if (editing)
              IconButton(
                onPressed: _busy || _checkpointing || c.busy ? null : _metadata,
                tooltip: t('文章信息', 'Article details'),
                icon: const Icon(Icons.tune),
              ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.phase == MarkdownCreationPhase.creating
                                ? t(
                                    '正在保存文章，请保留此页。',
                                    'Saving article. Keep this page open.',
                                  )
                                : editing
                                ? (_durable
                                      ? t(
                                          '草稿已保留在此设备',
                                          'Draft retained on this device',
                                        )
                                      : t(
                                          '草稿尚待保存确认',
                                          'Draft retention pending',
                                        ))
                                : known != null
                                ? t(
                                    '已知文章 ID：$known',
                                    'Known article ID: $known',
                                  )
                                : t(
                                    '保存结果未知，请核对已有文章',
                                    'Save result unknown. Review an existing article.',
                                  ),
                          ),
                          if (editing)
                            Text(
                              c.record.input.title.trim().isEmpty
                                  ? t('请填写文章标题', 'Add an article title')
                                  : c.record.input.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          if (editing)
                            TextButton(
                              onPressed: _busy || _checkpointing || c.busy
                                  ? null
                                  : _metadata,
                              child: Text(
                                t('编辑标题和标签', 'Edit title and labels'),
                              ),
                            ),
                          if (!editing)
                            Text(
                              _server
                                  ? t(
                                      '当前预览：完整服务器版本',
                                      'Viewing: full server version',
                                    )
                                  : t(
                                      '当前预览：保留的本地原稿',
                                      'Viewing: retained local draft',
                                    ),
                            ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (needsReview)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: TextField(
                                    controller: _id,
                                    readOnly: known != null,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: t(
                                        '已有文章 ID',
                                        'Existing article ID',
                                      ),
                                    ),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _busy || _checkpointing
                                      ? null
                                      : _inspect,
                                  child: Text(
                                    t('读取服务器版本', 'Read server version'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy || _checkpointing
                                      ? null
                                      : () => _switch(false),
                                  child: Text(t('本地原稿', 'Local draft')),
                                ),
                                if (c.observed != null)
                                  TextButton(
                                    onPressed: _busy || _checkpointing
                                        ? null
                                        : () => _switch(true),
                                    child: Text(
                                      t('完整服务器版本', 'Full server version'),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: _editingPreview ? _editing() : _readonly()),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .3,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (editing)
                            FilledButton(
                              onPressed: _busy || _checkpointing || c.busy
                                  ? null
                                  : _save,
                              child: Text(t('保存文章', 'Save article')),
                            ),
                          if (needsReview)
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      _checkpointing ||
                                      !_server ||
                                      !_reviewReady
                                  ? null
                                  : _adopt,
                              child: Text(
                                t(
                                  '已核对，关联此文章',
                                  'Reviewed: associate this article',
                                ),
                              ),
                            ),
                          if (c.phase == MarkdownCreationPhase.cleanup)
                            FilledButton(
                              onPressed: _busy || _checkpointing
                                  ? null
                                  : _retry,
                              child: Text(
                                t('仅重试本地清理', 'Retry local cleanup only'),
                              ),
                            ),
                          if (c.phase == MarkdownCreationPhase.finished)
                            FilledButton(
                              onPressed: _busy || _checkpointing ? null : _open,
                              child: Text(t('打开已知文章', 'Open known article')),
                            ),
                          if (!editing && widget.sourceIoScope != null)
                            OutlinedButton(
                              onPressed:
                                  _busy ||
                                      _checkpointing ||
                                      _reviewTransport == null
                                  ? null
                                  : _export,
                              child: Text(
                                t(
                                  '导出当前完整版本',
                                  'Export complete displayed source',
                                ),
                              ),
                            ),
                          OutlinedButton(
                            onPressed: _busy || _checkpointing ? null : _leave,
                            child: Text(t('保留并返回', 'Keep and return')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    _debounce?.cancel();
    _id.dispose();
    _exportJob?.retire();
    unawaited(_source.retireAndDrain());
    unawaited(_preview.retire().catchError((Object _) {}));
    _preview.dispose();
    c.retire();
    super.dispose();
  }
}
