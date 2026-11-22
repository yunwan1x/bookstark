import '../../core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';
import '../../core/public_shares_repository.dart';

class ShareUnlockPage extends StatefulWidget {
  const ShareUnlockPage({
    super.key,
    required this.detail,
    required this.repository,
    this.english = false,
    this.onReturnToFeed,
    this.editing = false,
    this.verifyPassword,
    this.onReturnToReader,
  });
  final PublicShareDetail detail;
  final PublicSharesRepository repository;
  final bool english;
  final bool editing;
  final Future<PublicShareDetail> Function(
    String password,
    Future<void> abortTrigger,
  )?
  verifyPassword;
  final VoidCallback? onReturnToReader;
  final VoidCallback? onReturnToFeed;
  @override
  State<ShareUnlockPage> createState() => _ShareUnlockPageState();
}

class _ShareUnlockPageState extends State<ShareUnlockPage> {
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _abort = Completer<void>();
  bool _visible = false, _busy = false;
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
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = widget.verifyPassword != null
          ? await widget.verifyPassword!(_password.text, _abort.future)
          : await widget.repository.unlock(
              widget.detail,
              _password.text,
              abortTrigger: _abort.future,
            );
      if (!mounted) return;
      _password.clear();
      Navigator.pop(context, value);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          // Never surface a server response which could echo submitted secrets.
          _error = t(
            '无法解锁，请核对密码和网络后重试。',
            'Unable to unlock. Check the password and connection, then retry.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
    appBar: AppBar(
      title: Text(
        widget.editing
            ? t('验证分享密码', 'Verify share password')
            : t('解锁分享', 'Unlock share'),
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: Color(0xffdcebff),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xff155af5),
                      size: 52,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.editing
                      ? t(
                          '编辑链接对应受保护内容',
                          'This editing link opens protected content',
                        )
                      : t('内容已加密', 'Content is protected'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.detail.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  t(
                    widget.editing
                        ? '编辑链接已验证，还需要分享密码读取和保存正文。'
                        : '分享内容需要密码才能阅读。',
                    widget.editing
                        ? 'The editing link is verified. A share password is also needed to read and save the content.'
                        : 'A password is required to read this share.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
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
                          Text(
                            t('分享密码', 'Share password'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_visible,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            autofillHints: const [],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _unlock(),
                            validator: (value) => value == null || value.isEmpty
                                ? t('请输入分享密码', 'Enter the share password')
                                : value.length > 4096
                                ? t('密码过长', 'Password is too long')
                                : null,
                            decoration: InputDecoration(
                              hintText: t(
                                '请输入分享密码',
                                'Enter the share password',
                              ),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          setState(() => _visible = !_visible),
                                tooltip: _visible
                                    ? t('隐藏密码', 'Hide password')
                                    : t('显示密码', 'Show password'),
                                icon: Icon(
                                  _visible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t(
                              widget.editing
                                  ? '密码仅在本次编辑会话使用，不保存到设备。'
                                  : '密码仅用于本次解锁，不保存在设备上。',
                              widget.editing
                                  ? 'The password is used only in this editing session and is not saved on this device.'
                                  : 'The password is used for this unlock only and is not saved on this device.',
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _unlock,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            child: Text(
                              _busy
                                  ? t('正在解锁…', 'Unlocking…')
                                  : widget.editing
                                  ? t('验证并编辑', 'Verify and edit')
                                  : t('解锁阅读', 'Unlock and read'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.editing
                      ? (widget.onReturnToReader ??
                            () => Navigator.pop(context))
                      : (widget.onReturnToFeed ?? () => Navigator.pop(context)),
                  child: Text(
                    widget.editing
                        ? t('返回阅读', 'Return to reading')
                        : widget.onReturnToFeed == null
                        ? t('返回', 'Back')
                        : t('返回广场', 'Back to feed'),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xffe5f0ff),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xff155af5)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.editing
                                  ? t(
                                      '密码不会授予其他编辑权限',
                                      'A password does not grant other editing permissions',
                                    )
                                  : t('解锁后仍为只读阅读', 'Reading remains read-only'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t(
                                widget.editing
                                    ? '保存前仍会核对编辑链接、内容版本与保护状态。'
                                    : '共享编辑需要单独的编辑链接。',
                                widget.editing
                                    ? 'The editing link, content version and protection are checked again before saving.'
                                    : 'Shared editing requires a separate edit link.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
