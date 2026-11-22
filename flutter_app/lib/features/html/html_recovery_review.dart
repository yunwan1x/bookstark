import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/html_notes_repository.dart';
import '../../core/html_recovery_vault.dart';
import 'html_code_source_surface.dart';
import 'html_preview.dart';

/// Protected pending intents deliberately have no local source to restore.
/// Reviewing/adopting current content never resends the previous operation.
class HtmlRecoveryReviewPage extends StatefulWidget {
  const HtmlRecoveryReviewPage({
    super.key,
    required this.note,
    required this.record,
    this.english = false,
    this.sourceSurfaceBuilder,
  });
  final HtmlNote note;
  final HtmlRecoveryRecord record;
  final bool english;
  final HtmlCodeSourceSurfaceBuilder? sourceSurfaceBuilder;
  @override
  State<HtmlRecoveryReviewPage> createState() => _HtmlRecoveryReviewPageState();
}

class _HtmlRecoveryReviewPageState extends State<HtmlRecoveryReviewPage> {
  bool _source = false;
  int _sourceEpoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<void> _adopt() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('采用当前版本？', 'Adopt the current version?')),
        content: Text(
          t(
            '将结束对上次提交的核对，不会重发请求。受保护的旧草稿未保存在本机。',
            'This ends review of the previous submission without resending it. Its protected draft was not stored on this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('继续核对', 'Keep reviewing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('采用当前版本', 'Adopt current version')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff1f5ff),
    appBar: AppBar(title: Text(t('核对服务器版本', 'Review server version'))),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _adopt,
                child: Text(
                  t('采用当前版本开始新编辑', 'Adopt current version and start editing'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(t('不会重发上次提交。', 'The previous submission will not be resent.')),
          ],
        ),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xffffedca),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(height: 8),
                  Text(
                    widget.record.matchesCurrent(widget.note)
                        ? t(
                            '服务器内容已核对，上次回执未收到',
                            'Server content verified; the previous receipt was not received',
                          )
                        : t(
                            '上次保存结果未确认',
                            'The previous save result is unresolved',
                          ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      '请阅读当前保存的版本，确认后开始新的编辑。',
                      'Read the current server version before starting a new edit.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              '🔒 受保护正文未保存到本机。',
              '🔒 Protected content was not saved on this device.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.note.metadata.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Chip(label: Text(t('只读', 'Read only'))),
          ),
          const SizedBox(height: 12),
          Text(t('核对期间预览不运行脚本。', 'Scripts do not run during review.')),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(t('预览', 'Preview'))),
              ButtonSegment(value: true, label: Text(t('源码', 'Source'))),
            ],
            selected: {_source},
            onSelectionChanged: (value) =>
                setState(() => _source = value.single),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 520,
            child: _source
                ? HtmlCodeSourceSurface(
                    key: ValueKey(_sourceEpoch),
                    document: ComplexEditorDocument.parse(
                      ComplexEditorKind.html,
                      widget.note.source,
                    ),
                    title: widget.note.metadata.title,
                    english: widget.english,
                    onReady: (_) async {},
                    onState: (_) {},
                    beforeRetire: (_) async {},
                    onReloadRequested: () => setState(() => _sourceEpoch++),
                    builder: widget.sourceSurfaceBuilder,
                  )
                : NativeHtmlPreview(
                    source: widget.note.source,
                    english: widget.english,
                  ),
          ),
        ],
      ),
    ),
  );
}
