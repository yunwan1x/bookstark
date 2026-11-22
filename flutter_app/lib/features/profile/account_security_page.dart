import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/profile_repository.dart';
import '../../core/account_password_repository.dart';
import '../../core/account_security_controller.dart';

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({
    super.key,
    required this.member,
    required this.repository,
    this.english = false,
  });
  final MemberProfile member;
  final AccountPasswordRepository repository;
  final bool english;
  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  late final _controller = AccountSecurityController(widget.repository);
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();
  final _visible = <String>{};
  int _inputGeneration = 0;
  bool _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
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

  String? _validate(String? value, {bool next = false}) {
    try {
      validateLoginPassword(value ?? '', newPassword: next);
      return null;
    } catch (_) {
      return next
          ? t(
              '新密码至少6个字符，最多72 UTF8字节',
              'New password: at least6 characters, up to72 UTF8 bytes',
            )
          : t('请输入有效的当前登录密码', 'Enter a valid current login password');
    }
  }

  Future<void> _submit() async {
    final c = _controller;
    if (c.busy || c.unresolved || !_form.currentState!.validate()) {
      return;
    }
    final pending = c.change(_current.text, _next.text);
    // Clear the actual active input before detaching it, then replace every
    // semantics input node so the Web layer cannot retain an old value.
    _current.clear();
    _next.clear();
    _confirm.clear();
    _visible.clear();
    _inputGeneration++;
    FocusScope.of(context).unfocus();
    setState(() {});
    try {
      await pending;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('密码输入未通过校验。', 'The password input is invalid.')),
          ),
        );
      }
    }
  }

  Future<void> _leave() async {
    final c = _controller;
    if (_leaving) {
      return;
    }
    if (c.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('正在处理，请稍候。', 'Processing. Please wait.'))),
      );
      return;
    }
    if (c.unresolved ||
        _current.text.isNotEmpty ||
        _next.text.isNotEmpty ||
        _confirm.text.isNotEmpty) {
      final leave = await showDialog<bool>(
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
                  Text(
                    t('离开账户安全？', 'Leave account security?'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.phase == AccountSecurityPhase.sessionUnstored
                        ? t(
                            '新凭据已验证，但当前会话尚未保存。离开后可能需要重新登录。',
                            'The new credentials were verified, but this session is not saved. You may need to sign in again.',
                          )
                        : c.unresolved
                        ? t(
                            '密码可能已经修改。离开清除本次密码和内存记录，不撤销服务器修改。',
                            'The password may have changed. Leaving clears session passwords and does not undo server changes.',
                          )
                        : t(
                            '离开将清除尚未提交的密码。',
                            'Leaving clears passwords that have not been submitted.',
                          ),
                  ),
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
                        child: Text(t('离开', 'Leave')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (leave != true) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Widget _card(List<Widget> children) => Card(
    semanticContainer: false,
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
  Widget _field(
    String label,
    TextEditingController controller, {
    bool next = false,
    bool confirmation = false,
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
      validator: (value) => confirmation
          ? (value == _next.text && value != null && value.isNotEmpty
                ? null
                : t('两次新密码须完全一致', 'Both new passwords must match exactly'))
          : _validate(value, next: next),
    ),
  );
  String _status() {
    final c = _controller;
    return switch (c.phase) {
      AccountSecurityPhase.changing => t(
        '正在提交密码修改…',
        'Submitting the password change…',
      ),
      AccountSecurityPhase.verifying => t(
        '正在验证新凭据…',
        'Verifying the new credentials…',
      ),
      AccountSecurityPhase.persisting => t('正在保存当前会话…', 'Saving this session…'),
      AccountSecurityPhase.rejected => t(
        '未能更改，请核对当前密码、会话和连接。',
        'The change failed. Check the current password, session and connection.',
      ),
      AccountSecurityPhase.unknown => t(
        '修改结果未知。不会自动重发，请先验证新凭据。',
        'The change result is unknown. It will not be resent. Verify the new credentials first.',
      ),
      AccountSecurityPhase.unverified => t(
        '已收到修改回执，登录验证尚未完成。',
        'The change was acknowledged. Login verification is incomplete.',
      ),
      AccountSecurityPhase.sessionUnstored => t(
        '新凭据已验证，但当前会话尚未保存。',
        'The new credentials are verified, but this session is not saved.',
      ),
      AccountSecurityPhase.complete =>
        c.receivedWriteReceipt
            ? t(
                '登录密码修改已核对，当前会话已保存。',
                'The password change was verified and this session is saved.',
              )
            : t(
                '新凭据已验证，会话已保存；上次修改回执仍未知。',
                'The new credentials are verified and saved; the earlier change receipt remains unknown.',
              ),
      _ => t(
        '修改后会核对实际登录状态。',
        'The actual login state is verified after the change.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
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
          title: Text(t('账户安全', 'Account security')),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card([
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.lock, color: Color(0xff0b4eff)),
                      Text(
                        '${t('账号', 'Account')}: ${widget.member.account}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '修改登录密码，与内容密码独立。',
                      'Change the login password independently of content passwords.',
                    ),
                  ),
                ]),
                if (c.phase != AccountSecurityPhase.ready)
                  _card([
                    Text(_status()),
                    if ({
                      AccountSecurityPhase.unknown,
                      AccountSecurityPhase.unverified,
                    }.contains(c.phase))
                      TextButton(
                        onPressed: c.busy ? null : c.verify,
                        child: Text(
                          t('验证本次新凭据', 'Verify these new credentials'),
                        ),
                      ),
                    if (c.phase == AccountSecurityPhase.sessionUnstored)
                      TextButton(
                        onPressed: c.persist,
                        child: Text(t('仅重试保存会话', 'Retry session saving only')),
                      ),
                  ]),
                Form(
                  key: _form,
                  child: _card([
                    _heading(t('修改登录密码', 'Change login password')),
                    _field(t('当前登录密码', 'Current login password'), _current),
                    _field(t('新登录密码', 'New login password'), _next, next: true),
                    Text(
                      t(
                        '至少6个字符，最多72字节；保留输入的空格。',
                        'At least6 characters, up to72 UTF8 bytes. Spaces are preserved.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _field(
                      t('确认新登录密码', 'Confirm new login password'),
                      _confirm,
                      confirmation: true,
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xffe3edff),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t(
                          '修改后会重新核对登录状态，不会自动重试未知结果。',
                          'Login state is rechecked after changes. Unknown results are never retried automatically.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: c.busy || c.unresolved ? null : _submit,
                      child: Text(t('修改登录密码', 'Change login password')),
                    ),
                  ]),
                ),
                _card([
                  _heading(t('会话与隐私', 'Session and privacy')),
                  Text(
                    t(
                      '密码不保存在设备上，提交后清空输入。',
                      'Passwords are not stored on this device. Inputs are cleared on submission.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '修改成功后更新当前会话，需要时重新登录。',
                      'The current session is updated after a change. Sign in again when needed.',
                    ),
                  ),
                ]),
                Text(
                  t(
                    '退出前会提示尚未确认的修改。',
                    'Unconfirmed changes are reviewed before leaving.',
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
