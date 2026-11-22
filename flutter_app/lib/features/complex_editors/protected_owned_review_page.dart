import '../../widgets/bookstark_markdown.dart';
import '../../core/complex_editor_document.dart';
import 'package:flutter/material.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/protected_complex_lifetime.dart';
import 'complex_editor_browser.dart';

/// Only the current server source is visible. An unknown request's edited
/// plaintext was intentionally never persisted, so equality cannot prove commit.
class ProtectedOwnedReviewPage extends StatefulWidget {
  const ProtectedOwnedReviewPage({
    super.key,
    required this.initial,
    required this.owner,
    required this.readFresh,
    required this.finishReviewed,
    this.english = false,
    this.localSource = false,
  });
  final ComplexNote initial;
  final ProtectedReviewOwner owner;
  final Future<ComplexNote> Function() readFresh;
  final Future<void> Function(ComplexNote) finishReviewed;
  final bool english;
  final bool localSource;
  @override
  State<ProtectedOwnedReviewPage> createState() => _State();
}

class _State extends State<ProtectedOwnedReviewPage> {
  late ComplexNote _actual = widget.initial;
  bool _busy = false, _allowPop = false;
  int _version = 0;
  String? _notice;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && widget.owner.current;
  Future<void> _review({required bool finish}) async {
    if (_busy || !current) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final fresh = await widget.readFresh();
      if (!current) return;
      if (!fresh.same(_actual)) {
        await widget.owner.nextPreview();
        if (!current) return;
        setState(() {
          _actual = fresh;
          _version++;
          _notice = t(
            widget.localSource
                ? '本机版本已变化，请重新查看；尚未清理记录。'
                : '服务器版本已变化，请重新查看；尚未清理记录。',
            widget.localSource
                ? 'The local version changed. Review it again; the record remains.'
                : 'The server version changed. Review it again; the record remains.',
          );
        });
        return;
      }
      if (!finish) return;
      await widget.finishReviewed(fresh);
      if (!current) return;
      await widget.owner.preview.retire();
      if (!current) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && _allowPop) Navigator.of(context).pop(true);
      });
    } catch (_) {
      if (current) {
        setState(
          () => _notice = t(
            '核对或本机清理未完成。记录仍需处理，不会重新发送保存。',
            'Review or device cleanup is incomplete. Saving will not be resent.',
          ),
        );
      }
    } finally {
      if (current) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy || !current) return;
    setState(() => _busy = true);
    try {
      await widget.owner.preview.retire();
      if (!current) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && _allowPop) Navigator.of(context).pop(false);
      });
    } catch (_) {
      if (current) {
        setState(() {
          _busy = false;
          _notice = t(
            '预览尚未关闭，请重试返回。',
            'Preview has not closed. Retry returning.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(t('核对受保护笔记', 'Review protected note')),
        leading: IconButton(
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back),
          tooltip: t('返回并保留记录', 'Return and retain record'),
        ),
      ),
      body: Column(
        children: [
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(
                      widget.localSource
                          ? '上次编辑正文未保留在硬盘。下方仅为本机当前版本；内容相同不证明上次保存成功。'
                          : '上次编辑正文未保留在硬盘。下方仅为服务器当前版本；内容相同不证明上次保存成功。',
                      widget.localSource
                          ? 'The prior edited body was not retained on disk. Below is only the current local version. Matching content does not prove the prior save succeeded.'
                          : 'The prior edited body was not retained on disk. Below is only the current server version. Matching content does not prove the prior save succeeded.',
                    ),
                  ),
                  if (_notice != null)
                    Semantics(liveRegion: true, child: Text(_notice!)),
                  TextButton(
                    onPressed: _busy ? null : () => _review(finish: false),
                    child: Text(t('重新只读核对', 'Read current version again')),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _review(finish: true),
                    child: Text(
                      t(
                        '已核对当前版本，结束此记录',
                        'Reviewed current version; end this record',
                      ),
                    ),
                  ),
                  Text(
                    t(
                      widget.localSource
                          ? '只清理本机提交标记，不发送正文、不修改本机资料。返回保留记录。'
                          : '只清理本机提交标记，不发送正文、不修改服务器资料。返回保留记录。',
                      widget.localSource
                          ? 'Clears only this device marker. Sends no body and changes no local resource. Returning retains the record.'
                          : 'Clears only this device marker. Sends no body and changes no server resource. Returning retains the record.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child:
                _actual.document.kind == ComplexEditorKind.markdown &&
                    (!widget.localSource || _actual.collection != 'article')
                ? BookstarkMarkdown(
                    data: _actual.document.source,
                    english: widget.english,
                    scrollable: true,
                    onLink: (_, _) async {},
                    imageBuilder: (_, _, alt) =>
                        Text(alt ?? t('图片未加载', 'Image not loaded')),
                  )
                : ComplexEditorBrowser(
                    key: ValueKey(_version),
                    document: _actual.document,
                    title: _actual.title,
                    english: widget.english,
                    readOnly: true,
                    retirementController: widget.owner.preview,
                  ),
          ),
        ],
      ),
    ),
  );
}
