import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/local_assistant_retained_draft.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

class LocalAssistantRetainedDraftPage extends StatefulWidget {
  const LocalAssistantRetainedDraftPage({
    super.key,
    required this.inspect,
    required this.clear,
    this.initialSnapshot,
    this.english = false,
  });
  final Future<LocalAssistantRetainedDraftSnapshot?> Function() inspect;
  final Future<void> Function(LocalAssistantRetainedDraftSnapshot) clear;
  final LocalAssistantRetainedDraftSnapshot? initialSnapshot;
  final bool english;
  @override
  State<LocalAssistantRetainedDraftPage> createState() => _RetainedState();
}

class _RetainedState extends State<LocalAssistantRetainedDraftPage> {
  LocalAssistantRetainedDraftSnapshot? _snapshot;
  bool _busy = false, _loaded = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    if (_snapshot == null) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final snapshot = await widget.inspect();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loaded = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _snapshot = null;
        _error = t(
          '暂时无法完整读取草稿，原文已保留，请重试。',
          'The complete draft could not be read. It is retained. Try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final reviewed = _snapshot;
    if (_busy || reviewed == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('清除此草稿？', 'Clear this draft?')),
        content: Text(
          t(
            '只清除这份本机编辑草稿。不会删除已保存资料，也不会重新创建资料。此操作无法撤销。',
            'Only this local editor draft will be cleared. Saved resources are retained and nothing will be created. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('返回并保留', 'Keep draft')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('确认清除此草稿', 'Clear this draft')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.clear(reviewed);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '清理未确认，或草稿状态已变化。请重新核对；未创建或删除任何资料。',
            'Cleanup was not confirmed, or the draft changed. Review again. No resource was created or deleted.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _full(LocalAssistantRetainedDraftSnapshot snapshot) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _FullRetainedText(
          content: snapshot.content,
          english: widget.english,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final note = snapshot?.note, task = snapshot?.task;
    final content = snapshot?.content ?? '';
    final preview = _chunk(content, 0);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: const Color(0xfff4f5f8),
        appBar: AppBar(title: Text(t('保留的助手草稿', 'Retained assistant draft'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t('本地空间', 'Local space'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xffffefc9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xffb77900),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('这次保存已放弃', 'This save attempt was ended'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t(
                              '草稿仍在本机，尚未创建资料。',
                              'The draft remains on this device. No resource was created.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              if (!_busy && _loaded && snapshot == null && _error == null)
                Text(
                  t(
                    '未找到实际编辑草稿，未清除任何内容。',
                    'No editor draft was found. Nothing was cleared.',
                  ),
                ),
              if (snapshot != null)
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Card(
                    semanticContainer: false,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xffd1d5db)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                t('原编辑草稿', 'Original editor draft'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Chip(label: Text(t('只读', 'Read only'))),
                            ],
                          ),
                          const Divider(height: 32),
                          if (note != null) ...[
                            Text(
                              note.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                          ],
                          BookstarkMarkdown(
                            data: preview,
                            english: widget.english,
                          ),
                          if (preview.length < content.length)
                            TextButton(
                              onPressed: _busy ? null : () => _full(snapshot),
                              child: Text(
                                t(
                                  '查看完整草稿（分段只读）',
                                  'View complete draft (read only)',
                                ),
                              ),
                            ),
                          if (note != null && note.labels.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: note.labels
                                  .map(
                                    (label) => Chip(
                                      label: Text(label),
                                      backgroundColor: const Color(0xffdbeafe),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          if (task != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '${t('截止日期', 'Due date')}: ${task.dueDate.isEmpty ? t('未设置', 'Not set') : task.dueDate}',
                            ),
                            Text(
                              task.done
                                  ? t('已完成', 'Completed')
                                  : t('未完成', 'Not completed'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: Text(t('返回并保留', 'Return and keep')),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _busy || snapshot == null ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: Text(t('清除此草稿', 'Clear this draft')),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(t('重新核对', 'Review again')),
              ),
              Text(
                t(
                  '只清除本机草稿，不会删除已保存资料',
                  'Only this local draft is cleared. Saved resources are retained.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _chunkSize = 24000;
String _chunk(String text, int index) {
  var start = index * _chunkSize;
  var end = (start + _chunkSize).clamp(0, text.length);
  if (start > 0 &&
      start < text.length &&
      text.codeUnitAt(start) >= 0xdc00 &&
      text.codeUnitAt(start) <= 0xdfff) {
    start--;
  }
  if (end > start &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return text.substring(start, end);
}

class _FullRetainedText extends StatelessWidget {
  const _FullRetainedText({required this.content, required this.english});
  final String content;
  final bool english;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(english ? 'Complete draft · read only' : '完整草稿 · 只读'),
    ),
    body: SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: (content.length / _chunkSize).ceil(),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((english ? 'Section ' : '分段 ') + (index + 1).toString()),
              BookstarkMarkdown(data: _chunk(content, index), english: english),
            ],
          ),
        ),
      ),
    ),
  );
}
