import '../../core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';
import '../../core/share_comment_models.dart';
import '../../core/share_comments_repository.dart';
import 'share_comment_compose_page.dart';

class ShareCommentsPage extends StatefulWidget {
  const ShareCommentsPage({
    super.key,
    required this.detail,
    required this.repository,
    this.english = false,
  });
  final PublicShareDetail detail;
  final ShareCommentsRepository repository;
  final bool english;
  @override
  State<ShareCommentsPage> createState() => _ShareCommentsPageState();
}

class _ShareCommentsPageState extends State<ShareCommentsPage> {
  PublicShareCommentPage? _page;
  ShareCommentCapabilities? _capabilities, _pendingCapabilities;
  Completer<void>? _abort;
  late PublicCommentSubmission _submission = PublicCommentSubmission(
    widget.repository,
    widget.detail,
  );
  PublicShareComment? _pendingReply;
  int _generation = 0, _requestedPage = 1;
  bool _loading = true, _deleting = false, _preparing = false, _leaving = false;
  String? _error, _capabilityError;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void didUpdateWidget(covariant ShareCommentsPage old) {
    super.didUpdateWidget(old);
    if (old.detail.reference != widget.detail.reference ||
        old.detail.targetId != widget.detail.targetId ||
        old.repository != widget.repository) {
      _submission = PublicCommentSubmission(widget.repository, widget.detail);
      _pendingReply = null;
      _pendingCapabilities = null;
      _load(1);
    }
  }

  @override
  void dispose() {
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    super.dispose();
  }

  Future<void> _load(int page) async {
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    final abort = _abort = Completer<void>();
    final generation = ++_generation;
    setState(() {
      _requestedPage = page;
      _loading = true;
      _error = null;
      _page = null;
      _capabilities = null;
      _capabilityError = null;
    });
    ShareCommentCapabilities? capability;
    String? capabilityError;
    try {
      capability = await widget.repository.capabilities(
        widget.detail,
        abortTrigger: abort.future,
      );
    } catch (_) {
      capabilityError = t(
        '评论设置暂时无法确认，可阅读已有评论；发布前请重试。',
        'Comment settings could not be confirmed. Existing comments can be read; retry before posting.',
      );
    }
    try {
      final data = await widget.repository.list(
        widget.detail,
        page,
        abortTrigger: abort.future,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = data;
        _capabilities = capability;
        _capabilityError = capabilityError;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = t(
          '无法加载评论，请检查分享和网络后重试。',
          'Unable to load comments. Check the share and connection, then retry.',
        );
      });
    }
  }

  Future<void> _leave() async {
    if (_submission.phase == PublicCommentSubmissionPhase.unknown) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('离开并清除待确认记录？', 'Leave and clear the pending record?')),
          content: Text(
            t(
              '上次评论可能已经发布，请先核对列表。离开只清除本次内存记录，不删除评论。',
              'The comment may already be published. Review the list first. Leaving clears only this in-memory record, not the comment.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续核对', 'Keep reviewing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('离开', 'Leave')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      _submission.reset(acknowledgeUnknown: true);
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Future<void> _compose([PublicShareComment? reply]) async {
    if (_loading || _deleting || _preparing) return;
    setState(() => _preparing = true);
    try {
      final unknown = _submission.phase == PublicCommentSubmissionPhase.unknown;
      ShareCommentCapabilities? capability;
      if (unknown) {
        capability = _pendingCapabilities ?? _capabilities;
      } else {
        try {
          capability = await widget.repository.capabilities(widget.detail);
          if (!mounted) return;
          setState(() {
            _capabilities = capability;
            _capabilityError = null;
          });
        } catch (_) {
          if (mounted) {
            setState(() {
              _capabilities = null;
              _capabilityError = t(
                '评论设置暂时无法确认，请重试。',
                'Comment settings could not be confirmed. Please retry.',
              );
            });
          }
          return;
        }
      }
      final ready = capability;
      if (ready == null) return;
      if (!unknown && !ready.enabled) {
        await _load(_requestedPage);
        return;
      }
      _pendingCapabilities = ready;
      if (_submission.phase == PublicCommentSubmissionPhase.acknowledged) {
        final start = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('上一条评论已发布', 'Previous comment published')),
            content: Text(
              '${t('实际评论编号', 'Actual comment ID')}: ${_submission.receipt!.id}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('返回核对', 'Review comments')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('写另一条评论', 'Write another comment')),
              ),
            ],
          ),
        );
        if (start != true || !mounted) return;
        _submission.reset(acknowledgeUnknown: false);
      }
      if (_submission.phase == PublicCommentSubmissionPhase.editing) {
        _pendingReply = reply;
      }
      final receipt = await Navigator.push<PublicShareComment>(
        context,
        MaterialPageRoute(
          builder: (_) => ShareCommentComposePage(
            contextDetail: widget.detail,
            capabilities: ready,
            submission: _submission,
            reply: _pendingReply,
            english: widget.english,
          ),
        ),
      );
      if (!mounted) return;
      if (receipt != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('评论已发布', 'Comment published'))),
        );
        await _load(1);
      } else {
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _remove(PublicShareComment comment) async {
    if (_deleting || !comment.canDelete || comment.deleted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('删除这条评论？', 'Delete this comment?')),
        content: Text(
          t(
            '只删除所选评论，已有回复依服务端规则保留。',
            'Only the selected comment is deleted. Existing replies follow the server rules.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.remove(widget.detail, comment);
      if (mounted) await _load(_requestedPage);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '删除未确认，请刷新列表核对。',
                'Deletion was not confirmed. Reload comments to verify.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _comment(PublicShareComment value, {bool reply = false}) {
    final author = value.deleted ? t('已删除', 'Deleted') : value.author;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xffe3edff),
                child: Text(author.characters.take(1).toString()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(value.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (value.canDelete)
                IconButton(
                  onPressed: _deleting ? null : () => _remove(value),
                  tooltip: t('删除', 'Delete'),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (value.replyToAuthor.isNotEmpty && reply)
            Text(
              '${t('回复', 'Reply to')} ${value.replyToAuthor}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SelectableText(
            value.deleted ? t('评论已删除', 'Comment deleted') : value.content,
            semanticsLabel: value.deleted
                ? t('评论已删除', 'Comment deleted')
                : value.content,
          ),
          if (!value.deleted && _capabilities?.enabled == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _deleting ? null : () => _compose(value),
                child: Text(t('回复', 'Reply')),
              ),
            ),
          if (value.replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xffe3edff), width: 3),
                ),
              ),
              child: Column(
                children: [
                  for (final item in value.replies)
                    Container(
                      margin: const EdgeInsets.only(left: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xfff4f7fc),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _comment(item, reply: true),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page, cap = _capabilities;
    final unknown = _submission.phase == PublicCommentSubmissionPhase.unknown;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          title: Text(t('分享评论', 'Share comments')),
          leading: BackButton(onPressed: _leave),
          actions: [
            IconButton(
              onPressed: () => _load(_requestedPage),
              tooltip: t('重新加载', 'Reload'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        bottomNavigationBar: cap?.enabled != true || _loading
            ? null
            : SafeArea(
                top: false,
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: _deleting || _preparing
                          ? null
                          : () => _compose(),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        unknown
                            ? t('核对待确认评论', 'Review pending comment')
                            : t('写评论', 'Write comment'),
                      ),
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _load(_requestedPage),
                          child: Text(t('重试', 'Retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.detail.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xffe3edff),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              t(
                                '评论公开可见，包括受密码保护分享下的评论。',
                                'Comments are public, including comments on password-protected shares.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_capabilityError != null) ...[
                            Text(_capabilityError!),
                            TextButton(
                              onPressed: () => _load(_requestedPage),
                              child: Text(
                                t('重试评论设置', 'Retry comment settings'),
                              ),
                            ),
                          ],
                          if (cap?.enabled == false)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                t('评论模块已关闭。', 'Comments are disabled.'),
                              ),
                            ),
                          if (unknown) ...[
                            Text(
                              t(
                                '上次发布结果未知，请先核对。不会自动重发。',
                                'The previous submission is unconfirmed. Review it first; nothing is resent automatically.',
                              ),
                            ),
                            if (cap?.enabled != true)
                              TextButton(
                                onPressed: _preparing ? null : () => _compose(),
                                child: Text(
                                  t('核对待确认评论', 'Review pending comment'),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          if (page != null) ...[
                            if (page.items.isEmpty && cap?.enabled != false)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  t('这一页暂无评论。', 'No comments on this page.'),
                                ),
                              ),
                            for (final item in page.items) ...[
                              Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                color: Colors.white,
                                child: _comment(item),
                              ),
                              const SizedBox(height: 8),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: page.page > 1
                                      ? () => _load(page.page - 1)
                                      : null,
                                  child: Text(t('上一页', 'Previous')),
                                ),
                                Text('${page.page}'),
                                OutlinedButton(
                                  onPressed: page.hasNext
                                      ? () => _load(page.page + 1)
                                      : null,
                                  child: Text(t('下一页', 'Next')),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
