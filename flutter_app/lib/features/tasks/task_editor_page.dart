import '../../core/task_draft_save_context.dart';
import '../../core/task_creation_guarded_repository.dart';
import '../../core/task_action_drafts.dart';
import 'task_action_components.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/markdown_editing.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.repository,
    required this.task,
    this.vault,
    this.attachments,
    this.english = false,
    this.clock,
    this.actions,
    this.onCreationRecovery,
  });
  final TasksRepository repository;
  final Future<void> Function()? onCreationRecovery;
  final TaskEditorActionBindings? actions;
  final TaskItem task;
  final TaskDraftVault? vault;
  final AttachmentRepository? attachments;
  final bool english;
  final DateTime Function()? clock;
  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _content;
  late TaskItem _saved;
  late String _dueDate;
  late bool _done;
  int? _topicId;
  int _actionsEpoch = 0;
  bool _actionsRetired = false, _requestingSuggestion = false;
  bool _creationReadOnly = false;
  Timer? _draftTimer;
  int _version = 0, _cleanupVersion = 0;
  bool _restoring = false, _suppressChanges = false, _choosingDraft = false;
  bool _ready = false,
      _saving = false,
      _preview = false,
      _allowLeave = false,
      _leaving = false,
      _savedOnce = false,
      _cleanupPending = false;
  int? _cleanupId;
  int _cleanupParent = 0;
  String? _error, _draftError;
  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  String t(String zh, String en) => widget.english ? en : zh;
  TaskItem get _snapshot => applyTaskTopic(
    _saved.copyWith(content: _content.text, dueDate: _dueDate, done: _done),
    _topicId == null
        ? null
        : _topicId == 0
        ? const TaskTopicChoice.clear()
        : TaskTopicChoice.select(_topicId!),
  );
  bool get _dirty =>
      (_saved.id == null && _content.text.trim().isNotEmpty) ||
      _content.text != _saved.content ||
      _dueDate != _saved.dueDate ||
      _done != _saved.done ||
      _topicId != _saved.topicId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saved = widget.task;
    _content = TextEditingController(text: _saved.content)
      ..addListener(_changed);
    final now = _now();
    _dueDate = _saved.dueDate.isEmpty
        ? taskDate(DateTime(now.year, now.month, now.day + 7))
        : _saved.dueDate;
    _done = _saved.done;
    _topicId = _saved.topicId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  bool get _ownedCurrent =>
      widget.actions == null || _actionsCurrent(widget.actions!, _actionsEpoch);

  bool _actionsCurrent(TaskEditorActionBindings binding, int epoch) =>
      mounted &&
      !_actionsRetired &&
      epoch == _actionsEpoch &&
      identical(widget.actions, binding) &&
      binding.isCurrent();

  TaskActionSnapshot _actionSnapshot(TaskEditorActionBindings binding) =>
      TaskActionSnapshot(
        scope: binding.scope,
        memberId: binding.memberId,
        task: _snapshot,
      );

  @override
  void didUpdateWidget(covariant TaskEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.actions, widget.actions) ||
        !identical(oldWidget.repository, widget.repository) ||
        oldWidget.task.id != widget.task.id ||
        oldWidget.task.parentId != widget.task.parentId) {
      _actionsEpoch++;
      _actionsRetired = true;
    }
  }

  Future<void> _suggest() async {
    final binding = widget.actions;
    if (binding == null ||
        binding.generateSuggestion == null ||
        _saved.id == null ||
        !_ready ||
        _saving ||
        _requestingSuggestion ||
        !_actionsCurrent(binding, _actionsEpoch)) {
      return;
    }
    final epoch = _actionsEpoch, origin = _actionSnapshot(binding);
    setState(() {
      _requestingSuggestion = true;
      _error = null;
    });
    try {
      if (!await binding.verifyExistingOwner(_saved.id!)) {
        throw const TaskActionRetired();
      }
      if (!_actionsCurrent(binding, epoch)) return;
      final proposal = await binding.generateSuggestion!(origin);
      if (!_actionsCurrent(binding, epoch)) return;
      if (proposal.origin.fingerprint != origin.fingerprint ||
          !proposal.complete ||
          _actionSnapshot(binding).fingerprint != origin.fingerprint) {
        throw const TaskActionChanged();
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TaskSuggestionPreviewPage(
            suggestion: proposal,
            english: widget.english,
            isCurrent: () => _actionsCurrent(binding, epoch),
            readCurrentDraft: () async {
              if (!_actionsCurrent(binding, epoch)) {
                throw const TaskActionRetired();
              }
              return _actionSnapshot(binding);
            },
            compareAndApply: (expected, update) async {
              // No await between CAS and writing the actual editor controller.
              if (!_actionsCurrent(binding, epoch) ||
                  _saving ||
                  !_ready ||
                  _actionSnapshot(binding).fingerprint != expected ||
                  update.id != _saved.id ||
                  update.parentId != _saved.parentId ||
                  update.topicId != _topicId ||
                  update.dueDate != _dueDate ||
                  update.done != _done) {
                return false;
              }
              _content.value = TextEditingValue(
                text: update.content,
                selection: TextSelection.collapsed(
                  offset: update.content.length,
                ),
              );
              return true;
            },
          ),
        ),
      );
    } catch (_) {
      if (_actionsCurrent(binding, epoch)) {
        setState(
          () => _error = t(
            '建议未应用，当前待办可能已变化，请重新核对。',
            'Suggestion not applied. Review the current task again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingSuggestion = false);
    }
  }

  Future<void> _chooseTopic() async {
    final binding = widget.actions, epoch = _actionsEpoch;
    if (binding == null ||
        binding.topicSource == null ||
        !_ready ||
        _saving ||
        !_actionsCurrent(binding, epoch)) {
      return;
    }
    final before = _snapshot, version = _version;
    try {
      if (before.id != null && !await binding.verifyExistingOwner(before.id!)) {
        throw const TaskActionRetired();
      }
      if (!_actionsCurrent(binding, epoch)) return;
      if (!mounted) return;
      final choice = await Navigator.of(context).push<TaskTopicChoice>(
        MaterialPageRoute(
          builder: (_) => TaskTopicPickerPage(
            source: binding.topicSource!,
            currentTopicId: _topicId,
            english: widget.english,
          ),
        ),
      );
      if (choice == null || !_actionsCurrent(binding, epoch)) return;
      if (version != _version || _saving) throw const TaskActionChanged();
      _topicId = choice.id;
      _changed();
    } catch (_) {
      if (_actionsCurrent(binding, epoch)) {
        setState(
          () => _error = t(
            '专题未改变，请重新核对当前待办。',
            'Topic was not changed. Review the current task again.',
          ),
        );
      }
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final vault = widget.vault;
      if (vault == null) {
        if (mounted) setState(() => _ready = true);
        return;
      }
      try {
        final draft = await vault.read(_saved.id, parentId: _saved.parentId);
        if (!mounted) return;
        if (draft != null &&
            (draft.content != _saved.content ||
                draft.dueDate != _saved.dueDate ||
                draft.done != _saved.done ||
                (draft.topicId != null && draft.topicId != _saved.topicId))) {
          setState(() => _choosingDraft = true);
          final action = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (dialog) => PopScope(
              canPop: false,
              child: AlertDialog(
                scrollable: true,
                title: Text(t('发现未保存草稿', 'Unsaved draft found')),
                content: Text(
                  t(
                    '恢复正文、截止日期、专题和完成状态，或继续使用已保存内容。',
                    'Restore the content, due date, topic and status, or use the saved task.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, 'back'),
                    child: Text(t('暂不打开', 'Go back')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, 'saved'),
                    child: Text(t('使用已保存内容', 'Use saved task')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, 'restore'),
                    child: Text(t('恢复草稿', 'Restore draft')),
                  ),
                ],
              ),
            ),
          );
          if (!mounted) return;
          setState(() => _choosingDraft = false);
          if (action == 'back') {
            _pop();
            return;
          }
          if (action == 'restore') {
            _content.text = draft.content;
            _dueDate = draft.dueDate;
            _done = draft.done;
            _topicId = draft.topicId ?? _saved.topicId;
          } else {
            await vault.remove(_saved.id, parentId: _saved.parentId);
          }
        }
        if (mounted) {
          setState(() {
            _ready = true;
            _draftError = null;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _ready = false;
            _draftError = error.toString();
          });
        }
      }
    } finally {
      _restoring = false;
    }
  }

  void _changed() {
    if (!_ready || _suppressChanges) return;
    _version++;
    _draftTimer?.cancel();
    setState(() => _error = null);
    if (widget.vault != null) {
      _draftTimer = Timer(const Duration(milliseconds: 600), _persist);
    }
  }

  Future<bool> _clearSavedDraft() async {
    if (!_cleanupPending) return true;
    final generation = _cleanupVersion;
    try {
      await widget.vault!.remove(_cleanupId, parentId: _cleanupParent);
      if (generation == _cleanupVersion) {
        _cleanupPending = false;
        if (mounted) setState(() => _draftError = null);
      }
      return !_cleanupPending;
    } catch (error) {
      if (mounted && generation == _cleanupVersion) {
        setState(() => _draftError = error.toString());
      }
      return false;
    }
  }

  Future<bool> _persist() async {
    if (_creationReadOnly) return true;
    final vault = widget.vault;
    if (!_ready || vault == null || !_ownedCurrent) return false;
    final version = _version;
    final task = _snapshot;
    await _clearSavedDraft();
    if (!mounted || version != _version) return false;
    try {
      if (_dirty) {
        await vault.write(task);
      } else {
        await vault.remove(task.id, parentId: task.parentId);
      }
      if (mounted && version == _version && !_cleanupPending) {
        setState(() => _draftError = null);
      }
      return !_cleanupPending;
    } catch (error) {
      if (mounted && version == _version) {
        setState(() => _draftError = error.toString());
      }
      return false;
    }
  }

  Future<void> _clearBrokenDraft() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('清除这份本机草稿？', 'Clear this local draft?')),
        content: Text(
          t(
            '只清除当前任务的本机未保存修改，已保存任务不变。',
            'Only this task’s unsaved local draft will be removed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('清除草稿', 'Clear draft')),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    try {
      await widget.vault!.remove(_saved.id, parentId: _saved.parentId);
      if (mounted) {
        setState(() {
          _ready = true;
          _draftError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _draftError = error.toString());
    }
  }

  Future<bool> _save() async {
    if (!_ready || _saving || !_ownedCurrent) return false;
    final repository = widget.repository,
        binding = widget.actions,
        epoch = _actionsEpoch;
    final snapshot = _snapshot;
    final version = _version;
    try {
      snapshot.writeBody();
    } catch (error) {
      setState(() => _error = error.toString());
      return false;
    }
    if (_cleanupPending) {
      final dirtyAtClick = _dirty;
      final vault = widget.vault;
      _draftTimer?.cancel();
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        final cleared = await _clearSavedDraft();
        if (!mounted ||
            !_ownedCurrent ||
            !identical(repository, widget.repository) ||
            !identical(binding, widget.actions) ||
            !identical(vault, widget.vault) ||
            epoch != _actionsEpoch) {
          return false;
        }
        if (!cleared) {
          // Retain edited known-ID content when possible; this never writes
          // task SQL/HTTP and cannot replace the still-pending original key.
          if (_dirty) await _persist();
          return false;
        }
        // A cleanup-only click never authorizes saving edits made while the
        // metadata deletion was pending. They remain an unsaved draft.
        if (!dirtyAtClick) return !_dirty;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    _draftTimer?.cancel();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await (repository is TaskDraftSaveRepository
          ? (repository as TaskDraftSaveRepository).saveWithDraft(
              snapshot,
              widget.vault,
            )
          : repository.save(snapshot));
      if (!mounted ||
          !_ownedCurrent ||
          !identical(repository, widget.repository) ||
          !identical(binding, widget.actions) ||
          epoch != _actionsEpoch) {
        return false;
      }
      _draftTimer?.cancel();
      final unchanged = version == _version;
      _version++;
      setState(() {
        _saved = snapshot.copyWith(id: id, content: snapshot.content.trim());
        if (unchanged && _content.text != _saved.content) {
          _suppressChanges = true;
          _content.value = TextEditingValue(
            text: _saved.content,
            selection: TextSelection.collapsed(offset: _saved.content.length),
          );
          _suppressChanges = false;
        }
        _savedOnce = true;
      });
      if (widget.vault != null) {
        _cleanupId = snapshot.id;
        _cleanupParent = snapshot.parentId;
        _cleanupPending = true;
        _cleanupVersion++;
        await _clearSavedDraft();
        if (_dirty) await _persist();
      }
      if (repository is TaskDraftSaveRepository &&
          (repository as TaskDraftSaveRepository)
                  .taskCreationRecovery
                  ?.record !=
              null) {
        if (mounted)
          setState(() {
            _version++;
            _creationReadOnly = true;
          });
        return false;
      }
      return !_dirty && !_cleanupPending;
    } catch (error) {
      if (error is TaskCreationNeedsReview) {
        _draftTimer?.cancel();
        if (mounted)
          setState(() {
            _version++;
            _creationReadOnly = true;
            _error = null;
          });
        return false;
      }

      if (mounted) {
        _draftTimer?.cancel();
        setState(() {
          if (error is TaskSaveFailure && error.savedId > 0) {
            _saved = snapshot.copyWith(
              id: error.savedId,
              content: snapshot.content.trim(),
            );
            _savedOnce = true;
          }
          _error = error.toString();
        });
        await _persist();
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = _now();
    final date = await showDatePicker(
      context: context,
      initialDate: validTaskDate(_dueDate)
          ? DateTime.parse(_dueDate)
          : DateTime(now.year, now.month, now.day + 7),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      currentDate: _now(),
      helpText: t('选择截止日期', 'Choose due date'),
    );
    if (!mounted || date == null) return;
    _dueDate = taskDate(date);
    _changed();
  }

  void _pop() {
    if (!mounted) return;
    _version++;
    _draftTimer?.cancel();
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _leave() async {
    if (_leaving) return;
    if (_saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('正在保存，请稍候', 'Saving. Please wait.'))),
      );
      return;
    }
    if (!_ready || (!_dirty && !_cleanupPending)) {
      _pop();
      return;
    }
    _leaving = true;
    try {
      if (_cleanupPending && !_dirty) {
        if (await _clearSavedDraft()) {
          _pop();
          return;
        }
        if (!mounted) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: Text(t('任务已保存，草稿清理失败', 'Task saved; draft cleanup failed')),
            content: Text(
              t(
                '已保存为任务#${_saved.id}。旧草稿仍在本机，下次打开时请勿重复创建。',
                'Saved as task #${_saved.id}. The old local draft remains; avoid creating it again.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(t('保留编辑页', 'Stay here')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(t('仍然离开', 'Leave anyway')),
              ),
            ],
          ),
        );
        if (leave == true) _pop();
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('有未保存的修改', 'Unsaved changes')),
          content: Text(
            t(
              '请选择保存、保留本机草稿或放弃修改。',
              'Save the task, keep a local draft, or discard the changes.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'discard'),
              child: Text(t('放弃修改', 'Discard changes')),
            ),
            if (widget.vault != null)
              TextButton(
                onPressed: () => Navigator.pop(dialog, 'keep'),
                child: Text(t('保留草稿并离开', 'Keep draft and leave')),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'save'),
              child: Text(t('保存并离开', 'Save and leave')),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      _draftTimer?.cancel();
      if (action == 'save') {
        if (await _save()) _pop();
        return;
      }
      if (action == 'keep') {
        if (await _persist()) _pop();
        return;
      }
      if (action == 'discard') {
        _version++;
        try {
          if (!await _clearSavedDraft()) return;
          await widget.vault?.remove(_saved.id, parentId: _saved.parentId);
          _pop();
        } catch (error) {
          if (mounted) setState(() => _draftError = error.toString());
        }
      }
    } finally {
      _leaving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _draftTimer?.cancel();
      _persist();
    }
  }

  @override
  void dispose() {
    _actionsEpoch++;
    _actionsRetired = true;
    _draftTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _content.removeListener(_changed);
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_creationReadOnly) return _buildEditor(context);
    final repository = widget.repository;
    final frozen = repository is TaskDraftSaveRepository
        ? (repository as TaskDraftSaveRepository)
              .taskCreationRecovery
              ?.record
              ?.body
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('待办创建记录待核对', 'Review task creation record')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t(
              '创建记录尚需核对，已停止编辑和再次创建。',
              'Review the creation record. Editing and creation are stopped.',
            ),
          ),
          if (frozen != null) ...[
            Text(t('提交时完整草稿（只读）', 'Complete submitted draft (read only)')),
            SelectableText(frozen['content'] as String),
            Text(
              t('提交日期：', 'Submitted due: ') + (frozen['due_date'] as String),
            ),
            Text(t('提交完成状态：', 'Submitted done: ') + frozen['done'].toString()),
            Text(
              t('提交父待办 ID：', 'Submitted parent ID: ') +
                  frozen['parent_id'].toString(),
            ),
            Text(
              t('提交专题 ID：', 'Submitted topic ID: ') +
                  frozen['topic_id'].toString(),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            t(
              '当前编辑内容（仅内存；关闭可能丢失未提交修改）',
              'Current editor content (memory only; closing may lose unsubmitted changes)',
            ),
          ),
          SelectableText(_content.text),
          Text(t('日期：', 'Due: ') + _dueDate),
          Text(t('完成：', 'Done: ') + _done.toString()),
          Text(t('父待办 ID：', 'Parent task ID: ') + _saved.parentId.toString()),
          Text(t('专题 ID：', 'Topic ID: ') + (_topicId ?? 0).toString()),
          if (widget.onCreationRecovery != null)
            FilledButton(
              onPressed: () async {
                final callback = widget.onCreationRecovery;
                if (callback != null && mounted) await callback();
              },
              child: Text(t('只读核对恢复记录', 'Review recovery record read only')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('返回并保留记录', 'Return and keep record')),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) => PopScope(
    canPop: _allowLeave || (!_dirty && !_saving && !_cleanupPending),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: BackButton(onPressed: _leave),
        title: Text(
          _saved.id != null
              ? t('编辑待办', 'Edit task')
              : _saved.parentId > 0
              ? t('新建子待办', 'New subtask')
              : t('新建待办', 'New task'),
        ),
        actions: [
          TextButton(
            onPressed: !_ready || _saving ? null : _save,
            child: Text(_saving ? t('保存中…', 'Saving…') : t('保存', 'Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _savedOnce && !_dirty
                ? t('已保存', 'Saved')
                : _dirty
                ? t('有未保存的修改', 'Unsaved changes')
                : t('修改将在保存后生效', 'Changes take effect after saving'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_draftError != null)
            MaterialBanner(
              content: Text(t('本机草稿：', 'Local draft: ') + _draftError!),
              actions: [
                TextButton(
                  onPressed: _ready ? _persist : _restore,
                  child: Text(t('重试', 'Retry')),
                ),
                if (!_ready)
                  TextButton(
                    onPressed: _clearBrokenDraft,
                    child: Text(t('清除草稿', 'Clear draft')),
                  ),
              ],
            ),
          if (!_ready && _draftError == null && !_choosingDraft)
            const LinearProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            t('待办内容', 'Task content'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (_preview)
            BookstarkMarkdown(
              data: _content.text,
              attachments: widget.attachments,
              english: widget.english,
            )
          else
            TextField(
              key: const Key('task-content'),
              controller: _content,
              enabled: _ready,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: t('写下清晰、可执行的待办…', 'Write a clear, actionable task…'),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_content.text.trim().runes.length} / 1000',
              style: TextStyle(
                color: _content.text.trim().runes.length > 1000
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in [
                (Icons.format_bold, '**', '**', t('加粗', 'Bold')),
                (Icons.format_list_bulleted, '- ', '', t('列表', 'List')),
                (
                  Icons.check_box_outlined,
                  '- [ ] ',
                  '',
                  t('勾选列表', 'Checklist'),
                ),
              ])
                IconButton.outlined(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: !_ready || _preview
                      ? null
                      : () => wrapMarkdown(_content, item.$2, item.$3),
                  tooltip: item.$4,
                  icon: Icon(item.$1),
                ),
              TextButton(
                onPressed: !_ready
                    ? null
                    : () => setState(() => _preview = !_preview),
                child: Text(
                  _preview ? t('继续编辑', 'Continue editing') : t('预览', 'Preview'),
                ),
              ),
            ],
          ),
          if (widget.actions?.generateSuggestion != null && _saved.id != null)
            OutlinedButton.icon(
              onPressed:
                  !_ready || _saving || _requestingSuggestion || _actionsRetired
                  ? null
                  : _suggest,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _requestingSuggestion
                    ? t('正在生成只读建议', 'Preparing a read-only suggestion')
                    : t('AI 建议', 'AI suggestions'),
              ),
            ),
          if (widget.actions?.topicSource != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: !_ready || _saving || _actionsRetired
                  ? null
                  : _chooseTopic,
              icon: const Icon(Icons.topic_outlined),
              label: Text(
                _topicId == null || _topicId == 0
                    ? t('专题：无', 'Topic: none')
                    : t('专题 #', 'Topic #') + _topicId.toString(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            t('截止日期', 'Due date'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _ready ? _pickDate : null,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 48),
              textStyle: Theme.of(context).textTheme.bodyMedium,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(_dueDate)),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _saved.id == null || widget.task.dueDate.isEmpty
                ? t(
                    '默认七天后，可选择其他日期',
                    'Defaults to seven days from now. Choose another date if needed.',
                  )
                : t('点击日期修改截止日期', 'Tap to change the due date'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _done,
            onChanged: !_ready
                ? null
                : (value) {
                    _done = value!;
                    _changed();
                  },
            title: Text(t('已完成', 'Completed')),
          ),
          const SizedBox(height: 16),
          Text(
            _saved.parentId == 0
                ? t('父待办：无（根待办）', 'Parent: none (root task)')
                : t(
                    '父待办：#${_saved.parentId}',
                    'Parent task: #${_saved.parentId}',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text(
            t(
              '未保存时离开会提示保留或放弃修改',
              'Leaving with unsaved changes will ask whether to keep or discard them.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}
