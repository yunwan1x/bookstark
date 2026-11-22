import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import 'html_preview.dart';
import 'html_code_source_surface.dart';

/// An immutable, inert snapshot with an isolated source WebView; no repository or mutation.
class HtmlVersionViewPage extends StatefulWidget {
  const HtmlVersionViewPage({
    super.key,
    required this.heading,
    required this.title,
    required this.source,
    required this.labels,
    this.english = false,
    this.sourceSurfaceBuilder,
  });
  final String heading, title, source;
  final List<String> labels;
  final bool english;
  final HtmlCodeSourceSurfaceBuilder? sourceSurfaceBuilder;
  @override
  State<HtmlVersionViewPage> createState() => _HtmlVersionViewPageState();
}

class _HtmlVersionViewPageState extends State<HtmlVersionViewPage> {
  bool _source = false;
  int _sourceEpoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff1f5ff),
    appBar: AppBar(title: Text(widget.heading)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Chip(label: Text(t('只读', 'Read only'))),
          ),
          Text(t('标签', 'Labels')),
          if (widget.labels.isEmpty) Text(t('无标签', 'No labels')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final label in widget.labels) Chip(label: Text(label)),
            ],
          ),
          const SizedBox(height: 16),
          Text(t('核对期间预览不运行脚本。', 'Scripts do not run during review.')),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(t('预览', 'Preview'))),
              ButtonSegment(value: true, label: Text(t('源码', 'Source'))),
            ],
            selected: {_source},
            onSelectionChanged: (selection) =>
                setState(() => _source = selection.single),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 520,
            child: _source
                ? HtmlCodeSourceSurface(
                    key: ValueKey(_sourceEpoch),
                    document: ComplexEditorDocument.parse(
                      ComplexEditorKind.html,
                      widget.source,
                    ),
                    title: widget.title,
                    english: widget.english,
                    onReady: (_) async {},
                    onState: (_) {},
                    beforeRetire: (_) async {},
                    onReloadRequested: () => setState(() => _sourceEpoch++),
                    builder: widget.sourceSurfaceBuilder,
                  )
                : NativeHtmlPreview(
                    source: widget.source,
                    english: widget.english,
                  ),
          ),
        ],
      ),
    ),
  );
}
