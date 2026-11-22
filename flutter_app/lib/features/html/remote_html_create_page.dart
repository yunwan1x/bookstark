import 'dart:async';

import 'package:flutter/material.dart';

import '../complex_editors/complex_editor_browser.dart';

import '../../core/html_notes_repository.dart';
import '../../core/html_creation_candidates.dart';
import '../../core/labels_repository.dart';
import '../../core/remote_html_creation_controller.dart';
import '../../widgets/label_picker.dart';
import '../notes/note_unlock_dialog.dart';
import 'html_preview.dart';
import 'html_browser_session.dart';
import 'html_note_page.dart';
import 'html_creation_source_coordinator.dart';
import 'html_creation_source_surface.dart';
import 'html_version_view.dart';
import 'html_code_source_surface.dart';

class RemoteHtmlCreatePage extends StatefulWidget {
  const RemoteHtmlCreatePage({
    super.key,
    required this.controller,
    required this.labels,
    required this.serverLabel,
    this.english = false,
    this.onDisposed,
    this.sourceSurfaceBuilder = defaultHtmlSourceSurface,
    this.readOnlySourceSurfaceBuilder,
  });
  final RemoteHtmlCreationController controller;
  final LabelsRepository labels;
  final String serverLabel;
  final bool english;
  final VoidCallback? onDisposed;
  final HtmlSourceSurfaceBuilder sourceSurfaceBuilder;
  final HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder;
  @override
  State<RemoteHtmlCreatePage> createState() => _RemoteHtmlCreatePageState();
}

class _RemoteHtmlCreatePageState extends State<RemoteHtmlCreatePage> {
  RemoteHtmlCreationController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  late final TextEditingController _title;
  Timer? _timer;
  late final HtmlCreationSourceCoordinator _sourceCoordinator;
  int _sourceMount = 0;
  bool _sourceClosing = false, _saveInFlight = false;
  int? _sourceScheduledRevision;
  bool _source = true, _allowPop = false, _leaving = false, _popping = false;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: c.draft?.title ?? '');
    _sourceCoordinator = HtmlCreationSourceCoordinator(
      freezeEdit: (source) => HtmlNoteEdit(
        title: _title.text,
        source: source,
        labels: c.draft?.labels ?? const [],
      ),
      applyCapturedEdit: (value) {
        final old = c.draft;
        if (old != null &&
            (value.title != old.title ||
                value.source != old.source ||
                value.labels.length != old.labels.length ||
                !value.labels.asMap().entries.every(
                  (e) => e.value == old.labels[e.key],
                ))) {
          c.edit(value);
        }
      },
      flushCreationJournal: c.flush,
      create: c.save,
      creationStillEditable: () => c.canEdit,
      pendingOrUnknown: () => !{
        RemoteHtmlCreationPhase.editing,
        RemoteHtmlCreationPhase.finished,
      }.contains(c.phase),
    );
    c.addListener(_updated);
  }

  void _updated() {
    if (!mounted) return;
    _timer?.cancel();
    if (c.phase == RemoteHtmlCreationPhase.finished) {
      if (!_saveInFlight) _pop(c.created?.metadata.id);
      setState(() {});
      return;
    }
    if (c.canEdit) {
      _timer = Timer(const Duration(milliseconds: 650), () async {
        if (_source && _sourceCoordinator.ready) {
          await _sourceCoordinator.checkpoint();
        } else {
          await c.flush();
        }
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  void _pop(int? id) {
    if (!mounted || _popping || _sourceClosing) return;
    _sourceClosing = true;
    unawaited(_closeThenPop(id));
  }

  Future<void> _closeThenPop(int? id) async {
    if (_sourceCoordinator.transport != null) {
      await HtmlBrowserSession.closeActive();
    }
    await _sourceCoordinator.drain();
    if (!mounted || _popping) return;
    _popping = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(id);
    });
  }

  void _edit({String? title, String? source, List<String>? labels}) {
    final draft = c.draft;
    if (!c.canEdit || _sourceCoordinator.busy || draft == null) return;
    c.edit(
      HtmlNoteEdit(
        title: title ?? _title.text,
        source: source ?? draft.source,
        labels: labels ?? draft.labels,
      ),
    );
  }

  void _sourceStateChanged(ComplexEditorState value) {
    if (!mounted ||
        !value.ready ||
        !value.dirty ||
        !c.canEdit ||
        _sourceCoordinator.busy ||
        value.revision == _sourceCoordinator.lastCheckpointRevision ||
        value.revision == _sourceScheduledRevision) {
      return;
    }
    _sourceScheduledRevision = value.revision;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 650), () async {
      await _sourceCoordinator.checkpoint();
      if (mounted) setState(() {});
    });
  }

  void _reloadSource() {
    if (!mounted ||
        !_source ||
        _sourceCoordinator.transport != null ||
        _sourceCoordinator.busy) {
      return;
    }
    setState(() {
      _sourceMount++;
      _sourceScheduledRevision = null;
    });
  }

  Future<void> _switchSource(bool value) async {
    if (_leaving || _source == value || _sourceCoordinator.busy || c.busy) {
      return;
    }
    _timer?.cancel();
    if (_source && c.canEdit) {
      final durable = await _sourceCoordinator.checkpoint();
      if (!durable || !mounted) {
        if (mounted) setState(() {});
        return;
      }
      await HtmlBrowserSession.closeActive();
    }
    if (mounted) {
      setState(() {
        _source = value;
        _sourceMount++;
        _sourceScheduledRevision = null;
      });
    }
  }

  Future<void> _saveCreation() async {
    if (_saveInFlight) return;
    _saveInFlight = true;
    _timer?.cancel();
    _sourceScheduledRevision = null;
    try {
      if (_source && _sourceCoordinator.ready) {
        await _sourceCoordinator.submit();
      } else {
        await c.save();
      }
    } finally {
      _saveInFlight = false;
      if (mounted) {
        if (c.phase == RemoteHtmlCreationPhase.finished) {
          _pop(c.created?.metadata.id);
        }
        setState(() {});
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving || c.busy) return;
    _leaving = true;
    _timer?.cancel();
    if (_source && _sourceCoordinator.ready && c.canEdit) {
      final durable = await _sourceCoordinator.prepareLeave();
      if (!durable || !mounted) {
        _leaving = false;
        if (mounted) setState(() {});
        return;
      }
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('离开新建页面', 'Leave creation'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              t(
                c.canEdit ? '可以保留草稿，稍后继续。' : '未确认的创建将保留，回来后只读核对。',
                c.canEdit
                    ? 'Keep the draft to continue later.'
                    : 'The uncertain creation is kept for read-only review.',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: Text(t('保留并离开', 'Keep and leave')),
            ),
            if (c.canEdit)
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(t('放弃草稿', 'Discard draft')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'stay'),
              child: Text(t('继续编辑', 'Continue editing')),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == null || choice == 'stay') {
      await c.flush();
      await _sourceCoordinator.unlock();
      _leaving = false;
      if (mounted) setState(() {});
      return;
    }
    if (choice == 'discard') {
      _sourceCoordinator.invalidate();
      await HtmlBrowserSession.closeActive();
      await _sourceCoordinator.drain();
    }
    final ok = choice == 'discard' ? await c.discardDraft() : await c.flush();
    _leaving = false;
    if (!mounted) return;
    if (ok && {'keep', 'discard'}.contains(choice)) {
      _pop(null);
    } else {
      setState(() {});
    }
  }

  Future<void> _labels() async {
    final value = await showLabelPicker(
      context,
      repository: widget.labels,
      selected: c.draft?.labels ?? [],
      english: widget.english,
    );
    if (value != null && mounted && !_leaving) _edit(labels: value);
  }

  Future<void> _inspect(int id) async {
    await c.inspect(id);
    if (!mounted) return;
    if (c.failure is HtmlNoteLocked) {
      await showDialog<HtmlNote>(
        context: context,
        barrierDismissible: false,
        builder: (_) => NoteUnlockDialog<HtmlNote>(
          english: widget.english,
          onUnlock: (password) async {
            await c.inspect(id, password: password);
            if (c.observed == null) {
              throw StateError(
                t('无法解锁或核对该笔记，请重试。', 'Unable to unlock or verify this note.'),
              );
            }
            return c.observed!;
          },
        ),
      );
    }
  }

  Future<void> _search() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _CandidatePage(controller: c, english: widget.english),
      ),
    );
    if (id != null && mounted) await _inspect(id);
  }

  Future<void> _review() async {
    final snapshot = c.observed;
    if (snapshot == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HtmlVersionViewPage(
          heading: t('核对服务器版本', 'Review server version'),
          title: snapshot.metadata.title,
          source: snapshot.source,
          labels: snapshot.labels,
          english: widget.english,
          sourceSurfaceBuilder: widget.readOnlySourceSurfaceBuilder,
        ),
      ),
    );
    if (mounted && c.observed != null) c.markReviewed(snapshot);
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_updated);
    final sourceCoordinator = _sourceCoordinator;
    final title = _title;
    final controller = c;
    final onDisposed = widget.onDisposed;
    unawaited(() async {
      try {
        if (sourceCoordinator.transport != null) {
          await HtmlBrowserSession.closeActive();
        }
      } catch (_) {
        // Forced retirement must finish cleanup even if the native close fails.
      }
      try {
        await sourceCoordinator.drain();
        await sourceCoordinator.dispose();
      } finally {
        title.dispose();
        controller.dispose();
        onDisposed?.call();
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = c.draft;
    final pending = c.phase != RemoteHtmlCreationPhase.editing;
    final reviewable = {
      RemoteHtmlCreationPhase.unknown,
      RemoteHtmlCreationPhase.review,
    }.contains(c.phase);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff1f5ff),
        appBar: AppBar(
          leading: IconButton(
            onPressed: c.busy || _leaving ? null : _leave,
            tooltip: t('返回', 'Back'),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            t(
              pending ? '核对新建结果' : '新建 HTML',
              pending ? 'Review creation' : 'New HTML',
            ),
          ),
          actions: [
            if (!pending)
              TextButton(
                onPressed:
                    _leaving || c.busy || (_source && !_sourceCoordinator.ready)
                    ? null
                    : _saveCreation,
                child: Text(t('保存', 'Save')),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                children: [
                  Chip(
                    avatar: const Icon(Icons.cloud_outlined),
                    label: Text(t('服务器空间', 'Server space')),
                  ),
                  if (!pending) Chip(label: Text(t('未保存', 'Unsaved'))),
                ],
              ),
              Text(
                widget.serverLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (pending)
                Card(
                  color: const Color(0xffffedca),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(
                            c.phase == RemoteHtmlCreationPhase.cleanup
                                ? '已保存，草稿清理待完成'
                                : '创建结果待核对',
                            c.phase == RemoteHtmlCreationPhase.cleanup
                                ? 'Saved; cleanup pending'
                                : 'Creation needs review',
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          t(
                            '先核对服务器版本，避免重复创建。标题相同不能证明是本次创建。',
                            'Review the server version before continuing. A matching title alone does not identify this creation.',
                          ),
                        ),
                        if (c.receiptId != null) Text('ID ${c.receiptId}'),
                      ],
                    ),
                  ),
                ),
              if (c.busy) const LinearProgressIndicator(),
              if (c.failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t(
                      c.failure is FormatException && c.canEdit
                          ? '请检查标题、正文和标签。'
                          : '操作未完成，请核对结果或稍后重试。',
                      c.failure is FormatException && c.canEdit
                          ? 'Check the title, source and labels.'
                          : 'The operation did not finish. Review the result or retry later.',
                    ),
                  ),
                ),
              if (_sourceCoordinator.failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t(
                      '源码尚未可靠保存，请重试或留在此页。',
                      'Source checkpoint failed. Retry or stay on this page.',
                    ),
                  ),
                ),
              if (c.recoveryFailure != null) ...[
                Text(
                  t(
                    '本机恢复记录未能更新。',
                    'The device recovery record could not be updated.',
                  ),
                ),
                if (c.phase != RemoteHtmlCreationPhase.cleanup)
                  OutlinedButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            await c.flush();
                            if (mounted) setState(() {});
                          },
                    child: Text(t('重试本机存储', 'Retry device storage')),
                  ),
              ],
              if (draft != null) ...[
                const SizedBox(height: 16),
                if (c.canEdit && !_sourceCoordinator.busy && !_leaving)
                  TextField(
                    key: const ValueKey('remote-html-create-title'),
                    controller: _title,
                    onChanged: (value) {
                      if (!_leaving) _edit(title: value);
                    },
                    decoration: InputDecoration(labelText: t('标题', 'Title')),
                  )
                else
                  Text(
                    draft.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in draft.labels)
                      InputChip(
                        label: Text(label),
                        onDeleted:
                            c.canEdit && !_sourceCoordinator.busy && !_leaving
                            ? () => _edit(
                                labels: draft.labels
                                    .where((v) => v != label)
                                    .toList(),
                              )
                            : null,
                      ),
                    if (c.canEdit && !_sourceCoordinator.busy)
                      ActionChip(
                        avatar: const Icon(Icons.add),
                        label: Text(t('添加标签', 'Add labels')),
                        onPressed: _leaving || c.busy ? null : _labels,
                      ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t(
                      '此恢复已转为保护模式，仅在解锁后核对服务器版本。',
                      'Recovery is protected. Unlock to review the server version.',
                    ),
                  ),
                ),
              if (reviewable) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: c.busy
                      ? null
                      : c.receiptId != null
                      ? () => _inspect(c.receiptId!)
                      : _search,
                  icon: const Icon(Icons.search),
                  label: Text(t('只读核对服务器新建结果', 'Review server creation')),
                ),
              ],
              if (c.observed != null &&
                  c.phase == RemoteHtmlCreationPhase.review) ...[
                Card(
                  child: ListTile(
                    onTap: c.busy ? null : _review,
                    title: Text(c.observed!.metadata.title),
                    subtitle: Text(
                      'ID ${c.observed!.metadata.id} · v${c.observed!.metadata.version}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                Text(
                  t(
                    draft?.matches(c.observed!) == true
                        ? '原文和标签已回读一致。'
                        : '请查看完整版本，采用将保留服务器当前内容和标签。',
                    draft?.matches(c.observed!) == true
                        ? 'Source and labels match the read-back.'
                        : 'Review the complete version. Adoption keeps the current server source and labels.',
                  ),
                ),
                FilledButton(
                  onPressed: c.busy || !c.reviewed ? null : c.adopt,
                  child: Text(
                    t('采用已核对笔记并继续', 'Adopt reviewed note and continue'),
                  ),
                ),
              ],
              if (c.canFinishLabels)
                OutlinedButton(
                  onPressed: c.finishLabels,
                  child: Text(
                    t('仅继续保存本次标签', 'Finish only the requested labels'),
                  ),
                ),
              if (c.phase == RemoteHtmlCreationPhase.cleanup)
                FilledButton(
                  onPressed: _leaving || c.busy ? null : c.retryCleanup,
                  child: Text(t('重试本机清理', 'Retry device cleanup')),
                ),
              if (draft != null) ...[
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text(t('源码', 'Source'))),
                    ButtonSegment(
                      value: false,
                      label: Text(t('预览', 'Preview')),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: _leaving
                      ? null
                      : (value) => _switchSource(value.single),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height - 460)
                      .clamp(280.0, 520.0)
                      .toDouble(),
                  child: _source
                      ? HtmlCreationSourceSurface(
                          key: ValueKey('remote-create-source-$_sourceMount'),
                          coordinator: _sourceCoordinator,
                          source: draft.source,
                          title: _title.text,
                          english: widget.english,
                          builder: widget.sourceSurfaceBuilder,
                          onChanged: () {
                            if (mounted) setState(() {});
                          },
                          onSaveRequested: _saveCreation,
                          onStateChanged: _sourceStateChanged,
                          onReloadRequested: _reloadSource,
                        )
                      : NativeHtmlPreview(
                          source: draft.source,
                          english: widget.english,
                        ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                t(
                  '未保存及核对阶段使用轻量预览，不运行脚本。',
                  'Unsaved and recovery previews do not run scripts.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidatePage extends StatefulWidget {
  const _CandidatePage({required this.controller, required this.english});
  final RemoteHtmlCreationController controller;
  final bool english;
  @override
  State<_CandidatePage> createState() => _CandidatePageState();
}

class _CandidatePageState extends State<_CandidatePage> {
  final _keyword = TextEditingController();
  HtmlCreationCandidatePage? _result;
  bool _busy = false, _failed = false;
  String _query = '';
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.controller.candidates(
        page: page,
        keyword: _query,
      );
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('查找候选笔记', 'Find candidate notes'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t(
            '列表仅供选择。打开后会读取完整原文与标签，再由你确认采用。未找到不能证明创建失败。',
            'Choose a candidate for full source and label review. No result does not prove creation failed.',
          ),
        ),
        TextField(
          controller: _keyword,
          enabled: !_busy,
          decoration: InputDecoration(labelText: t('标题关键词', 'Title keyword')),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () {
                  _query = _keyword.text;
                  _result = null;
                  _load(1);
                },
          child: Text(t('查找', 'Search')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_failed) Text(t('读取失败，请重试。', 'Unable to read candidates. Retry.')),
        if (_failed)
          OutlinedButton(
            onPressed: _busy ? null : () => _load(_result?.page ?? 1),
            child: Text(t('重试', 'Retry')),
          ),
        if (!_busy && !_failed && _result?.candidates.isEmpty == true)
          Text(t('当前页没有候选笔记。', 'No candidates on this page.')),
        if (_result != null) ...[
          for (final note in _result!.candidates)
            Card(
              child: ListTile(
                enabled: !_busy && !_failed,
                leading: Icon(note.protected ? Icons.lock_outline : Icons.code),
                title: Text(note.title),
                subtitle: Text(
                  'ID ${note.id} · v${note.version}\n${note.modified}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.pop(context, note.id),
              ),
            ),
          Text('${_result!.page} / ${_result!.totalPages}'),
          Wrap(
            spacing: 12,
            children: [
              if (_result!.page > 1)
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(_result!.page - 1),
                  child: Text(t('上一页', 'Previous')),
                ),
              if (_result!.page < _result!.totalPages && _result!.page < 1000)
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(_result!.page + 1),
                  child: Text(t('下一页', 'Next')),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}
