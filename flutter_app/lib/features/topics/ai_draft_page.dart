import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/completion_repository.dart';
import '../../widgets/bookstark_markdown.dart';

class CompletionDraft {
  const CompletionDraft(this.markdown, {required this.complete});
  final String markdown;
  final bool complete;
}

class AIDraftPage extends StatefulWidget {
  const AIDraftPage({
    super.key,
    required this.repository,
    required this.title,
    required this.initialContext,
    required this.initialInstruction,
    this.scene = CompletionScene.topicSummary,
    this.attachments,
    this.english = false,
  });
  final CompletionRepository repository;
  final String title, initialContext, initialInstruction;
  final CompletionScene scene;
  final AttachmentRepository? attachments;
  final bool english;
  @override
  State<AIDraftPage> createState() => _AIDraftPageState();
}

class _AIDraftPageState extends State<AIDraftPage> {
  late final _context = TextEditingController(text: widget.initialContext);
  late final _instruction = TextEditingController(
    text: widget.initialInstruction,
  );
  StreamSubscription<String>? _subscription;
  Completer<void>? _abort;
  String _answer = '';
  String? _error;
  bool _busy = false,
      _complete = false,
      _stopped = false,
      _expanded = false,
      _allowLeave = false;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(text),
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
  Future<void> _cancel({bool stopped = true}) async {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _abort = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _complete = false;
        _stopped = stopped;
      });
    }
    await subscription?.cancel();
  }

  Future<void> _generate() async {
    if (_busy) return;
    if (_answer.isNotEmpty &&
        (!await _confirm(
              t('重新生成', 'Regenerate'),
              t('将替换当前草稿，继续吗？', 'Replace the current draft?'),
            ) ||
            !mounted)) {
      return;
    }
    await _cancel(stopped: false);
    if (!mounted) return;
    final generation = ++_generation;
    final abort = _abort = Completer<void>();
    setState(() {
      _answer = '';
      _error = null;
      _busy = true;
      _complete = false;
      _stopped = false;
    });
    _subscription = widget.repository
        .complete(
          context: _context.text,
          instruction: _instruction.text,
          scene: widget.scene,
          abortTrigger: abort.future,
        )
        .listen(
          (text) {
            if (mounted && generation == _generation) {
              setState(() => _answer += text);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (mounted && generation == _generation) {
              setState(() {
                _busy = false;
                _complete = false;
                _error = error.toString();
                _subscription = null;
              });
            }
          },
          onDone: () {
            if (mounted && generation == _generation) {
              setState(() {
                _busy = false;
                _complete = _answer.trim().isNotEmpty;
                _subscription = null;
                if (!_complete) _error = t('AI返回空正文', 'AI returned no content');
              });
            }
          },
          cancelOnError: true,
        );
  }

  Future<void> _leave() async {
    final dirty =
        _answer.isNotEmpty ||
        _context.text != widget.initialContext ||
        _instruction.text != widget.initialInstruction;
    if ((_busy || dirty) &&
        (!await _confirm(
              t('放弃草稿并返回？', 'Discard draft and leave?'),
              t('尚未使用的内容不会保存。', 'Unused content will not be saved.'),
            ) ||
            !mounted)) {
      return;
    }
    await _cancel();
    if (!mounted) return;
    _allowLeave = true;
    Navigator.pop(context);
  }

  void _use() {
    if (_busy || _answer.trim().isEmpty) return;
    _allowLeave = true;
    Navigator.pop(context, CompletionDraft(_answer, complete: _complete));
  }

  @override
  void dispose() {
    _generation++;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    _context.dispose();
    _instruction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<CompletionDraft>(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(t('AI草拟', 'AI draft')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _context,
              enabled: !_busy,
              minLines: _expanded ? 8 : 3,
              maxLines: _expanded ? null : 6,
              decoration: InputDecoration(
                labelText: t('上下文', 'Context'),
                helperText: t(
                  '最多20000字；发送前可修改',
                  'Up to 20000 characters; review before sending',
                ),
                suffixIcon: IconButton(
                  tooltip: _expanded
                      ? t('收起上下文', 'Collapse context')
                      : t('展开上下文', 'Expand context'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _instruction,
              enabled: !_busy,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: t('生成要求', 'Instructions'),
                helperText: t('1—2000字', '1–2000 characters'),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_busy)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop),
                    label: Text(t('停止生成', 'Stop generating')),
                  )
                else
                  OutlinedButton(
                    onPressed: _generate,
                    child: Text(
                      _answer.isEmpty
                          ? t('开始生成', 'Generate')
                          : t('重新生成', 'Regenerate'),
                    ),
                  ),
                Text(
                  _busy
                      ? t('生成中', 'Generating')
                      : _complete
                      ? t('生成完成', 'Completed')
                      : _stopped
                      ? t('已停止，内容尚不完整', 'Stopped; content is incomplete')
                      : _error != null
                      ? t('生成未完成', 'Incomplete')
                      : t('尚未生成', 'Not generated'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            if (_answer.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('草稿预览', 'Draft preview'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      BookstarkMarkdown(
                        data: _answer,
                        attachments: widget.attachments,
                        english: widget.english,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              t(
                '仅生成草稿，使用后仍需手动保存。',
                'This only generates a draft. Save it explicitly after review.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: !_busy && _answer.trim().isNotEmpty ? _use : null,
              child: Text(
                _complete
                    ? t('使用草稿', 'Use draft')
                    : t('编辑当前草稿', 'Edit current draft'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
