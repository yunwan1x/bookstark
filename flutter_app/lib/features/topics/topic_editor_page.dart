import 'package:flutter/material.dart';
import '../../core/topics_repository.dart';
import '../../core/topic_draft_vault.dart';

class TopicEditorPage extends StatefulWidget {
  const TopicEditorPage({
    super.key,
    required this.repository,
    required this.topic,
    this.vault,
    this.english = false,
  });
  final TopicsRepository repository;
  final TopicItem topic;
  final TopicDraftVault? vault;
  final bool english;
  @override
  State<TopicEditorPage> createState() => _TopicEditorPageState();
}

class _TopicEditorPageState extends State<TopicEditorPage> {
  late final TextEditingController _title, _question;
  late TopicItem _saved;
  late bool _pinned;
  bool _choosing = false;
  bool _ready = false, _busy = false, _allowLeave = false, _wrote = false;
  String? _error;
  late final Set<int?> _draftIds = {widget.topic.id};
  String t(String zh, String en) => widget.english ? en : zh;
  TopicItem get _snapshot => _saved.copyWith(
    title: _title.text,
    question: _question.text,
    isPinned: _pinned,
  );
  bool _same(TopicItem a, TopicItem b) =>
      a.title == b.title &&
      a.question == b.question &&
      a.isPinned == b.isPinned;
  bool get _dirty => !_same(_snapshot, _saved);
  @override
  void initState() {
    super.initState();
    _saved = widget.topic;
    _pinned = _saved.isPinned;
    _title = TextEditingController(text: _saved.title)..addListener(_changed);
    _question = TextEditingController(text: _saved.question)
      ..addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    try {
      final draft = await widget.vault?.read(_saved);
      if (!mounted) return;
      if (draft != null && !_same(draft, _saved)) {
        setState(() => _choosing = true);
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(t('发现主题草稿', 'Topic draft found')),
            content: Text(t('恢复未保存的修改？', 'Restore unsaved changes?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('放弃草稿', 'Discard draft')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('恢复', 'Restore')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        setState(() => _choosing = false);
        if (restore == true) {
          _title.text = draft.title;
          _question.text = draft.question;
          _pinned = draft.isPinned;
        } else {
          await widget.vault?.remove(_saved.id);
        }
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _clearDraft() async {
    try {
      await widget.vault?.remove(_saved.id);
      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    final submitted = _snapshot;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.repository.save(submitted);
      _saved = submitted.copyWith(id: id, memberId: widget.repository.memberId);
      _wrote = true;
      _draftIds.add(id);
      for (final key in _draftIds) {
        await widget.vault?.remove(key);
      }
      if (!mounted) return;
      _allowLeave = true;
      Navigator.pop(context, id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!_ready || !_dirty) {
      _allowLeave = true;
      Navigator.pop(context, _wrote ? _saved.id : null);
      return;
    }
    final keep = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('保留修改？', 'Keep changes?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('放弃修改', 'Discard changes')),
          ),
          if (widget.vault != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('保留草稿', 'Keep draft')),
            ),
        ],
      ),
    );
    if (keep == null) return;
    try {
      if (keep) {
        await widget.vault!.write(_snapshot);
      } else {
        for (final key in _draftIds) {
          await widget.vault?.remove(key);
        }
      }
      if (!mounted) return;
      _allowLeave = true;
      Navigator.pop(context, _wrote ? _saved.id : null);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<int>(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          _saved.id == null ? t('新建主题', 'New topic') : t('编辑主题', 'Edit topic'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _ready && !_busy ? _save : null,
              child: Text(_busy ? t('保存中', 'Saving') : t('保存', 'Save')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !_ready && _error == null && !_choosing
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (!_ready)
                      TextButton(
                        onPressed: _clearDraft,
                        child: Text(t('清除损坏草稿', 'Clear damaged draft')),
                      ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _title,
                    enabled: _ready && !_busy,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: t('主题名称', 'Topic title'),
                      counterText: '${_title.text.trim().runes.length}/200',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _question,
                    enabled: _ready && !_busy,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: t('核心问题', 'Core question'),
                      counterText: '${_question.text.runes.length}/2000',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: SwitchListTile(
                      title: Text(t('置顶主题', 'Pin topic')),
                      subtitle: Text(
                        t('在主题列表中优先显示', 'Show first in the topic list'),
                      ),
                      value: _pinned,
                      onChanged: _ready && !_busy
                          ? (value) => setState(() => _pinned = value)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t(
                      '小结、资料和任务可在保存后继续添加。',
                      'Add summaries, resources and tasks after saving.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
