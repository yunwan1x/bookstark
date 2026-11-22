import 'package:flutter/material.dart';

import 'source_chunks.dart';
import 'source_text_view.dart';

/// Read-only view of the complete Markdown source. It receives data only and
/// has no repository, save, recovery-vault, attachment, or network capability.
class LargeMarkdownReadPage extends StatefulWidget {
  const LargeMarkdownReadPage({
    super.key,
    required this.title,
    required this.labels,
    required this.source,
    this.english = false,
  });

  final String title;
  final List<String> labels;
  final String source;
  final bool english;

  @override
  State<LargeMarkdownReadPage> createState() => _LargeMarkdownReadPageState();
}

class _LargeMarkdownReadPageState extends State<LargeMarkdownReadPage> {
  late int _bytes = SourceChunks.utf8ByteLength(widget.source);
  bool get english => widget.english;
  String get source => widget.source;
  String get title => widget.title;
  List<String> get labels => widget.labels;

  @override
  void didUpdateWidget(covariant LargeMarkdownReadPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _bytes = SourceChunks.utf8ByteLength(widget.source);
    }
  }

  String get _title => english ? 'Original note' : '笔记原文';
  String get _readonly => english ? 'Read only' : '只读';
  String get _complete => english ? 'Full source preserved' : '全文完整保留';
  String get _message => english
      ? 'This content exceeds the editing limit and is shown read-only.'
      : '内容超过编辑上限，已切换为只读原文。';

  @override
  Widget build(BuildContext context) {
    final megabytes = _bytes / (1024 * 1024);
    final sizeText = '${megabytes.toStringAsFixed(2)} MB';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff202a36),
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: english ? 'Saving unavailable' : '只读不可保存',
            onPressed: null,
            icon: const Icon(Icons.save_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final metadataMax = bounds.maxHeight * .45;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: metadataMax),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ReadonlyBadge(label: _readonly),
                          Text(
                            '$sizeText · $_complete',
                            style: const TextStyle(color: Color(0xff586675)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xff202a36),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (labels.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: labels
                              .map((label) => Chip(label: Text(label)))
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xffedf5ff),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _message,
                          style: const TextStyle(color: Color(0xff315e8e)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SourceTextView(
                  source: source,
                  decorated: true,
                  english: english,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReadonlyBadge extends StatelessWidget {
  const _ReadonlyBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xffeef5ff),
      border: Border.all(color: const Color(0xff2474dd)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xff1768ca),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
