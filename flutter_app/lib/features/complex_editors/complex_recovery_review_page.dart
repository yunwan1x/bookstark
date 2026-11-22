import 'package:flutter/material.dart';
import '../../core/local_complex_notes_repository.dart';
import 'complex_editor_browser.dart';
import 'source_text_view.dart';

enum ComplexRecoveryChoice { keepDraft, useSaved }

/// Returns intent only. The owner must fresh-read and validate the reviewed
/// version before changing its baseline or removing any recovery record.
class ComplexRecoveryReviewPage extends StatefulWidget {
  const ComplexRecoveryReviewPage({
    super.key,
    required this.saved,
    required this.draft,
    this.english = false,
  });
  final ComplexNote saved;
  final ComplexNoteEdit draft;
  final bool english;
  @override
  State<ComplexRecoveryReviewPage> createState() => _ReviewState();
}

class _ReviewState extends State<ComplexRecoveryReviewPage> {
  int _selected = 0;
  bool _raw = false;
  final Set<int> _viewed = {};
  String t(String zh, String en) => widget.english ? en : zh;
  ComplexNoteEdit get _shown => _selected == 0
      ? ComplexNoteEdit(
          title: widget.saved.title,
          document: widget.saved.document,
          labels: widget.saved.labels,
        )
      : widget.draft;
  ButtonStyle get _segmentStyle => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? const Color(0xffe8efff)
          : Colors.white,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? const Color(0xff2563eb)
          : const Color(0xff374151),
    ),
  );
  bool get _reviewed => _viewed.contains(0) && _viewed.contains(1);
  void _select(int value) => setState(() {
    _selected = value;
    _raw = false;
  });
  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final selected = _selected;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(t('核对本机修改', 'Review local changes'))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .45,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('complex-review-metadata'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xfff0f1f4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t(
                                    '上次保存结果待核对',
                                    'Previous save needs verification',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: _segmentStyle,
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(t('当前已保存', 'Currently saved')),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(t('本机草稿', 'Local draft')),
                            ),
                          ],
                          selected: {_selected},
                          onSelectionChanged: (s) => _select(s.single),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          shown.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (shown.labels.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            children: shown.labels
                                .map(
                                  (label) => Chip(
                                    label: Text(label),
                                    backgroundColor: const Color(0xffe8efff),
                                    side: BorderSide.none,
                                    shape: const StadiumBorder(),
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: _segmentStyle,
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text(t('正文', 'Document')),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text(t('原文', 'Source')),
                              ),
                            ],
                            selected: {_raw},
                            onSelectionChanged: (s) => setState(() {
                              _raw = s.single;
                              if (_raw) _viewed.add(_selected);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _raw
                    ? ComplexSourceView(
                        key: ValueKey('source-$_selected'),
                        source: shown.document.source,
                      )
                    : ComplexEditorBrowser(
                        key: ValueKey('review-$_selected'),
                        document: shown.document,
                        title: shown.title,
                        english: widget.english,
                        onReady: (_) async {
                          if (mounted) setState(() => _viewed.add(selected));
                        },
                      ),
              ),
              if (!_reviewed)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    t(
                      '请查看当前已保存和本机草稿后选择。',
                      'View both versions before choosing.',
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reviewed
                            ? () => Navigator.pop(
                                context,
                                ComplexRecoveryChoice.keepDraft,
                              )
                            : null,
                        child: Text(t('保留草稿继续编辑', 'Keep draft and edit')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _reviewed
                            ? () => Navigator.pop(
                                context,
                                ComplexRecoveryChoice.useSaved,
                              )
                            : null,
                        child: Text(t('采用已保存版本', 'Use saved version')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full source, with bounded text layout and UTF-16 surrogate-safe boundaries.
class ComplexSourceView extends StatelessWidget {
  const ComplexSourceView({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context) => SourceTextView(source: source);
}
