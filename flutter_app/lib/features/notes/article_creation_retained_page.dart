import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'article_creation_retained_record.dart';

/// An opaque retained record never becomes a fresh attempt or an editable DTO.
/// All old keys remain untouched; this screen has no write/delete/POST callbacks.
class ArticleCreationRetainedPage extends StatefulWidget {
  const ArticleCreationRetainedPage({
    super.key,
    required this.record,
    required this.isCurrent,
    required this.sourceIoScope,
    this.english = false,
  });
  final ArticleCreationRetainedRecord record;
  final bool Function() isCurrent;
  final ComplexSourceIoScope? sourceIoScope;
  final bool english;
  @override
  State<ArticleCreationRetainedPage> createState() => _RetainedState();
}

class _RetainedState extends State<ArticleCreationRetainedPage> {
  late final ArticleCreationRetainedRecord _record;
  late final ComplexSourceIoScope? _initialOwner;
  OwnedPreviewController _preview = OwnedPreviewController();
  ComplexEditorTransport? _transport;
  NativeComplexSourceIo? _job;
  bool _busy = false;
  int _generation = 0;
  String? _message;
  bool get current =>
      mounted &&
      identical(widget.record, _record) &&
      identical(widget.sourceIoScope, _initialOwner) &&
      widget.isCurrent();
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _initialOwner = widget.sourceIoScope;
  }

  @override
  void didUpdateWidget(covariant ArticleCreationRetainedPage old) {
    super.didUpdateWidget(old);
    if (!identical(widget.record, _record) ||
        !identical(widget.sourceIoScope, _initialOwner)) {
      _job?.retire();
      _transport = null;
      unawaited(_preview.retire().catchError((Object _) {}));
    }
  }

  Future<void> _export() async {
    final owner = widget.sourceIoScope, transport = _transport;
    if (!current || _busy || owner == null || transport == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      owner.guard();
      await widget.record.verifyFresh();
      if (!current || !identical(transport, _transport)) {
        throw StateError('Review retired');
      }
      final grant = await transport.reviewExportIdentity();
      final source = widget.record.export;
      if (grant['sha256'] != source.digest ||
          grant['bytes'] != source.bytes.length) {
        throw StateError('Retained export binding changed');
      }
      owner.guard();
      final job = NativeComplexSourceIo(
        owner: owner,
        lease: grant['lease']! as String,
        generation: grant['generation']! as int,
      );
      _job = job;
      final saved = await job.exportOwnedReview(
        source,
        beforeWrite: widget.record.verifyFresh,
      );
      if (current) {
        _message = saved
            ? t(
                '完整恢复记录已导出，原记录仍保留。',
                'Complete recovery record exported. The original is retained.',
              )
            : t('导出已取消，原记录仍保留。', 'Export cancelled. The original is retained.');
      }
    } catch (_) {
      if (current) {
        _message = t(
          '导出未确认，目标可能包含部分内容。原记录保持不变。',
          'Export is unconfirmed; destination may contain partial content. The original record is unchanged.',
        );
      }
    } finally {
      _job?.retire();
      _job = null;
      try {
        await _preview.retire();
        if (current) {
          final old = _preview;
          _preview = OwnedPreviewController();
          old.dispose();
          _transport = null;
          _generation++;
        }
      } catch (_) {
        if (current) {
          _message = t(
            '旧预览关闭尚未确认，原记录仍保留。',
            'Preview closure is not confirmed. The original is retained.',
          );
        }
      }
      if (current) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!current || _busy) return;
    setState(() => _busy = true);
    try {
      await _preview.retire();
      if (mounted && current) Navigator.pop(context);
    } catch (_) {
      if (current) {
        setState(() {
          _busy = false;
          _message = t(
            '旧预览关闭尚未确认，原记录仍保留。',
            'Preview closure is not confirmed. The original is retained.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(widget.record, _record) ||
        !identical(widget.sourceIoScope, _initialOwner)) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              t(
                '恢复空间已变更，请重新打开。',
                'Recovery scope changed. Reopen this record.',
              ),
            ),
          ),
        ),
      );
    }
    final record = widget.record;
    final generation = _generation, preview = _preview;
    // This notice is explicitly not a partial representation of the old source.
    final displayed = record.renderable
        ? record.source
        : t(
            '此恢复记录超过20 MiB，无法在此页完整显示。请使用“导出完整恢复记录”保留全部原始字节。没有创建或修改文章。',
            'This recovery record exceeds 20 MiB and cannot be displayed completely here. Export the complete recovery record to preserve every original byte. No article was created or changed.',
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('保留的文章恢复记录', 'Retained article recovery record')),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            t(
                              '原恢复记录已保留。其内容不符合当前编辑约束，已阻止再次创建。导出保留完整原始记录，不会删除或修复原记录。',
                              'The original recovery record is retained. It does not meet current editing constraints, so new creation is blocked. Export preserves the complete original record without deleting or repairing it.',
                            ),
                          ),
                        ),
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_message!),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ComplexEditorBrowser(
                    key: ValueKey(_generation),
                    document: ComplexEditorDocument.parse(
                      ComplexEditorKind.markdown,
                      displayed,
                    ),
                    title: t('原始恢复记录', 'Original recovery record'),
                    readOnly: true,
                    english: widget.english,
                    retirementController: _preview,
                    ownedReviewExport: widget.sourceIoScope != null,
                    ownedReviewExportDigest: widget.sourceIoScope == null
                        ? null
                        : record.export.digest,
                    ownedReviewExportBytes: widget.sourceIoScope == null
                        ? null
                        : record.export.bytes.length,
                    onExternalLink: (_) async {},
                    onReady: (transport) async {
                      if (current &&
                          generation == _generation &&
                          identical(preview, _preview) &&
                          !preview.retired) {
                        setState(() => _transport = transport);
                      }
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .3,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed:
                                _busy ||
                                    _transport == null ||
                                    widget.sourceIoScope == null
                                ? null
                                : _export,
                            child: Text(
                              t('导出完整恢复记录', 'Export complete recovery record'),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _leave,
                            child: Text(t('保留并返回', 'Keep and return')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _job?.retire();
    unawaited(_preview.retire().catchError((Object _) {}));
    _preview.dispose();
    super.dispose();
  }
}
