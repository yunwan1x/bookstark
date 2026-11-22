import '../../core/local_model_stream.dart';
import '../../core/local_assistant_draft_ledger.dart';
import '../../core/local_assistant_knowledge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/assistant_repository.dart';
import '../../core/attachments.dart';
import '../../widgets/bookstark_markdown.dart';
import 'source_sheet.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.repository,
    this.vault,
    this.attachments,
    this.english = false,
    this.onSpeak,
    this.onOpenSource,
    this.onEditLocalDraft,
    this.onForgetLocalDraft,
    this.local = false,
    this.modelLabel,
    this.knowledgeGranted = false,
  });
  final Future<void> Function(String draftId)? onEditLocalDraft;
  final Future<void> Function(String draftId)? onForgetLocalDraft;
  final AssistantDataSource repository;
  final bool local;
  final String? modelLabel;
  final bool knowledgeGranted;
  final Future<void> Function(Map<String, Object?> source)? onOpenSource;
  final AssistantConversationVault? vault;
  final AttachmentRepository? attachments;
  final bool english;
  final Future<void> Function(String markdown)? onSpeak;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AssistantSession? _session;
  List<AssistantMessage> _messages = [];
  List<AssistantDraft> _drafts = [];
  final _resolving = <String>{};
  Completer<void>? _abort;
  Timer? _saveTimer, _deltaTimer, _checkpointTimer;
  int _partialBytes = 0;
  String? _error, _storageError, _pendingQuestion;
  String _partial = '', _progress = '';
  bool _loading = true,
      _ready = false,
      _busy = false,
      _serverBusy = false,
      _resetting = false,
      _stopping = false,
      _allowLeave = false,
      _leaving = false,
      _stopped = false;
  int _loadGeneration = 0;
  bool _contextReadFailed = false;
  bool _confirmingReplacement = false;
  String t(String zh, String en) => widget.english ? en : zh;
  String _failure(Object error) {
    if (!widget.local) return error.toString();
    if (error is LocalAssistantDraftNeedsAttention) {
      return t(
        '仍有关联草稿，请先在本地备份的恢复管理中处理。',
        'Linked drafts remain. Handle them in Local backup recovery management first.',
      );
    }
    if (error is LocalModelStreamFailure) {
      return switch (error.issue) {
        LocalModelStreamIssue.authentication => t(
          '模型认证失败，请检查设置中的密钥。',
          'Model authentication failed. Check the key in Settings.',
        ),
        LocalModelStreamIssue.cancelled => t('回答已停止。', 'Reply stopped.'),
        LocalModelStreamIssue.retired => t(
          '本地空间已变化，请重新打开助手。',
          'The local space changed. Reopen the assistant.',
        ),
        LocalModelStreamIssue.busy => t(
          '已有回答正在进行。',
          'A reply is already in progress.',
        ),
        LocalModelStreamIssue.timeout => t(
          '模型响应超时，已保留收到的内容。',
          'The model timed out. Received content is retained.',
        ),
        LocalModelStreamIssue.outputLimit => t(
          '回答或资料超过本轮限制，已保留收到的内容。',
          'The reply or sources exceeded this turn limit. Received content is retained.',
        ),
        _ => t(
          '模型连接未完成，已保留收到的内容，请检查配置后重试。',
          'The model response did not complete. Received content is retained. Check the configuration and retry.',
        ),
      };
    }
    if (error is LocalKnowledgeFailure) {
      return t(
        '本地资料暂时无法读取，请检查知识权限和资源状态。',
        'Local sources could not be read. Check knowledge permission and resource availability.',
      );
    }
    return t(
      '本地助手暂时无法完成操作，请重试。',
      'The local assistant could not complete this operation. Retry.',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(_inputChanged);
    _load();
  }

  void _inputChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _saveTimer?.cancel();
    if (_ready && !_resetting) {
      _saveTimer = Timer(const Duration(milliseconds: 600), _persist);
    }
  }

  Future<bool> _persist() async {
    _saveTimer?.cancel();
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    final session = _session;
    if (!_ready || session == null || widget.vault == null) {
      return true;
    }
    try {
      await widget.vault!.save(
        session.id,
        _messages,
        input: _input.text,
        pendingQuestion: _pendingQuestion,
        partial: _partial,
      );
      if (mounted) {
        setState(() => _storageError = null);
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _storageError = error.toString());
      }
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _persist();
    }
  }

  Future<void> _load() async {
    if (_busy || _resetting || _resolving.isNotEmpty) {
      return;
    }
    final current = _ready && _session != null
        ? AssistantConversation(
            _session!.id,
            List.of(_messages),
            input: _input.text,
            pendingQuestion: _pendingQuestion,
            partial: _partial,
          )
        : null;
    final generation = ++_loadGeneration;
    _saveTimer?.cancel();
    _contextReadFailed = false;
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
    });
    try {
      final session = await widget.repository.open();
      AssistantConversation? saved;
      try {
        saved = current ?? await widget.vault?.load();
      } catch (_) {
        _contextReadFailed = true;
        rethrow;
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      if (saved != null && saved.session != session.id) {
        final clear = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('会话已更新', 'Conversation changed')),
            content: Text(
              t(
                widget.local
                    ? '模型会话与保存的上下文不同。清空旧上下文后开始新会话？'
                    : '服务器会话与本地上下文不同。清空旧上下文后开始新会话？',
                widget.local
                    ? 'The model conversation differs from stored context. Clear the old context and start this conversation?'
                    : 'The server conversation differs from local context. Clear the old context and start this conversation?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('返回', 'Back')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('清空旧上下文', 'Clear old context')),
              ),
            ],
          ),
        );
        if (clear != true) {
          if (mounted) {
            Navigator.maybePop(context);
          }
          return;
        }
        await widget.vault?.clear();
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      _input.text = saved != null && saved.session == session.id
          ? saved.input
          : '';
      setState(() {
        _session = session;
        _messages = saved != null && saved.session == session.id
            ? List.of(saved.messages)
            : [];
        _pendingQuestion = saved != null && saved.session == session.id
            ? saved.pendingQuestion
            : null;
        _partial = saved != null && saved.session == session.id
            ? saved.partial
            : '';
        _partialBytes = utf8.encode(_partial).length;
        _stopped = _pendingQuestion != null;
        _drafts = session.drafts;
        _serverBusy = session.busy;
        _ready = true;
        _storageError = null;
      });
      await _persist();
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _following =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.offset < 120;
  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<bool> _confirmPartialReplacement() async {
    if (_partial.isEmpty) return true;
    if (_confirmingReplacement) return false;
    final repository = widget.repository;
    final session = _session;
    final generation = _loadGeneration;
    final partial = _partial;
    final pendingQuestion = _pendingQuestion;
    setState(() => _confirmingReplacement = true);
    bool? replace;
    try {
      replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('替换未完成回答？', 'Replace the unfinished reply?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  '当前回答尚未完成。替换后将发送新问题；这段未完成回答不会加入模型上下文。',
                  'This reply is unfinished. Replacing it sends the new question. The unfinished reply will not be included in model context.',
                ),
              ),
              if (pendingQuestion != null) ...[
                const SizedBox(height: 16),
                Text(pendingQuestion),
              ],
              const SizedBox(height: 16),
              BookstarkMarkdown(
                data: partial,
                attachments: widget.attachments,
                english: widget.english,
              ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('返回并保留', 'Keep unfinished reply')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('替换并发送', 'Replace and send')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingReplacement = false);
    }
    return replace == true &&
        mounted &&
        identical(repository, widget.repository) &&
        identical(session, _session) &&
        generation == _loadGeneration &&
        partial == _partial &&
        pendingQuestion == _pendingQuestion &&
        !_leaving &&
        !_resetting &&
        !_busy &&
        !_serverBusy &&
        _ready &&
        _resolving.isEmpty &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  Future<void> _send() async {
    final session = _session;
    if (!_ready ||
        session == null ||
        _busy ||
        _resetting ||
        _serverBusy ||
        _resolving.isNotEmpty ||
        _confirmingReplacement) {
      return;
    }
    final question = _input.text.trim();
    if (question.isEmpty || utf8.encode(question).length > 8000) {
      setState(
        () => _error = t(
          '请输入问题，最多8000字节',
          'Enter a question (maximum 8000 bytes).',
        ),
      );
      return;
    }
    if (_partial.isNotEmpty && !await _confirmPartialReplacement()) return;
    _saveTimer?.cancel();
    final abort = Completer<void>();
    _abort = abort;
    _input.clear();
    setState(() {
      _busy = true;
      _stopping = false;
      _stopped = false;
      _pendingQuestion = question;
      _partial = '';
      _partialBytes = 0;
      _progress = '';
      _error = null;
    });
    _bottom();
    try {
      await for (final update in widget.repository.chat(
        session: session.id,
        message: question,
        history: boundedAssistantHistory(_messages),
        abortTrigger: abort.future,
      )) {
        if (!mounted || abort.isCompleted) {
          break;
        }
        final follow = _following;
        if (update.type == 'round') {
          _deltaTimer?.cancel();
          _deltaTimer = null;
          setState(() {
            _partial = '';
            _partialBytes = 0;
            _progress = t('正在思考…', 'Thinking…');
          });
        }
        if (update.type == 'delta') {
          _partialBytes += utf8.encode(update.text).length;
          if (_partialBytes > 256 * 1024) {
            throw const FormatException(
              'Assistant reply exceeds display limit',
            );
          }
          _partial += update.text;
          _checkpointTimer ??= Timer(const Duration(seconds: 2), () {
            _checkpointTimer = null;
            if (mounted) _persist();
          });
          _deltaTimer ??= Timer(const Duration(milliseconds: 50), () {
            _deltaTimer = null;
            if (mounted) {
              setState(() {});
              if (_following) {
                _bottom();
              }
            }
          });
        }
        if (update.type == 'progress') {
          setState(
            () => _progress = switch (update.text) {
              'search' => t('正在搜索知识库…', 'Searching your knowledge…'),
              'read' => t('正在读取资料…', 'Reading sources…'),
              'draft_note' => t('正在准备笔记草稿…', 'Preparing note draft…'),
              'draft_task' => t('正在准备待办草稿…', 'Preparing task draft…'),
              _ => t('正在核对工具结果…', 'Checking tool results…'),
            },
          );
        }
        if (update.type == 'done') {
          _deltaTimer?.cancel();
          _deltaTimer = null;
          setState(() {
            final combined = [..._messages, ...update.messages];
            _messages = combined.length > 38
                ? combined.sublist(combined.length - 38)
                : combined;
            _drafts = [
              ..._drafts,
              ...update.drafts.where(
                (draft) => !_drafts.any((old) => old.id == draft.id),
              ),
            ];
            _pendingQuestion = null;
            _partial = '';
            _progress = '';
          });
          await _persist();
        }
        if (follow && update.type != 'delta') {
          _bottom();
        }
      }
    } catch (error) {
      if (mounted) {
        if (_input.text.isEmpty) {
          _input.text = question;
        }
        setState(() {
          _stopped = abort.isCompleted;
          if (!abort.isCompleted) {
            _error = _failure(error);
          }
        });
      }
    } finally {
      _deltaTimer?.cancel();
      _deltaTimer = null;
      if (!abort.isCompleted) {
        abort.complete();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _stopping = false;
        });
        await _persist();
      }
      if (identical(_abort, abort)) {
        _abort = null;
      }
    }
  }

  void _stop() {
    if (!_busy || _stopping) {
      return;
    }
    if (_input.text.isEmpty && _pendingQuestion != null) {
      _input.text = _pendingQuestion!;
    }
    _deltaTimer?.cancel();
    _deltaTimer = null;
    setState(() {
      _stopping = true;
      _stopped = true;
    });
    final abort = _abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
  }

  Future<void> _clearLocalContext() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('清空本地上下文？', 'Clear local context?')),
        content: Text(
          t(
            '仅清空本机对话和待发送输入，服务器草稿和知识库不受影响。',
            'Only this device’s conversation and unsent input are cleared. Server drafts and knowledge remain.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('清空', 'Clear')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    try {
      await widget.vault?.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _failure(error));
      }
    }
  }

  Future<void> _reset() async {
    if (!_ready || _busy || _resetting || _resolving.isNotEmpty) {
      return;
    }
    final session = _session!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('新建会话？', 'Start a new conversation?')),
        content: Text(
          t(
            '将清空当前上下文并放弃未确认草稿，已创建的资源仍保留。',
            'Clear this context and discard pending drafts. Created resources remain.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('新建会话', 'New conversation')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    _saveTimer?.cancel();
    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      final next = await widget.repository.reset(session.id);
      if (!mounted) {
        return;
      }
      _input.clear();
      setState(() {
        _session = next;
        _messages = [];
        _drafts = next.drafts;
        _serverBusy = next.busy;
        _pendingQuestion = null;
        _partial = '';
        _stopped = false;
      });
      await widget.vault?.clear();
      await _persist();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  Future<void> _forgetLocalDraft(AssistantDraft draft) async {
    final forget = widget.onForgetLocalDraft;
    if (!widget.local ||
        forget == null ||
        !{'done', 'cancelled'}.contains(draft.status) ||
        !_ready ||
        _session == null ||
        _busy ||
        _resetting ||
        _serverBusy ||
        _resolving.isNotEmpty) {
      return;
    }
    final session = _session!.id, generation = _loadGeneration;
    final repository = widget.repository;
    bool current() =>
        mounted &&
        identical(repository, widget.repository) &&
        _session?.id == session &&
        generation == _loadGeneration;
    setState(() {
      _resolving.add(draft.id);
      _error = null;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('移除此记录？', 'Remove this record?')),
          content: Text(
            t(
              '只移除助手列表中的这条记录，不会删除已保存资料或保留草稿。',
              'Only this record is removed from the assistant list. Saved resources and retained editor drafts are not deleted.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('返回并保留', 'Keep record')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认移除此记录', 'Remove this record')),
            ),
          ],
        ),
      );
      if (confirmed != true || !current()) return;
      await forget(draft.id);
      if (!current()) return;
      final fresh = await repository.open();
      if (!current() || fresh.id != session) return;
      setState(() {
        _session = fresh;
        _drafts = fresh.drafts;
        _serverBusy = fresh.busy;
      });
    } catch (error) {
      if (current()) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _resolving.remove(draft.id));
    }
  }

  Future<void> _resolve(AssistantDraft draft, bool confirm) async {
    if (_busy ||
        _resetting ||
        _serverBusy ||
        _resolving.contains(draft.id) ||
        (draft.status != 'pending' &&
            !(widget.local && confirm && draft.status == 'unknown')) ||
        _session == null) {
      return;
    }
    if (confirm && widget.local) {
      final edit = widget.onEditLocalDraft;
      if (edit == null) return;
      final session = _session!.id;
      setState(() {
        _resolving.add(draft.id);
        _error = null;
      });
      try {
        await edit(draft.id);
        final fresh = await widget.repository.open();
        if (mounted && _session?.id == session) {
          setState(() => _drafts = fresh.drafts);
        }
      } catch (error) {
        if (mounted) setState(() => _error = _failure(error));
      } finally {
        if (mounted) setState(() => _resolving.remove(draft.id));
      }
      return;
    }
    if (confirm) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('核对并创建', 'Review and create')),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (draft.payload['title'] is String)
                  Text(
                    draft.payload['title'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                if (draft.payload['due_date'] is String &&
                    (draft.payload['due_date'] as String).isNotEmpty)
                  Text('${t('日期', 'Due')}: ${draft.payload['due_date']}'),
                const SizedBox(height: 16),
                BookstarkMarkdown(
                  data: draft.payload['content'] is String
                      ? draft.payload['content'] as String
                      : '',
                  attachments: widget.attachments,
                  english: widget.english,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('返回', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认创建', 'Confirm create')),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) {
        return;
      }
    }
    final session = _session!.id;
    setState(() {
      _resolving.add(draft.id);
      _error = null;
    });
    try {
      final resolved = await widget.repository.resolve(
        session,
        draft.id,
        confirm: confirm,
      );
      if (mounted && _session?.id == session) {
        setState(
          () => _drafts = [
            for (final old in _drafts) old.id == resolved.id ? resolved : old,
          ],
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted) {
        setState(() => _resolving.remove(draft.id));
      }
    }
  }

  Future<void> _source(Map<String, Object?> source) async {
    try {
      if (widget.onOpenSource != null) {
        await widget.onOpenSource!(source);
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AssistantSourceSheet(
          repository: widget.repository,
          source: source,
          attachments: widget.attachments,
          english: widget.english,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '暂时无法打开这项资料，可能已删除或权限已变化。',
            'Unable to open this source. It may have been deleted or permissions changed.',
          ),
        );
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    try {
      if (_busy) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('停止回答并返回？', 'Stop the reply and leave?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('停止并返回', 'Stop and leave')),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) {
          return;
        }
        if (_input.text.isEmpty && _pendingQuestion != null) {
          _input.text = _pendingQuestion!;
        }
        _stop();
      }
      if (!await _persist() && mounted) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('上下文未保留', 'Context was not retained')),
            content: Text(
              t('仍然返回可能丢失当前上下文。', 'Leaving may lose the current context.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('仍然返回', 'Leave anyway')),
              ),
            ],
          ),
        );
        if (yes != true) {
          return;
        }
      }
      if (mounted) {
        setState(() => _allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    } finally {
      _leaving = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkpointTimer?.cancel();
    _saveTimer?.cancel();
    _deltaTimer?.cancel();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _speakMessage(String markdown) async {
    try {
      await widget.onSpeak?.call(markdown);
    } catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    }
  }

  Widget _message(AssistantMessage message, {bool speakable = true}) => Align(
    alignment: message.role == 'user'
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Card(
        color: message.role == 'user'
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.role == 'assistant')
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('AI 回复', 'AI reply'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: t('复制回答', 'Copy reply'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    if (speakable && widget.onSpeak != null)
                      IconButton(
                        tooltip: t('朗读回答', 'Read reply'),
                        onPressed: () => _speakMessage(message.content),
                        icon: const Icon(Icons.volume_up_outlined),
                      ),
                  ],
                ),
              if (message.role == 'user')
                SelectableText(message.content)
              else
                BookstarkMarkdown(
                  data: message.content,
                  attachments: widget.attachments,
                  english: widget.english,
                ),
              if (message.sources.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(t('参考来源', 'Sources')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in message.sources)
                      ActionChip(
                        label: Text(
                          source['title'] is String
                              ? source['title'] as String
                              : t('来源资料', 'Source'),
                        ),
                        onPressed: () => _source(source),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  Widget _draft(AssistantDraft draft) {
    final kind = draft.payload['kind'];
    final content = draft.payload['content'] is String
        ? draft.payload['content'] as String
        : '';
    final title = kind == 'note' && draft.payload['title'] is String
        ? draft.payload['title'] as String
        : content;
    final usable = ['note', 'task'].contains(kind);
    final enabled =
        usable &&
        !_busy &&
        !_resetting &&
        !_serverBusy &&
        !_resolving.contains(draft.id);
    final status = switch (draft.status) {
      'pending' => t('待确认', 'Pending'),
      'done' => t('已创建', 'Created'),
      'cancelled' => t('已放弃', 'Discarded'),
      'expired' => t('已过期', 'Expired'),
      'unknown' => t('保存结果待核对', 'Save needs review'),
      _ => t('不可用', 'Unavailable'),
    };
    final resource = assistantCreatedResource(draft);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  kind == 'note'
                      ? t('创建笔记', 'Create note')
                      : t('创建待办', 'Create task'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (draft.payload['due_date'] is String &&
                (draft.payload['due_date'] as String).isNotEmpty)
              Text('${t('日期', 'Due')}: ${draft.payload['due_date']}'),
            if (draft.status == 'pending') ...[
              const SizedBox(height: 12),
              Text(
                t(
                  widget.local ? '请在编辑器中核对并明确保存，当前只是草稿' : '仅在你确认后创建，尚未写入知识库',
                  widget.local
                      ? 'Review and explicitly save in the editor. This is only a draft.'
                      : 'Created only after confirmation. Nothing has been written yet.',
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: enabled ? () => _resolve(draft, false) : null,
                    child: Text(t('放弃', 'Discard')),
                  ),
                  FilledButton(
                    onPressed:
                        enabled &&
                            (!widget.local || widget.onEditLocalDraft != null)
                        ? () => _resolve(draft, true)
                        : null,
                    child: Text(
                      _resolving.contains(draft.id)
                          ? t('处理中…', 'Processing…')
                          : widget.local
                          ? t('编辑并保存', 'Edit and save')
                          : t('核对并创建', 'Review and create'),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.local && draft.status == 'unknown')
              FilledButton(
                onPressed: enabled && widget.onEditLocalDraft != null
                    ? () => _resolve(draft, true)
                    : null,
                child: Text(t('核对保存结果', 'Review save result')),
              ),
            if (widget.local &&
                widget.onForgetLocalDraft != null &&
                {'done', 'cancelled'}.contains(draft.status))
              TextButton(
                onPressed: enabled && _resolving.isEmpty
                    ? () => _forgetLocalDraft(draft)
                    : null,
                child: Text(
                  _resolving.contains(draft.id)
                      ? t('移除中…', 'Removing…')
                      : t('移除此记录', 'Remove this record'),
                ),
              ),
            if (resource != null)
              OutlinedButton(
                onPressed: () => _source(resource),
                child: Text(t('打开已创建资源', 'Open created resource')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _transcript() => ListView(
    controller: _scroll,
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        widget.local
            ? t('本地空间 · 最近19轮上下文', 'Local space · Up to 19 recent turns')
            : t(
                '连接到你的知识库 · 仅携带最近19轮上下文',
                'Connected to your knowledge · Up to 19 recent turns of context',
              ),
      ),
      if (widget.local && widget.modelLabel != null)
        Text('${t('模型', 'Model')}: ${widget.modelLabel}'),
      if (widget.local)
        Text(
          widget.knowledgeGranted
              ? t('本地知识检索：已授权', 'Local knowledge search: Allowed')
              : t('本地知识检索：关闭', 'Local knowledge search: Off'),
        ),
      if (boundedAssistantHistory(_messages).length != _messages.length)
        Text(
          t(
            '较长消息保留为阅读记录，不加入模型上下文',
            'Long messages remain readable but are omitted from model context.',
          ),
        ),
      if (_serverBusy)
        Card(
          child: ListTile(
            title: Text(
              t('会话正在处理，请稍后刷新', 'Conversation is busy. Refresh shortly.'),
            ),
            trailing: IconButton(
              tooltip: t('刷新', 'Refresh'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(_error!),
                if (!_ready)
                  FilledButton(onPressed: _load, child: Text(t('重试', 'Retry'))),
                if (_contextReadFailed && widget.vault != null)
                  TextButton(
                    onPressed: _clearLocalContext,
                    child: Text(t('清空本地上下文', 'Clear local context')),
                  ),
              ],
            ),
          ),
        ),
      if (_storageError != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('${t('上下文未保留', 'Context not retained')}: $_storageError'),
                TextButton(
                  onPressed: _persist,
                  child: Text(t('重试保留', 'Retry retaining context')),
                ),
              ],
            ),
          ),
        ),
      if (_ready && _messages.isEmpty && _pendingQuestion == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              const Icon(Icons.auto_awesome, size: 48),
              const SizedBox(height: 16),
              Text(
                t('从一个问题开始', 'Start with a question'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in [
                    t('总结最近的阅读笔记', 'Summarize recent reading notes'),
                    t('整理今天的待办', 'Organize today’s tasks'),
                  ])
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: () => _input.text = suggestion,
                    ),
                ],
              ),
            ],
          ),
        ),
      for (final message in _messages) _message(message),
      if (_pendingQuestion != null) ...[
        _message(AssistantMessage(role: 'user', content: _pendingQuestion!)),
        if (_partial.isNotEmpty)
          _message(
            AssistantMessage(role: 'assistant', content: _partial),
            speakable: false,
          ),
        if (_busy)
          Text(
            _stopping
                ? t('正在停止…', 'Stopping…')
                : _progress.isEmpty
                ? t('正在回答…', 'Replying…')
                : _progress,
          ),
        if (_stopped && !_busy)
          Text(
            t(
              '已停止 · 此回答未作为完成上下文发送',
              'Stopped · This partial reply is not used as completed context',
            ),
          ),
      ],
      for (final draft in _drafts) _draft(draft),
    ],
  );
  Widget _composer(double maxHeight, {bool footer = true}) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: TextField(
                    key: const Key('assistant-input'),
                    controller: _input,
                    enabled: _ready && !_resetting,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: t('继续提问…', 'Continue asking…'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: _busy ? t('停止回答', 'Stop reply') : t('发送', 'Send'),
                onPressed: _busy
                    ? (_stopping ? null : _stop)
                    : (_ready &&
                              !_serverBusy &&
                              !_resetting &&
                              _resolving.isEmpty &&
                              !_confirmingReplacement &&
                              _input.text.trim().isNotEmpty
                          ? _send
                          : null),
                icon: Icon(_busy ? Icons.stop : Icons.send),
              ),
            ],
          ),
          if (footer)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t(
                  'AI 可能出错，请核对重要内容',
                  'AI may make mistakes. Check important information.',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _allowLeave || (!_busy && _input.text.isEmpty && _storageError == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        _leave();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _leave,
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          widget.local
              ? t('本地 AI 助手', 'Local AI assistant')
              : t('AI 助手', 'AI assistant'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            enabled: _ready && !_busy && !_resetting && _resolving.isEmpty,
            onSelected: (value) {
              if (value == 'reset') {
                _reset();
              } else {
                _load();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'reset',
                child: Text(t('新建会话', 'New conversation')),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text(t('刷新草稿状态', 'Refresh draft status')),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final height = math.min(
                  160.0,
                  math.max(56.0, constraints.maxHeight * 0.38),
                );
                if (constraints.maxHeight < 100) {
                  return SingleChildScrollView(
                    child: _composer(56, footer: false),
                  );
                }
                return Column(
                  children: [
                    Expanded(child: _transcript()),
                    _composer(height, footer: constraints.maxHeight >= 120),
                  ],
                );
              },
            ),
    ),
  );
}
