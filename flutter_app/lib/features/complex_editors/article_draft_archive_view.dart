import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/owned_preview_controller.dart';
import 'complex_editor_browser.dart';

typedef ArticleArchiveBodyBuilder =
    Widget Function(
      BuildContext context, {
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required OwnedPreviewController retirementController,
    });
Widget defaultArticleArchiveBody(
  BuildContext context, {
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required OwnedPreviewController retirementController,
}) => ComplexEditorBrowser(
  document: document,
  title: title,
  english: english,
  readOnly: true,
  retirementController: retirementController,
);

class ArticleDraftArchiveView<T> extends StatefulWidget {
  const ArticleDraftArchiveView({
    super.key,
    required this.title,
    required this.document,
    this.pageTitle,
    this.actionLabel,
    this.confirmTitle,
    this.confirmActionLabel,
    this.bodyBuilder = defaultArticleArchiveBody,
    this.confirmBody,
    this.notice,
    this.unavailableMessage,
    this.prepareRestore,
    this.isCurrentScope,
    this.english = false,
  });
  final String title;
  final ComplexEditorDocument document;
  final String? pageTitle,
      actionLabel,
      confirmTitle,
      confirmActionLabel,
      confirmBody,
      notice,
      unavailableMessage;
  final Future<T> Function()? prepareRestore;
  final ArticleArchiveBodyBuilder bodyBuilder;
  final bool Function()? isCurrentScope;
  final bool english;
  @override
  State<ArticleDraftArchiveView<T>> createState() =>
      _ArticleDraftArchiveViewState<T>();
}

class _ArticleDraftArchiveViewState<T>
    extends State<ArticleDraftArchiveView<T>> {
  final _preview = OwnedPreviewController();
  bool _busy = false, _processing = false, _allowPop = false, _failed = false;
  String? _notice;
  static const purple = Color(0xff6530ad);
  String t(String zh, String en) => widget.english ? en : zh;
  bool current() {
    if (!mounted) return false;
    try {
      return widget.isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _leave({bool restore = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (restore) {
        if (!current() || widget.prepareRestore == null || _failed) {
          throw StateError('Archived article restore unavailable');
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(primary: purple),
            ),
            child: AlertDialog(
              scrollable: true,
              title: Text(
                widget.confirmTitle ??
                    t('恢复到当前文章？', 'Restore to the current article?'),
              ),
              content: Text(
                widget.confirmBody ??
                    t(
                      '已保存文章与旧稿均会保留。恢复后仍需手动保存。',
                      'The saved article and old draft are retained. Restore still requires an explicit save.',
                    ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    widget.confirmActionLabel ?? t('继续恢复', 'Continue restore'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (!mounted || confirmed != true) return;
        if (!current()) throw StateError('Archive scope changed');
      }
      // A route result may open an editable browser or another cookie scope.
      // Wait for this exact readonly lease to close before returning it.
      setState(() => _processing = true);
      await _preview.retire();
      if (!mounted) return;
      T? approval;
      if (restore) {
        if (!current()) throw StateError('Archive scope changed');
        approval = await widget.prepareRestore!();
        if (!mounted) return;
        if (!current()) throw StateError('Archive scope changed');
      }
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop<T>(context, approval);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = t(
            '旧稿或页面状态已变化，原记录仍保留。请返回草稿列表重新检查。',
            'The old draft or page state changed. Records are retained. Return to the list and check again.',
          );
        });
      }
    } finally {
      if (mounted && !_allowPop) {
        setState(() {
          _busy = false;
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.pageTitle ?? t('旧文章草稿', 'Old article draft')),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (widget.prepareRestore != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: purple),
              onPressed: _busy || _failed ? null : () => _leave(restore: true),
              child: Text(widget.actionLabel ?? t('恢复旧稿', 'Restore old draft')),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final height = math.max(240.0, constraints.maxHeight - 250 * scale);
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfff1e8fc),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          t('已处理 · 只读', 'Handled · Read only'),
                          style: const TextStyle(
                            color: purple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _failed
                        ? Center(
                            child: Text(
                              t(
                                '旧稿已保留，请返回重新检查。',
                                'Old draft retained. Return and check again.',
                              ),
                            ),
                          )
                        : widget.bodyBuilder(
                            context,
                            document: widget.document,
                            title: widget.title,
                            english: widget.english,
                            retirementController: _preview,
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_processing) const LinearProgressIndicator(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Color(0xff64748b),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _notice ??
                                  widget.notice ??
                                  t(
                                    '这是已处理的旧稿，不会自动覆盖文章。',
                                    'This handled old draft never automatically overwrites the article.',
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.prepareRestore == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.unavailableMessage ??
                              t(
                                '当前空间中的原文章不可用于恢复，旧稿仍保留。',
                                'The original article in the current space is unavailable for restore. The old draft is retained.',
                              ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: purple,
                            side: const BorderSide(color: purple),
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _busy ? null : _leave,
                          child: Text(t('返回草稿列表', 'Return to draft list')),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
