import 'package:flutter/material.dart';
import '../../core/notes_repository.dart';
import '../../core/owned15_native_notes_repository.dart';
import '../../widgets/bookstark_markdown.dart';

/// Mounted below Owned15MemoryEditorGuard. A failed unknown save replaces and
/// disposes the editor subtree. No NoteSaveFailure/acknowledged callback is used.
class Owned15NativeMemoryEditor extends StatefulWidget {
  const Owned15NativeMemoryEditor({
    super.key,
    required this.repository,
    required this.editorBuilder,
    required this.isCurrent,
    required this.onReviewed,
    this.english = false,
  });
  final Owned15NativeNotesRepository repository;
  final Widget Function(BuildContext) editorBuilder;
  final bool Function() isCurrent;
  final Future<void> Function() onReviewed;
  final bool english;
  @override
  State<Owned15NativeMemoryEditor> createState() =>
      _Owned15NativeMemoryEditorState();
}

class _Owned15NativeMemoryEditorState extends State<Owned15NativeMemoryEditor> {
  Note? _actual;
  bool _busy = false;
  String? _error;
  int _epoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    widget.repository.reviewRequired.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant Owned15NativeMemoryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      oldWidget.repository.reviewRequired.removeListener(_changed);
      widget.repository.reviewRequired.addListener(_changed);
      _epoch++;
      _actual = null;
      _error = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    widget.repository.reviewRequired.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _actual = null;
        _error = null;
      });
    }
  }

  Future<void> _read() async {
    if (!current || _busy) return;
    final epoch = _epoch;
    final repository = widget.repository;
    bool owned() =>
        current && epoch == _epoch && identical(repository, widget.repository);
    setState(() {
      _busy = true;
      _actual = null;
      _error = null;
    });
    try {
      final actual = await repository.read(repository.resourceId);
      if (!owned()) return;
      setState(() => _actual = actual);
    } catch (_) {
      if (owned()) {
        setState(
          () => _error = t(
            '无法读取当前资料。记录已保留。',
            'Current content could not be read. The record is retained.',
          ),
        );
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final actual = _actual;
    if (actual == null || !current || _busy) return;
    final epoch = _epoch;
    final repository = widget.repository;
    final onReviewed = widget.onReviewed;
    bool owned() =>
        current && epoch == _epoch && identical(repository, widget.repository);
    setState(() => _busy = true);
    try {
      // endWarmReview performs another full-tuple read and exact fingerprint CAS.
      // It removes only the reviewed journal, never writes content.
      await repository.endWarmReview(actual);
      if (!owned()) return;
      await onReviewed();
    } catch (_) {
      if (owned()) {
        setState(() {
          _actual = null;
          _error = t(
            '内容或记录已变化，请重新读取核对。记录仍保留。',
            'Content or record changed. Read again. The record is retained.',
          );
        });
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.reviewRequired.value) {
      return widget.editorBuilder(context);
    }
    final actual = _actual;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('核对当前本机资料', 'Review current local content')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  '上次保存结果未知，已停止编辑和再次提交。',
                  'The previous save result is unknown. Editing and resubmission have stopped.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '下方仅显示重新读取的当前本机正文，不能证明上次请求成功。未保存正文不写入磁盘，关闭或后台锁定后不会保留。',
                  'Only freshly read current local content is shown below. This does not prove the previous request succeeded. Unsaved content is not written to disk and is lost when closed or locked in the background.',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!),
                ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _read,
                child: Text(t('重新读取核对', 'Read current content')),
              ),
              if (actual != null) ...[
                SelectableText(
                  actual.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (actual.labels.isNotEmpty) Text(actual.labels.join(', ')),
                BookstarkMarkdown(
                  data: actual.content,
                  english: widget.english,
                  onLink: (_, _) async {},
                  imageBuilder: (_, _, alt) =>
                      Text(alt ?? t('图片引用（只读）', 'Image reference (read-only)')),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _finish,
                  child: Text(
                    t('确认已核对并移除记录', 'Confirm review and remove record'),
                  ),
                ),
              ],
              Text(
                t(
                  '返回会保留待核对记录，不会再次保存。',
                  'Going back retains the review record and does not save again.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
