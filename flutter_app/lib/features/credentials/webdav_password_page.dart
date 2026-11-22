import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_theme.dart';
import '../../core/webdav_password_repository.dart';
import '../../core/webdav_password_controller.dart';

class WebdavPasswordPage extends StatefulWidget {
  const WebdavPasswordPage({
    super.key,
    required this.repository,
    this.english = false,
    this.copy,
  });
  final WebdavPasswordRepository repository;
  final bool english;
  final Future<void> Function(String)? copy;
  @override
  State<WebdavPasswordPage> createState() => _WebdavPasswordPageState();
}

class _WebdavPasswordPageState extends State<WebdavPasswordPage> {
  late final _controller = WebdavPasswordController(widget.repository);
  bool _leaving = false;
  String? _copyStatus;
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
    super.dispose();
  }

  Future<void> _copy(String value) async {
    try {
      await (widget.copy ??
          (value) => Clipboard.setData(ClipboardData(text: value)))(value);
      if (mounted) {
        setState(() => _copyStatus = t('已复制', 'Copied'));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _copyStatus = t('未能复制，请重试。', 'Could not copy. Try again.'),
        );
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text(body),
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
      ) ??
      false;
  Future<void> _showResult() async {
    final result = _controller.result;
    if (!mounted || result == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppPasswordResultDialog(
        result: result,
        english: widget.english,
        copy:
            widget.copy ??
            (value) => Clipboard.setData(ClipboardData(text: value)),
      ),
    );
    if (mounted) {
      _controller.clearSecret();
    }
  }

  Future<void> _generate() async {
    final accepted = await _confirm(
      t('生成新的应用密码？', 'Generate a new app password?'),
      t(
        '新密码会立即替换旧密码，已配置的WebDAV客户端需要更新。',
        'The new password replaces the old one immediately. Existing WebDAV clients must update it.',
      ),
      t('确认生成新密码', 'Generate new password'),
    );
    if (accepted && mounted) {
      await _controller.reset();
      await _showResult();
    }
  }

  Future<void> _custom() async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AppPasswordInputDialog(english: widget.english),
    );
    if (password != null && mounted) {
      await _controller.reset(password: password);
      await _showResult();
    }
  }

  Future<void> _verify() async {
    await _controller.verify();
    await _showResult();
  }

  Future<void> _revoke() async {
    final account = _controller.profile?.account ?? '';
    final accepted = await _confirm(
      t('撤销应用密码？', 'Revoke the app password?'),
      '$account\n${t('撤销后，已配置的WebDAV客户端将无法访问。登录密码和网盘文件不会被删除。', 'Configured WebDAV clients will lose access. The login password and drive files are preserved.')}',
      t('确认撤销', 'Confirm revocation'),
    );
    if (accepted && mounted) {
      await _controller.revoke();
    }
  }

  Future<void> _acknowledge() async {
    if (await _confirm(
          t('清除未确认的本次记录？', 'Clear this unconfirmed record?'),
          t(
            '服务器可能已经接受操作。清除不会撤销服务器修改，也无法恢复丢失的随机密码；再次生成或设置会替换当前密码。',
            'The server may have accepted the operation. Clearing does not undo it or recover a lost random password. Another reset replaces the current password.',
          ),
          t('理解并继续管理', 'Understand and continue'),
        ) &&
        mounted) {
      _controller.acknowledgeUnknown();
    }
  }

  Future<void> _leave() async {
    if (_leaving || _controller.busy) {
      return;
    }
    if (_controller.unresolved &&
        !await _confirm(
          t('离开应用密码？', 'Leave app passwords?'),
          t(
            '操作结果尚未核对。离开会清除本次密码内存，不撤销服务器操作。',
            'The result is unverified. Leaving clears the password from this page and does not undo server changes.',
          ),
          t('离开', 'Leave'),
        )) {
      return;
    }
    if (mounted) {
      _controller.clearSecret();
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Widget _card(List<Widget> children) => Card(
    semanticContainer: false,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  String _status() => switch (_controller.phase) {
    WebdavPasswordPhase.failed => t(
      '未能读取或操作，请核对会话与连接。',
      'Could not read or perform the operation. Check session and connection.',
    ),
    WebdavPasswordPhase.changing => t('正在设置应用密码…', 'Setting the app password…'),
    WebdavPasswordPhase.verifying => t(
      '正在核对实际WebDAV凭据…',
      'Verifying actual WebDAV credentials…',
    ),
    WebdavPasswordPhase.unknown => t(
      '设置结果未知，不会自动重发。随机密码丢失时无法恢复。',
      'The reset result is unknown. It will not be resent. A lost random password cannot be recovered.',
    ),
    WebdavPasswordPhase.unverified => t(
      '已收到设置回执，实际凭据尚未完成核对。',
      'Reset acknowledged. Actual credential verification is incomplete.',
    ),
    WebdavPasswordPhase.confirmed =>
      _controller.receivedReceipt
          ? t(
              '本次设置回执和实际凭据已核对。',
              'This reset receipt and actual credentials were verified.',
            )
          : t(
              '本次候选凭据已核对；上次设置回执仍未知。',
              'This candidate was verified; the earlier reset receipt remains unknown.',
            ),
    WebdavPasswordPhase.revoking => t(
      '正在撤销应用密码…',
      'Revoking the app password…',
    ),
    WebdavPasswordPhase.revokeUnknown => t(
      '撤销结果未知，请只读核对。',
      'Revocation result unknown. Read to verify.',
    ),
    WebdavPasswordPhase.revokeUnverified => t(
      '已收到撤销回执，实际状态尚未核对。',
      'Revocation acknowledged. Actual state is unverified.',
    ),
    WebdavPasswordPhase.revoked =>
      _controller.receivedReceipt
          ? t(
              '撤销回执与实际无密码状态已核对。',
              'Revocation receipt and actual absence were verified.',
            )
          : t(
              '实际已无应用密码；上次撤销回执仍未知。',
              'Actual app password is absent; the earlier receipt remains unknown.',
            ),
    _ => '',
  };
  @override
  Widget build(BuildContext context) {
    final c = _controller,
        p = c.profile,
        status = _status(),
        enabled = !c.busy && !c.unresolved && c.profile != null;
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
          title: Text(t('WebDAV应用密码', 'WebDAV app password')),
          actions: [
            IconButton(
              tooltip: t('刷新', 'Refresh'),
              onPressed: c.busy ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card([
                  const Icon(
                    Icons.folder_copy_outlined,
                    color: Color(0xff0b4eff),
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('连接当前账户的网盘', 'Connect this account drive'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '应用密码独立于登录密码。',
                      'The app password is independent of your login password.',
                    ),
                  ),
                ]),
                if (c.busy) const LinearProgressIndicator(),
                if (p != null)
                  _card([
                    Text(
                      t('连接信息', 'Connection details'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(t('访问端点', 'Endpoint')),
                    SelectableText(p.endpoint.toString()),
                    TextButton.icon(
                      onPressed: () => _copy(p.endpoint.toString()),
                      icon: const Icon(Icons.copy),
                      label: Text(t('复制访问端点', 'Copy endpoint')),
                    ),
                    const SizedBox(height: 12),
                    Text('${t('用户名', 'Username')}: ${p.account}'),
                    const SizedBox(height: 16),
                    Text(
                      p.hasPassword
                          ? t('已设置应用密码', 'App password is set')
                          : t('尚未设置应用密码', 'No app password is set'),
                    ),
                    if (_copyStatus != null) Text(_copyStatus!),
                  ]),
                if (status.isNotEmpty)
                  _card([
                    Text(status),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.busy ? null : c.load,
                        child: Text(
                          t('只读刷新状态', 'Refresh state without writing'),
                        ),
                      ),
                    if (c.canVerify)
                      TextButton(
                        onPressed: c.busy ? null : _verify,
                        child: Text(t('核对本次新凭据', 'Verify this candidate')),
                      ),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.busy ? null : _acknowledge,
                        child: Text(
                          t('清除本次记录并继续', 'Clear this record and continue'),
                        ),
                      ),
                  ]),
                _card([
                  Text(
                    t('管理应用密码', 'Manage app password'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: enabled ? _generate : null,
                    child: Text(t('生成新的应用密码', 'Generate a new app password')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: enabled ? _custom : null,
                    child: Text(t('设置自定义应用密码', 'Set a custom app password')),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t(
                      '设置新密码后，旧密码立即失效。',
                      'Setting a new password invalidates the old password immediately.',
                    ),
                  ),
                  if (p?.hasPassword == true) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: enabled ? _revoke : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: Text(t('撤销应用密码', 'Revoke app password')),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        '撤销后，已配置的WebDAV客户端将无法访问。',
                        'Configured WebDAV clients lose access after revocation.',
                      ),
                    ),
                  ],
                ]),
                _card([
                  Text(
                    t(
                      '完整密码仅在成功生成或设置后显示，请及时保存。',
                      'The full password is shown only after generating or setting it. Store it before closing.',
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppPasswordInputDialog extends StatefulWidget {
  const _AppPasswordInputDialog({required this.english});
  final bool english;
  @override
  State<_AppPasswordInputDialog> createState() =>
      _AppPasswordInputDialogState();
}

class _AppPasswordInputDialogState extends State<_AppPasswordInputDialog> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController(), _repeat = TextEditingController();
  bool _closing = false;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _first.clear();
    _repeat.clear();
    _first.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _close(String? value) async {
    if (_closing) {
      return;
    }
    setState(() {
      _first.clear();
      _repeat.clear();
      _generation++;
      _closing = true;
    });
    FocusScope.of(context).unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.pop(context, value);
    }
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      _close(_first.text);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool repeat = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('$label/$_generation'),
      controller: controller,
      enabled: !_closing,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [],
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (repeat) {
          return value == _first.text && value != null && value.isNotEmpty
              ? null
              : t('两次密码须完全一致。', 'Both passwords must match exactly.');
        }
        try {
          validateWebdavAppPassword(value ?? '');
          return null;
        } catch (_) {
          return t(
            '需要8—64个字符，且不超过72字节。',
            'Use 8–64 characters and at most 72 UTF8 bytes.',
          );
        }
      },
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _closing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        _close(null);
      }
    },
    child: Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('设置自定义应用密码', 'Set a custom app password'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _field(t('新应用密码', 'New app password'), _first),
              _field(
                t('确认应用密码', 'Confirm app password'),
                _repeat,
                repeat: true,
              ),
              Text(
                t(
                  '保留输入的空格；旧密码将立即失效。此处不会修改登录密码。',
                  'Spaces are preserved. The old app password becomes invalid. Your login password is unchanged.',
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _closing ? null : () => _close(null),
                    child: Text(t('取消', 'Cancel')),
                  ),
                  FilledButton(
                    onPressed: _closing ? null : _submit,
                    child: Text(t('确认替换应用密码', 'Replace app password')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AppPasswordResultDialog extends StatefulWidget {
  const _AppPasswordResultDialog({
    required this.result,
    required this.english,
    required this.copy,
  });
  final WebdavPasswordResult result;
  final bool english;
  final Future<void> Function(String) copy;
  @override
  State<_AppPasswordResultDialog> createState() =>
      _AppPasswordResultDialogState();
}

class _AppPasswordResultDialogState extends State<_AppPasswordResultDialog> {
  late String _secret = widget.result.secret;
  bool _revealed = false, _copied = false, _copying = false, _closing = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _secret = '';
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying || _secret.isEmpty) {
      return;
    }
    setState(() => _copying = true);
    try {
      await widget.copy(_secret);
      if (mounted) {
        setState(() => _copied = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _copied = false);
      }
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      }
    }
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    setState(() {
      _secret = '';
      _revealed = false;
      _closing = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _closing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        _close();
      }
    },
    child: Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('应用密码已核对', 'App password verified'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(widget.result.profile.account),
            const SizedBox(height: 12),
            SelectableText(
              _revealed ? _secret : '••••••••••••',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Text(
              widget.result.receivedReceipt
                  ? t(
                      '设置回执与实际WebDAV凭据均已核对。',
                      'The reset receipt and actual DAV credentials were verified.',
                    )
                  : t(
                      '本次候选已通过实际WebDAV核对；上次设置回执仍未知。',
                      'Actual DAV accepted this candidate; the earlier reset receipt remains unknown.',
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '完整密码仅此处显示，关闭后无法从服务器恢复，请及时保存。',
                'The full password is available only here. It cannot be recovered from the server after closing. Store it now.',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _closing
                      ? null
                      : () => setState(() => _revealed = !_revealed),
                  child: Text(
                    _revealed
                        ? t('隐藏应用密码', 'Hide app password')
                        : t('显示本次应用密码', 'Show this app password'),
                  ),
                ),
                TextButton(
                  onPressed: _copying || _closing ? null : _copy,
                  child: Text(
                    _copied
                        ? t('已复制', 'Copied')
                        : t('复制本次应用密码', 'Copy this app password'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _closing ? null : _close,
              child: Text(t('关闭并清除本次显示', 'Close and clear this display')),
            ),
          ],
        ),
      ),
    ),
  );
}
