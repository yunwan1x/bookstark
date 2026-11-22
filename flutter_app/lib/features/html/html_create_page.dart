import 'dart:async';

import 'package:flutter/material.dart';

import '../complex_editors/complex_editor_browser.dart';

import '../../core/html_notes_repository.dart';
import '../../core/local_html_creation_controller.dart';
import '../../core/local_html_notes_repository.dart';
import '../../core/labels_repository.dart';
import '../../widgets/label_picker.dart';
import 'html_preview.dart';
import 'html_browser_session.dart';
import 'html_note_page.dart';
import 'html_creation_source_coordinator.dart';
import 'html_creation_source_surface.dart';
import 'html_version_view.dart';
import 'html_code_source_surface.dart';

class HtmlCreatePage extends StatefulWidget {
  const HtmlCreatePage({
    super.key,
    required this.controller,
    required this.labels,
    this.english = false,
    this.onDisposed,
    this.sourceSurfaceBuilder = defaultHtmlSourceSurface,
    this.readOnlySourceSurfaceBuilder,
  });
  final LocalHtmlCreationController controller;
  final LabelsRepository labels;
  final bool english;
  final VoidCallback? onDisposed;
  final HtmlSourceSurfaceBuilder sourceSurfaceBuilder;
  final HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder;
  @override
  State<HtmlCreatePage> createState() => _HtmlCreatePageState();
}

class _HtmlCreatePageState extends State<HtmlCreatePage> {
  LocalHtmlCreationController get c => widget.controller;
  late final TextEditingController _title;
  Timer? _timer;
  late final HtmlCreationSourceCoordinator _sourceCoordinator;
  int _sourceMount = 0;
  bool _sourceClosing = false, _saveInFlight = false;
  int? _sourceScheduledRevision;
  bool _source = true, _allowPop = false, _popping = false, _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: c.draft.title);
    _sourceCoordinator = HtmlCreationSourceCoordinator(
      freezeEdit: (source) => HtmlNoteEdit(
        title: _title.text,
        source: source,
        labels: c.draft.labels,
      ),
      applyCapturedEdit: (value) {
        final old = c.draft;
        if (value.title != old.title ||
            value.source != old.source ||
            value.labels.length != old.labels.length ||
            !value.labels.asMap().entries.every(
              (e) => e.value == old.labels[e.key],
            )) {
          c.edit(value);
        }
      },
      flushCreationJournal: c.flush,
      create: c.save,
      creationStillEditable: () => c.canEdit,
      pendingOrUnknown: () => !{
        HtmlCreationPhase.editing,
        HtmlCreationPhase.finished,
      }.contains(c.phase),
    );
    _title.addListener(_titleChanged);
    c.addListener(_updated);
  }

  void _titleChanged() {
    if (c.canEdit && !_sourceCoordinator.busy && !_leaving) {
      c.edit(
        HtmlNoteEdit(
          title: _title.text,
          source: c.draft.source,
          labels: c.draft.labels,
        ),
      );
    }
  }

  void _updated() {
    if (!mounted) return;
    _timer?.cancel();
    if (c.phase == HtmlCreationPhase.finished) {
      if (!_saveInFlight) _pop(c.created?.metadata.id);
      setState(() {});
      return;
    }
    if (c.canEdit && c.dirty) {
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
        if (c.phase == HtmlCreationPhase.finished) _pop(c.created?.metadata.id);
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
    if (!c.dirty && c.canEdit) {
      _sourceCoordinator.invalidate();
      await HtmlBrowserSession.closeActive();
      await _sourceCoordinator.drain();
      final removed = await c.discardDraft();
      _leaving = false;
      if (removed) _pop(null);
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final pending = !c.canEdit;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('返回前确认', 'Before leaving'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                pending
                    ? t(
                        '新建结果尚未结束核对。保留记录后，下次新建HTML时先核对本机已保存的笔记。',
                        'Creation is unresolved. Keep its record and review the saved device note next time.',
                      )
                    : t('尚有未保存的新建草稿。', 'There is an unsaved new HTML draft.'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('继续编辑', 'Keep editing')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'keep'),
                child: Text(
                  pending
                      ? t('保留核对记录并返回', 'Keep recovery record and leave')
                      : t('保留草稿并返回', 'Keep draft and leave'),
                ),
              ),
              if (!pending) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(context, 'discard'),
                  child: Text(t('放弃草稿', 'Discard draft')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == null) {
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
    final stored = choice == 'discard'
        ? await c.discardDraft()
        : await c.flush();
    _leaving = false;
    if (stored) {
      _pop(null);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _labels() async {
    final labels = await showLabelPicker(
      context,
      repository: widget.labels,
      selected: c.draft.labels,
      english: widget.english,
    );
    if (labels != null && mounted && c.canEdit) {
      c.edit(
        HtmlNoteEdit(
          title: _title.text,
          source: c.draft.source,
          labels: labels,
        ),
      );
    }
  }

  Future<void> _review() async {
    final note = c.observed;
    if (note == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HtmlVersionViewPage(
          heading: t('核对已保存笔记', 'Review saved note'),
          title: note.metadata.title,
          source: note.source,
          labels: note.labels,
          english: widget.english,
          sourceSurfaceBuilder: widget.readOnlySourceSurfaceBuilder,
        ),
      ),
    );
    if (mounted) c.markReviewed(note);
  }

  Future<void> _endUnavailable() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('结束这次新建核对？', 'End this creation review?')),
        content: Text(
          t(
            '这不会恢复已删除的笔记，也不会再次创建。',
            'This will not restore a deleted note or create another one.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('结束核对', 'End review')),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await c.endUnavailable();
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_updated);
    _title.removeListener(_titleChanged);
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
    final pending = c.phase != HtmlCreationPhase.editing;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff1f5ff),
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: c.busy || _leaving ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            t(
              pending ? '核对新建结果' : '新建 HTML',
              pending ? 'Review creation' : 'New HTML',
            ),
          ),
          actions: [
            if (c.phase == HtmlCreationPhase.editing)
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
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Chip(
                    avatar: const Icon(Icons.computer),
                    label: Text(t('本地空间', 'Local space')),
                  ),
                  if (!pending) Chip(label: Text(t('未保存', 'Unsaved'))),
                ],
              ),
              const SizedBox(height: 12),
              if (pending)
                Card(
                  color: const Color(0xffffedca),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.phase == HtmlCreationPhase.cleanup
                              ? t('已保存，草稿清理待完成', 'Saved; draft cleanup pending')
                              : t('创建结果未确认', 'Creation result unresolved'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(
                            '请先核对本机保存，避免重复创建。',
                            'Review the saved device note before creating another.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (c.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (c.failure != null) ...[
                const SizedBox(height: 12),
                Text(
                  c.failure is HtmlCreationNameConflict
                      ? t(
                          '已有同名文章，请调整标题后保存。',
                          'An article with this title already exists. Choose another title.',
                        )
                      : c.failure is HtmlCreationTargetUnavailable
                      ? t(
                          '本次创建的笔记已删除或类型发生变化，不会再次创建。',
                          'This creation was deleted or changed format. It will not be created again.',
                        )
                      : c.failure is HtmlNoteChanged
                      ? t(
                          '已保存内容有变化，请重新查看完整版本。',
                          'Saved content changed. Review the full version again.',
                        )
                      : c.failure is FormatException
                      ? t(
                          '标题过长、为空或内容无效，请检查输入。',
                          'Check the title and content before saving.',
                        )
                      : t(
                          '操作未完成，请核对结果或稍后重试。',
                          'The operation did not finish. Review its result or retry later.',
                        ),
                ),
              ],
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
                const SizedBox(height: 12),
                Text(
                  t(
                    '本机草稿记录未能更新，请先重试。',
                    'The device draft could not be updated. Retry before leaving.',
                  ),
                ),
                if (c.phase != HtmlCreationPhase.cleanup)
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
              const SizedBox(height: 16),
              if (pending) Text(t('草稿标题（只读）', 'Draft title (read only)')),
              if (c.canEdit && !_sourceCoordinator.busy)
                TextField(
                  key: const ValueKey('html-create-title'),
                  controller: _title,
                  enabled: !_leaving && !c.busy,
                  decoration: InputDecoration(labelText: t('标题', 'Title')),
                )
              else
                Text(
                  c.draft.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              const SizedBox(height: 12),
              Text(t('标签', 'Labels')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in c.draft.labels)
                    InputChip(
                      label: Text(label),
                      onDeleted:
                          c.canEdit && !_sourceCoordinator.busy && !_leaving
                          ? () => c.edit(
                              HtmlNoteEdit(
                                title: _title.text,
                                source: c.draft.source,
                                labels: c.draft.labels
                                    .where((v) => v != label)
                                    .toList(),
                              ),
                            )
                          : null,
                    ),
                  if (c.canEdit && !_leaving)
                    ActionChip(
                      avatar: const Icon(Icons.add),
                      label: Text(t('添加标签', 'Add labels')),
                      onPressed: _leaving || c.busy ? null : _labels,
                    ),
                ],
              ),
              if ({
                HtmlCreationPhase.unknown,
                HtmlCreationPhase.review,
              }.contains(c.phase)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _leaving || c.busy ? null : c.verify,
                  icon: const Icon(Icons.search),
                  label: Text(t('只读核对本机新建结果', 'Verify device creation')),
                ),
              ],
              if (c.confirmedAbsent) ...[
                Text(
                  t(
                    '本机未发现这次创建记录。可以使用原标识明确重试。',
                    'No record of this creation was found on this device. You can explicitly retry with the same identity.',
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy ? null : c.allowRetryAfterAbsent,
                  child: Text(t('返回编辑并明确重试', 'Return to editing and retry')),
                ),
              ],
              if (c.observed != null &&
                  c.phase == HtmlCreationPhase.review) ...[
                Card(
                  child: ListTile(
                    onTap: c.busy ? null : _review,
                    title: Text(c.observed!.metadata.title),
                    subtitle: Text(
                      t(
                        '笔记 ID ${c.observed!.metadata.id} · 查看完整版本',
                        'Note ID ${c.observed!.metadata.id} · View full version',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                FilledButton(
                  onPressed: _leaving || c.busy || !c.reviewed
                      ? null
                      : c.adoptObserved,
                  child: Text(
                    t('采用已核对笔记并继续', 'Adopt reviewed note and continue'),
                  ),
                ),
                Text(
                  t(
                    '将打开已有笔记，不会再次新建。',
                    'This opens the existing note without creating another.',
                  ),
                ),
              ],
              if (c.failure is HtmlCreationTargetUnavailable &&
                  c.phase == HtmlCreationPhase.unknown)
                OutlinedButton(
                  onPressed: c.busy ? null : _endUnavailable,
                  child: Text(t('结束这次新建核对', 'End this creation review')),
                ),
              if (c.phase == HtmlCreationPhase.cleanup)
                FilledButton(
                  onPressed: _leaving || c.busy ? null : c.retryCleanup,
                  child: Text(t('重试本机清理', 'Retry device cleanup')),
                ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(t('源码', 'Source'))),
                  ButtonSegment(value: false, label: Text(t('预览', 'Preview'))),
                ],
                selected: {_source},
                onSelectionChanged: _leaving
                    ? null
                    : (v) => _switchSource(v.single),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height - 420)
                    .clamp(280.0, 520.0)
                    .toDouble(),
                child: _source
                    ? HtmlCreationSourceSurface(
                        key: ValueKey('local-create-source-$_sourceMount'),
                        coordinator: _sourceCoordinator,
                        source: c.draft.source,
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
                        source: c.draft.source,
                        english: widget.english,
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.computer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(
                        '保存在此设备。轻量预览不运行脚本。',
                        'Saved on this device. Lightweight preview does not run scripts.',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
