import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/owned15_creation_recovery_controller.dart';
import '../../widgets/bookstark_markdown.dart';

/// Warm source is memory only. All articles and other formats require the
/// caller's actual read-only WebView surface, never a native Markdown fallback.
class Owned15CreationReviewPage extends StatefulWidget {
  const Owned15CreationReviewPage({
    super.key,
    required this.controller,
    required this.isCurrent,
    required this.onOpenCurrent,
    required this.onResolved,
    this.warmDocument,
    this.warmTitle,
    this.webViewSnapshotBuilder,
    this.english = false,
  });
  final Owned15CreationRecoveryController controller;
  final bool Function() isCurrent;
  final Future<bool> Function(BuildContext, Owned15CreationReview)
  onOpenCurrent;
  final Future<void> Function() onResolved;
  final ComplexEditorDocument? warmDocument;
  final String? warmTitle;
  final Widget Function(BuildContext, ComplexEditorDocument)?
  webViewSnapshotBuilder;
  final bool english;
  @override
  State<Owned15CreationReviewPage> createState() =>
      _Owned15CreationReviewPageState();
}

class _Owned15CreationReviewPageState extends State<Owned15CreationReviewPage> {
  Owned15CreationReview? _review;
  String? _readFingerprint;
  bool _busy = false, _fullWarm = false;
  String? _error;
  int _epoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current {
    try {
      return mounted && widget.isCurrent() && widget.controller.current;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _inspect();
  }

  @override
  void didUpdateWidget(covariant Owned15CreationReviewPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      _epoch++;
      _review = null;
      _readFingerprint = null;
      _busy = false;
      _error = null;
      _inspect();
    }
  }

  Future<void> _inspect() async {
    if (!current || _busy) return;
    final epoch = _epoch, controller = widget.controller;
    bool owned() =>
        current && epoch == _epoch && identical(controller, widget.controller);
    setState(() {
      _busy = true;
      _readFingerprint = null;
      _error = null;
    });
    try {
      final review = await controller.inspect();
      if (owned()) setState(() => _review = review);
    } catch (_) {
      if (owned()) {
        setState(() {
          _review = null;
          _error = t(
            '无法核对结果，记录已保留；不会再次创建。',
            'Result could not be verified. The record is retained; creation will not be repeated.',
          );
        });
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final reviewed = _review;
    if (!current || _busy || reviewed?.observation == null) return;
    final epoch = _epoch,
        controller = widget.controller,
        open = widget.onOpenCurrent;
    bool owned() =>
        current && epoch == _epoch && identical(controller, widget.controller);
    setState(() => _busy = true);
    try {
      final fresh = await controller.inspect();
      if (!owned()) return;
      if (fresh.fingerprint != reviewed!.fingerprint) {
        setState(() {
          _review = fresh;
          _readFingerprint = null;
          _error = t('资料已变化，请重新核对。', 'Content changed. Review again.');
        });
        return;
      }
      if (!mounted) return;
      final viewed = await open(context, fresh);
      if (owned() && viewed) {
        setState(() => _readFingerprint = fresh.fingerprint);
      }
    } catch (_) {
      if (owned()) {
        setState(
          () => _error = t(
            '无法打开当前资料，记录保留。',
            'Current content could not be opened. The record is retained.',
          ),
        );
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  Future<void> _finish({required bool cancel}) async {
    final review = _review;
    if (!current || _busy || review == null) return;
    final epoch = _epoch,
        controller = widget.controller,
        resolved = widget.onResolved;
    bool owned() =>
        current && epoch == _epoch && identical(controller, widget.controller);
    if (cancel) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('放弃此次新建记录？', 'Abandon this creation record?')),
          content: Text(
            t(
              '将再次核对此操作没有保存回执。只清除此记录，不删除已有资料；内存稿件关闭后丢失。',
              'The operation will be checked again for an absent receipt. Only this record is removed. Existing resources are retained; the memory draft is lost when closed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('返回保留', 'Keep record')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('明确放弃', 'Abandon explicitly')),
            ),
          ],
        ),
      );
      if (yes != true || !owned()) return;
    } else if (_readFingerprint != review.fingerprint) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (cancel) {
        await controller.cancelUnsubmitted(review);
      } else {
        await controller.confirmSaved(review);
      }
      if (owned()) await resolved();
    } catch (_) {
      if (owned()) {
        setState(
          () => _error = t(
            '核对或清理未完成。请保留记录并重新核对；不会再次创建。',
            'Verification or cleanup is incomplete. Keep the record and review again; creation will not be repeated.',
          ),
        );
      }
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  Widget _snapshot(Owned15CreationReview review) {
    final document = widget.warmDocument;
    if (document == null) {
      return Text(
        t(
          '上次正文未保留。当前核对只能读取此回执所指向的现有资料，不能恢复原内存稿件。',
          'The previous draft body was not retained. Review can read only the existing resource identified by its receipt, not recover the previous memory draft.',
        ),
      );
    }
    if (review.marker.collection == 'note' &&
        document.kind == ComplexEditorKind.markdown) {
      var end = !_fullWarm && document.source.length > 16384
          ? 16384
          : document.source.length;
      if (end > 0 &&
          end < document.source.length &&
          document.source.codeUnitAt(end - 1) >= 0xd800 &&
          document.source.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      final preview = document.source.substring(0, end);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookstarkMarkdown(
            data: preview,
            english: widget.english,
            imageBuilder: (uri, title, alt) =>
                Text(alt ?? t('图片未载入', 'Image unavailable')),
            onLink: (text, href) async {},
          ),
          if (end < document.source.length) ...[
            Text(
              t(
                '此处为有界预览，完整原稿仍在本次内存中。',
                'This is a bounded preview; the complete draft remains in memory.',
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _fullWarm = true),
              child: Text(t('查看完整原稿', 'View complete draft')),
            ),
          ],
        ],
      );
    }
    final builder = widget.webViewSnapshotBuilder;
    if (builder == null) {
      return Text(
        t(
          '此格式需要只读 WebView；正文仍在本次内存中，未改用其他格式显示。',
          'This format requires its read-only WebView. Its source remains in memory and is not rendered as another format.',
        ),
      );
    }
    return SizedBox(height: 380, child: builder(context, document));
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: Text(t('核对新建结果', 'Review creation result'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t(
                '不会再次创建。请核对实际回执和当前资料。',
                'Creation will not be repeated. Review the actual receipt and current content.',
              ),
            ),
            if (widget.warmTitle != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.warmTitle!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              ),
            if (review != null) ...[
              Text(
                review.observation == null
                    ? t('未找到此操作的保存回执', 'No save receipt for this operation')
                    : t('回执资料 ID：', 'Receipt resource ID: ') +
                          review.observation!.receipt.id.toString(),
              ),
              const SizedBox(height: 12),
              _snapshot(review),
              const SizedBox(height: 16),
              if (review.observation != null)
                OutlinedButton(
                  onPressed: _busy ? null : _open,
                  child: Text(t('只读打开当前资料', 'Open current content read-only')),
                ),
              if (review.matching)
                FilledButton(
                  onPressed: _busy || _readFingerprint != review.fingerprint
                      ? null
                      : () => _finish(cancel: false),
                  child: Text(
                    t('已核对，仅清理记录', 'Reviewed — clean up record only'),
                  ),
                ),
              if (review.noReceipt)
                TextButton(
                  onPressed: _busy ? null : () => _finish(cancel: true),
                  child: Text(t('明确放弃此次记录', 'Abandon this record explicitly')),
                ),
            ],
            OutlinedButton(
              onPressed: _busy ? null : _inspect,
              child: Text(t('重新核对', 'Check again')),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.maybePop(context),
              child: Text(t('返回，保留记录', 'Back — retain record')),
            ),
            Text(
              t(
                '关闭或进入后台会释放内存稿件。恢复记录不包含正文或密码。',
                'Closing or backgrounding releases the memory draft. Recovery records contain no body or password.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
