import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/content_password_controller.dart';
import '../../core/content_password_repository.dart';

class ContentPasswordPage extends StatefulWidget {
  const ContentPasswordPage({
    super.key,
    required this.id,
    required this.repository,
    this.english = false,
  });
  final int id;
  final ContentPasswordRepository repository;
  final bool english;
  @override
  State<ContentPasswordPage> createState() => _ContentPasswordPageState();
}

class _ContentPasswordPageState extends State<ContentPasswordPage> {
  late final _controller = ContentPasswordController(
    widget.repository,
    widget.id,
  );
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _leaving = false;
  int _inputGeneration = 0;
  final _visible = <String>{};
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _controller.load();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _current.clear();
    _next.clear();
    _confirm.clear();
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<bool> _ask(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(message),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(t('取消', 'Cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(action),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
  Future<void> _leave() async {
    if (_leaving) {
      return;
    }
    final c = _controller;
    if (c.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('正在处理，请稍候。', 'Processing. Please wait.'))),
      );
      return;
    }
    if ((c.unresolved ||
            _current.text.isNotEmpty ||
            _next.text.isNotEmpty ||
            _confirm.text.isNotEmpty) &&
        !await _ask(
          t('离开密码设置？', 'Leave password settings?'),
          c.unresolved
              ? t(
                  '操作可能已生效。离开清除本次密码和内存记录，不撤销服务端修改。',
                  'The operation may have applied. Leaving clears session passwords and does not undo server changes.',
                )
              : t(
                  '离开将清除尚未提交的密码。',
                  'Leaving clears the passwords you have not submitted.',
                ),
          t('离开', 'Leave'),
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    Navigator.pop(context, c.protection?.protected);
  }

  String? _passwordError(String? value) {
    try {
      validateContentPassword(value ?? '');
      return null;
    } catch (_) {
      return t(
        '请输入1—1024 UTF8字节的有效密码',
        'Enter a valid password of 1–1024 UTF8 bytes',
      );
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('$label/$_inputGeneration'),
      controller: controller,
      enabled: !_controller.busy && !_controller.unresolved,
      obscureText: !_visible.contains(label),
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [],
      keyboardType: TextInputType.visiblePassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _visible.contains(label)
              ? t('隐藏密码', 'Hide password')
              : t('显示密码', 'Show password'),
          onPressed: () => setState(() {
            if (!_visible.add(label)) {
              _visible.remove(label);
            }
          }),
          icon: Icon(
            _visible.contains(label)
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: validate ?? _passwordError,
    ),
  );
  Future<void> _change({bool remove = false}) async {
    final c = _controller, protected = c.protection?.protected == true;
    FocusScope.of(context).unfocus();
    if (remove) {
      if (!protected || _passwordError(_current.text) != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('请先填写当前密码。', 'Enter the current password first.')),
          ),
        );
        return;
      }
      if (!await _ask(
        t('移除内容密码？', 'Remove the body password?'),
        t(
          '正文将无需密码。公开分享和编辑令牌会保留；请核对公开范围。',
          'The body will no longer require a password. Public sharing and editing tokens remain; check the publication scope.',
        ),
        t('验证并移除', 'Verify and remove'),
      )) {
        return;
      }
    } else if (!_form.currentState!.validate()) {
      return;
    }
    try {
      await c.change(
        newPassword: remove ? '' : _next.text,
        currentPassword: protected ? _current.text : null,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('密码输入未通过校验。', 'The password input is invalid.')),
          ),
        );
      }
    } finally {
      _current.clear();
      _next.clear();
      _confirm.clear();
      _visible.clear();
      _inputGeneration++;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Widget _card(List<Widget> children) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = _controller, actual = c.protection;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('内容密码', 'Body password')),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.busy) const LinearProgressIndicator(),
                if (actual != null)
                  _card([
                    _heading(actual.title),
                    Text(
                      t(
                        '仅管理当前笔记或文章的正文保护。',
                        'Manage only this note or article body.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      actual.protected
                          ? t('当前设有密码。', 'A password is currently set.')
                          : t('当前未设置密码。', 'No password is currently set.'),
                    ),
                  ]),
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xffe3edff),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    t(
                      '设置密码后正文需要验证才能读取。公开标题等信息仍可能可见。',
                      'A password protects body access. Public titles and other metadata may remain visible.',
                    ),
                  ),
                ),
                if (c.phase == ContentPasswordPhase.failed)
                  _card([
                    Text(
                      t(
                        '操作未完成。请核对连接、权限和当前密码。',
                        'The operation failed. Check connection, permission and current password.',
                      ),
                    ),
                    TextButton(
                      onPressed: c.load,
                      child: Text(t('重读保护状态', 'Reload protection status')),
                    ),
                  ]),
                if (c.unresolved)
                  _card([
                    _heading(t('结果仍需核对', 'Result needs verification')),
                    Text(
                      c.receivedWriteReceipt
                          ? t(
                              '已收到更改回执，但实际密码状态尚未核对完成。',
                              'A write receipt was received, but actual password verification is incomplete.',
                            )
                          : t(
                              '请求结果未知，可能已经修改。不会自动重发。',
                              'The request result is unknown and may have applied. It will not be resent automatically.',
                            ),
                    ),
                    TextButton(
                      onPressed: c.inspect,
                      child: Text(
                        t('只读核对更改结果', 'Verify the result without writing'),
                      ),
                    ),
                  ]),
                if (c.phase == ContentPasswordPhase.confirmed)
                  _card([
                    Text(
                      c.receivedWriteReceipt
                          ? t('密码更改已核对。', 'Password change verified.')
                          : t(
                              '当前密码状态已核对；上次写回执仍未知。',
                              'Current password state verified; the earlier write receipt remains unknown.',
                            ),
                    ),
                  ]),
                if (actual != null && !c.unresolved)
                  Form(
                    key: _form,
                    child: _card([
                      _heading(
                        actual.protected
                            ? t('修改内容密码', 'Change body password')
                            : t('设置内容密码', 'Set body password'),
                      ),
                      if (actual.protected)
                        _field(t('当前密码', 'Current password'), _current),
                      _field(t('新密码', 'New password'), _next),
                      _field(
                        t('确认新密码', 'Confirm new password'),
                        _confirm,
                        validate: (value) =>
                            value != _next.text ||
                                value == null ||
                                value.isEmpty
                            ? t(
                                '两次新密码须完全一致',
                                'Both new passwords must match exactly',
                              )
                            : null,
                      ),
                      Text(
                        t(
                          '保留输入空格；密码不保存到设备。不自动重试未知结果。',
                          'Spaces are preserved. Passwords are not saved on this device. Unknown writes are never retried automatically.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: c.busy ? null : () => _change(),
                        child: Text(
                          actual.protected
                              ? t('修改密码', 'Change password')
                              : t('设置密码', 'Set password'),
                        ),
                      ),
                    ]),
                  ),
                if (actual?.protected == true && !c.unresolved)
                  _card([
                    _heading(t('移除内容密码', 'Remove body password')),
                    Text(
                      t(
                        '移除后正文无需密码。公开分享仍会保留。',
                        'Removing the password leaves public sharing in place.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: c.busy ? null : () => _change(remove: true),
                      child: Text(t('验证并移除密码', 'Verify and remove password')),
                    ),
                  ]),
                Text(
                  t(
                    '操作后核对实际保护状态，不读取密码到磁盘。',
                    'Actual protection is verified after changes. Passwords stay off disk.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
