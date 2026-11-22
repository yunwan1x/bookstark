import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';
import '../../core/share_comment_models.dart';
import '../../core/share_comments_repository.dart';

class ShareCommentComposePage extends StatefulWidget {
  const ShareCommentComposePage({
    super.key,
    required this.contextDetail,
    required this.capabilities,
    required this.submission,
    this.reply,
    this.english = false,
  });
  final PublicShareDetail contextDetail;
  final ShareCommentCapabilities capabilities;
  final PublicCommentSubmission submission;
  final PublicShareComment? reply;
  final bool english;
  @override
  State<ShareCommentComposePage> createState() =>
      _ShareCommentComposePageState();
}

class _ShareCommentComposePageState extends State<ShareCommentComposePage> {
  late final _author = TextEditingController(
    text: widget.submission.input?.author ?? '',
  );
  late final _email = TextEditingController(
    text: widget.submission.input?.email ?? '',
  );
  late final _content = TextEditingController(
    text: widget.submission.input?.content ?? '',
  );
  final _form = GlobalKey<FormState>();
  String? _error;
  bool _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _busy =>
      widget.submission.phase == PublicCommentSubmissionPhase.submitting;
  bool get _unknown =>
      widget.submission.phase == PublicCommentSubmissionPhase.unknown;
  @override
  void dispose() {
    _author.clear();
    _email.clear();
    _content.clear();
    _author.dispose();
    _email.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('正在发送，请稍候。', 'Sending. Please wait.'))),
      );
      return;
    }
    if (!_unknown && _content.text.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('放弃未发布的评论？', 'Discard this draft?')),
          content: Text(
            t('此表单内容不会保存在设备上。', 'This form is not saved on this device.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续编辑', 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('放弃', 'Discard')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Future<void> _discardUnknown() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('放弃本次待确认记录？', 'Discard the pending record?')),
        content: Text(
          t(
            '评论可能已经发布。此操作只清除当前记录，不会删除服务端评论；再次发布可能造成重复。',
            'The comment may already be published. This only clears the pending record and does not delete a server comment. Publishing again can create a duplicate.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('保留记录', 'Keep record')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('放弃记录', 'Discard record')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.submission.reset(acknowledgeUnknown: true);
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Future<void> _submit() async {
    if (_busy || _unknown || !_form.currentState!.validate()) return;
    final reply = widget.reply;
    final input = PublicCommentInput(
      content: _content.text,
      author: _author.text,
      email: _email.text,
      parentId: reply?.id ?? 0,
      replyToId: reply?.id ?? 0,
    );
    setState(() => _error = null);
    final future = widget.submission.submit(widget.capabilities, input);
    setState(() {});
    try {
      final receipt = await future;
      if (!mounted) return;
      setState(() => _leaving = true);
      Navigator.pop(context, receipt);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _unknown
              ? t(
                  '发布结果未知，请先回评论列表核对。不会自动重发。',
                  'The result is unknown. Review the comments before trying again. Nothing is resent automatically.',
                )
              : t(
                  '评论未能发布，请检查内容和连接后重试。',
                  'Unable to publish. Check the content and connection, then retry.',
                ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.capabilities;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          title: Text(t('写评论', 'Write comment')),
          leading: BackButton(onPressed: _leave),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _leave,
                    child: Text(
                      _unknown
                          ? t('回列表核对', 'Review comments')
                          : t('取消', 'Cancel'),
                    ),
                  ),
                  if (!_unknown)
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? t('正在发布…', 'Publishing…')
                            : t('发布评论', 'Publish comment'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.contextDetail.title,
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
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.reply != null) ...[
                                Text(
                                  '${t('回复', 'Reply to')} ${widget.reply!.author}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (cap.signedIn) ...[
                                Text(
                                  '${t('当前公开账号', 'Public account')}: ${cap.account}',
                                ),
                                const SizedBox(height: 16),
                              ] else ...[
                                TextFormField(
                                  controller: _author,
                                  enabled: !_busy && !_unknown,
                                  decoration: InputDecoration(
                                    labelText: t('公开昵称', 'Public name'),
                                    helperText: t(
                                      '请填写昵称，避免显示网络地址。',
                                      'Enter a name to avoid displaying your network address.',
                                    ),
                                    helperMaxLines: 4,
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (v) =>
                                      v == null ||
                                          v.trim().isEmpty ||
                                          v.trim().runes.length > 40
                                      ? t(
                                          '昵称必填，最多40字',
                                          'Name required, up to 40 characters',
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 20),
                              ],
                              TextFormField(
                                controller: _email,
                                enabled: !_busy && !_unknown,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: t('邮箱（选填）', 'Email (optional)'),
                                  helperText: t(
                                    '不会出现在公开评论列表中。',
                                    'Not shown in the public comments list.',
                                  ),
                                  helperMaxLines: 4,
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) =>
                                    v != null &&
                                        v.trim().isNotEmpty &&
                                        (!v.contains('@') ||
                                            v.trim().runes.length > 200)
                                    ? t('请输入有效邮箱', 'Enter a valid email')
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _content,
                                enabled: !_busy && !_unknown,
                                minLines: 6,
                                maxLines: 14,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: t('评论内容', 'Comment'),
                                  alignLabelWithHint: true,
                                  counterText:
                                      '${_content.text.trim().runes.length} / ${cap.maxLength}',
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (v) =>
                                    v == null ||
                                        v.trim().isEmpty ||
                                        v.trim().runes.length > cap.maxLength
                                    ? t(
                                        '评论必填，最多${cap.maxLength}字',
                                        'Comment required, up to ${cap.maxLength} characters',
                                      )
                                    : null,
                              ),
                              if (_error != null || _unknown) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error ??
                                        t(
                                          '上次发布结果未知，请先核对列表。',
                                          'The previous result is unknown. Review comments first.',
                                        ),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                              if (_unknown)
                                TextButton(
                                  onPressed: _discardUnknown,
                                  child: Text(
                                    t('放弃本次待确认记录', 'Discard pending record'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
