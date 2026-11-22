import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_complex_notes_repository.dart';

class ArticleMetadata {
  ArticleMetadata(this.title, List<String> labels)
    : labels = List.unmodifiable(labels);
  final String title;
  final List<String> labels;
}

/// Owns controllers until the dialog route's closing animation disposes it.
class ArticleMetadataDialog extends StatefulWidget {
  const ArticleMetadataDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.document,
    this.english = false,
    this.noteMetadata = false,
  });
  final String title;
  final List<String> labels;
  final ComplexEditorDocument document;
  final bool english;
  final bool noteMetadata;
  @override
  State<ArticleMetadataDialog> createState() => _ArticleMetadataDialogState();
}

class _ArticleMetadataDialogState extends State<ArticleMetadataDialog> {
  late final _title = TextEditingController(text: widget.title);
  final _label = TextEditingController();
  late final _labels = List<String>.of(widget.labels);
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _title.dispose();
    _label.dispose();
    super.dispose();
  }

  void _add() {
    final value = _label.text.trim();
    if (value.isEmpty) return;
    try {
      ComplexNoteEdit(
        title: 'Article',
        document: widget.document,
        labels: [..._labels, value],
      ).validate();
      setState(() {
        _labels.add(value);
        _label.clear();
        _error = null;
      });
    } catch (_) {
      setState(
        () => _error = t(
          '标签重复、过长或数量过多，请调整后重试。',
          'Labels must be unique and within the size and count limits.',
        ),
      );
    }
  }

  void _apply() {
    final title = _title.text;
    try {
      ComplexNoteEdit(
        title: title,
        document: widget.document,
        labels: _labels,
      ).validate();
      if (_label.text.trim().isNotEmpty) {
        setState(
          () => _error = t(
            '请先添加新标签，或清空输入。',
            'Add the new label or clear its field first.',
          ),
        );
        return;
      }
      Navigator.pop(context, ArticleMetadata(title, _labels));
    } catch (_) {
      setState(
        () => _error = t(
          '请填写有效标题，并缩短过长的标题或标签。',
          'Enter a valid title and shorten oversized title or labels.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    scrollable: true,
    title: Text(
      widget.noteMetadata
          ? t('笔记信息', 'Note information')
          : t('文章信息', 'Article information'),
    ),
    content: SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: widget.noteMetadata
                  ? t('笔记标题', 'Note title')
                  : t('文章标题', 'Article title'),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          Text(t('标签', 'Labels')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < _labels.length; i++)
                InputChip(
                  label: Text(_labels[i]),
                  backgroundColor: const Color(0xfff1e8fc),
                  side: BorderSide.none,
                  labelStyle: const TextStyle(color: Color(0xff6530ad)),
                  deleteIconColor: const Color(0xff6530ad),
                  onDeleted: () => setState(() => _labels.removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  decoration: InputDecoration(labelText: t('新标签', 'New label')),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xfff1e8fc),
                  foregroundColor: const Color(0xff6530ad),
                  minimumSize: const Size(64, 48),
                ),
                onPressed: _add,
                child: Text(t('添加', 'Add')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(t('应用后仍需保存。', 'Save the article after applying.')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(onPressed: _apply, child: Text(t('应用', 'Apply'))),
    ],
  );
}
