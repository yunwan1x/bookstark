import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';
import '../../core/api_client.dart';
import '../../core/public_shares_repository.dart';

class ShareArticleUnlockDialog extends StatefulWidget {
  const ShareArticleUnlockDialog({
    super.key,
    required this.detail,
    required this.repository,
    this.english = false,
  });
  final PublicShareDetail detail;
  final PublicSharesRepository repository;
  final bool english;
  @override
  State<ShareArticleUnlockDialog> createState() =>
      _ShareArticleUnlockDialogState();
}

class _ShareArticleUnlockDialogState extends State<ShareArticleUnlockDialog> {
  final _password = TextEditingController();
  final _abort = Completer<void>();
  bool _busy = false, _visible = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    if (_password.text.isEmpty || _password.text.length > 4096) {
      setState(() => _error = t('请输入有效密码。', 'Enter a valid password.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.repository.unlock(
        widget.detail,
        _password.text,
        abortTrigger: _abort.future,
      );
      if (!mounted) return;
      if (value.reference != widget.detail.reference ||
          value.shareId != widget.detail.shareId ||
          value.targetId != widget.detail.targetId ||
          value.kind != widget.detail.kind ||
          !value.protected ||
          value.locked ||
          !value.markdown ||
          value.blogType != widget.detail.blogType) {
        throw const FormatException('Unlock context changed');
      }
      _password.clear();
      Navigator.pop(context, value);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              error is ApiFailure &&
                  error.status == 400 &&
                  (error.message.contains('密码') ||
                      error.message.toLowerCase().contains('password'))
              ? t('密码不正确，请重试。', 'Incorrect password. Try again.')
              : t(
                  '无法解锁，请核对密码和网络后重试。',
                  'Unable to unlock. Check the password and connection, then retry.',
                );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: Text(t('解锁阅读', 'Unlock and read')),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                widget.detail.blogType == 'article'
                    ? '输入分享密码后查看文章。'
                    : '输入分享密码后查看内容。',
                'Enter the share password to read.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: !_visible,
              enabled: !_busy,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 4096,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _unlock(),
              decoration: InputDecoration(
                labelText: t('分享密码', 'Share password'),
                counterText: '',
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _visible = !_visible),
                  tooltip: t(
                    _visible ? '隐藏密码' : '显示密码',
                    _visible ? 'Hide password' : 'Show password',
                  ),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: const Color(0xff6530ad)),
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff6530ad),
          foregroundColor: Colors.white,
        ),
        onPressed: _busy ? null : _unlock,
        child: Text(_busy ? t('正在解锁…', 'Unlocking…') : t('解锁', 'Unlock')),
      ),
    ],
  );
}
