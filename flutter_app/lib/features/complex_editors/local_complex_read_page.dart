import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/local_store.dart';
import 'complex_editor_browser.dart';

class LocalComplexReadPage extends StatefulWidget {
  const LocalComplexReadPage({
    super.key,
    required this.store,
    required this.id,
    required this.collection,
    required this.kind,
    this.english = false,
  });
  final LocalStore store;
  final int id;
  final String collection;
  final ComplexEditorKind kind;
  final bool english;
  @override
  State<LocalComplexReadPage> createState() => _LocalComplexReadPageState();
}

class _LocalComplexReadPageState extends State<LocalComplexReadPage> {
  late final LocalComplexNotesRepository _repository =
      LocalComplexNotesRepository(
        widget.store,
        kind: widget.kind,
        collection: widget.collection,
      );
  ComplexEditorDocument? _document;
  String? _title;
  bool _failed = false;
  int _epoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  String get _kindName => switch (widget.kind) {
    ComplexEditorKind.markdown => t('Markdown', 'Markdown'),
    ComplexEditorKind.html => t('HTML', 'HTML'),
    ComplexEditorKind.spreadsheet => t('表格', 'Spreadsheet'),
    ComplexEditorKind.drawing => t('画板', 'Drawing'),
    ComplexEditorKind.mindmap => t('思维导图', 'Mind map'),
    ComplexEditorKind.richdoc => t('富文档', 'Rich document'),
    ComplexEditorKind.presentation => t('演示文稿', 'Presentation'),
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _epoch++;
    _repository.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _document = null;
      _title = null;
      _failed = false;
    });
    try {
      final note = await _repository.read(widget.id);
      if (!mounted || epoch != _epoch) return;
      if (note.id != widget.id ||
          note.collection != widget.collection ||
          note.document.kind != widget.kind) {
        throw const FormatException('Document identity changed');
      }
      setState(() {
        _document = note.document;
        _title = note.title;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title ?? _kindName),
      actions: [
        IconButton(
          tooltip: t('刷新', 'Refresh'),
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    '无法读取文档，原始内容已保留。',
                    'Unable to read document. Original content preserved.',
                  ),
                ),
                TextButton(onPressed: _load, child: Text(t('重试', 'Retry'))),
              ],
            ),
          )
        : _document == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  t(
                    '本地空间 · $_kindName · 只读',
                    'Local space · $_kindName · Read only',
                  ),
                ),
              ),
              Expanded(
                child: ComplexEditorBrowser(
                  document: _document!,
                  title: _title!,
                  english: widget.english,
                ),
              ),
            ],
          ),
  );
}
