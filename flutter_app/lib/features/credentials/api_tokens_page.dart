import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_theme.dart';
import '../../core/api_tokens_repository.dart';
import '../../core/api_tokens_controller.dart';

class ApiTokensPage extends StatefulWidget {
  const ApiTokensPage({
    super.key,
    required this.repository,
    this.english = false,
    this.copySecret,
  });
  final ApiTokensRepository repository;
  final bool english;
  final Future<void> Function(String)? copySecret;
  @override
  State<ApiTokensPage> createState() => _ApiTokensPageState();
}

class _ApiTokensPageState extends State<ApiTokensPage> {
  late final _controller = ApiTokensController(widget.repository);
  bool _leaving = false;
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
  Future<void> _create() async {
    if (_controller.busy || _controller.unresolved) {
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TokenNameDialog(english: widget.english),
    );
    if (name == null || !mounted) {
      return;
    }
    await _controller.create(name);
    final actual = _controller.created;
    if (!mounted || actual == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreatedTokenDialog(
        receipt: actual,
        english: widget.english,
        copy:
            widget.copySecret ??
            (value) => Clipboard.setData(ClipboardData(text: value)),
      ),
    );
    if (mounted) {
      _controller.clearSecret();
    }
  }

  Future<void> _revoke(ApiTokenEntry entry) async {
    final consequence = t(
      '使用该令牌的工具将失去访问权限。',
      'Tools using this token will lose access.',
    );
    final accepted = await _confirm(
      t('撤销这个令牌？', 'Revoke this token?'),
      '${entry.name} · ID ${entry.id}\n$consequence',
      t('撤销令牌', 'Revoke token'),
    );
    if (accepted && mounted) {
      await _controller.revoke(entry);
    }
  }

  Future<void> _acknowledgeCreate() async {
    if (await _confirm(
          t('继续管理令牌？', 'Continue managing tokens?'),
          t(
            '上次请求可能已创建令牌。刷新只能读取掩码，不能恢复完整令牌；再次创建将产生独立的新令牌。',
            'The earlier request may have created a token. Refresh can read only its mask. Creating again makes a separate token.',
          ),
          t('理解并继续管理', 'Understand and continue'),
        ) &&
        mounted) {
      _controller.acknowledgeUnknownCreate();
    }
  }

  Future<void> _leave() async {
    if (_leaving || _controller.busy) {
      return;
    }
    if (_controller.unresolved &&
        !await _confirm(
          t('离开令牌管理？', 'Leave token management?'),
          t(
            '服务器可能已接受未核对的请求。离开不会撤销服务器操作，完整令牌也无法从列表恢复。',
            'The server may have accepted an unverified request. Leaving does not undo it. Full tokens cannot be recovered from the list.',
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
    ApiTokenPhase.failed => t(
      '读取或操作未能完成，请核对会话与连接。',
      'Reading or the operation failed. Check the session and connection.',
    ),
    ApiTokenPhase.creating => t('正在创建令牌…', 'Creating token…'),
    ApiTokenPhase.created => t(
      '已收到实际创建回执。',
      'Actual creation receipt received.',
    ),
    ApiTokenPhase.createUnknown => t(
      '创建结果未知，不会自动重发。请先刷新核对记录。',
      'Creation result unknown. It will not be resent. Refresh to review actual records.',
    ),
    ApiTokenPhase.revoking => t('正在撤销令牌…', 'Revoking token…'),
    ApiTokenPhase.revokeUnknown => t(
      '撤销结果未知，不会自动重发。',
      'Revocation result unknown. It will not be resent.',
    ),
    ApiTokenPhase.revokeUnverified => t(
      '已收到撤销回执，列表尚未证明该ID已消失。',
      'Revocation acknowledged. The list has not verified absence of this ID.',
    ),
    ApiTokenPhase.revoked =>
      _controller.receivedRevocationReceipt
          ? t('撤销回执和实际列表已核对。', 'Revocation receipt and actual list verified.')
          : t(
              '实际列表已核对为不存在；上次撤销回执仍未知。',
              'Actual list verified the ID is absent; the earlier revocation receipt remains unknown.',
            ),
    _ => '',
  };
  Widget _entry(ApiTokenEntry entry, {bool receiptOnly = false}) => _card([
    Text(
      entry.name.isEmpty ? t('未命名令牌', 'Unnamed token') : entry.name,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xffe3edff),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            entry.masked,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
          ),
        ),
        OutlinedButton(
          onPressed: _controller.busy || _controller.unresolved
              ? null
              : () => _revoke(entry),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: Text(t('撤销', 'Revoke')),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Text('${t('创建于', 'Created')}: ${entry.createdAt.split('T').first}'),
    Text('ID ${entry.id}'),
    if (receiptOnly)
      Text(
        t(
          '本次创建回执中的记录，当前列表尚未显示。',
          'From this creation receipt; not shown in the current list.',
        ),
      ),
  ]);
  @override
  Widget build(BuildContext context) {
    final c = _controller, status = _status();
    final latest = c.latestCreated;
    final latestOutside =
        latest != null &&
        c.page != null &&
        !c.page!.entries.any((row) => row.id == latest.id);
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
          title: Text(t('API令牌', 'API tokens')),
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
                  const Icon(Icons.key, color: Color(0xff0b4eff), size: 40),
                  const SizedBox(height: 16),
                  Text(
                    t('连接工具与扩展', 'Connect tools and extensions'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '为当前账户创建API令牌。完整令牌仅在创建成功后显示。',
                      'Create API tokens for this account. Full tokens are shown only after a successful creation.',
                    ),
                  ),
                ]),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('我的令牌', 'My tokens'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    FilledButton(
                      onPressed: c.busy || c.unresolved || c.page == null
                          ? null
                          : _create,
                      child: Text(t('创建令牌', 'Create token')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (c.busy) const LinearProgressIndicator(),
                if (status.isNotEmpty)
                  _card([
                    Text(status),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.busy ? null : c.load,
                        child: Text(
                          t('只读刷新核对记录', 'Refresh records without writing'),
                        ),
                      ),
                    if (c.phase == ApiTokenPhase.createUnknown)
                      TextButton(
                        onPressed: c.busy ? null : _acknowledgeCreate,
                        child: Text(t('核对后继续管理', 'Continue after review')),
                      ),
                  ]),
                if (c.page != null && c.page!.entries.isEmpty)
                  _card([Text(t('尚无API令牌。', 'No API tokens yet.'))]),
                for (final entry in c.page?.entries ?? <ApiTokenEntry>[])
                  _entry(entry),
                if (latestOutside) _entry(latest, receiptOnly: true),
                _card([
                  Text(
                    t(
                      '令牌列表最多显示100条。撤销会使使用该令牌的工具失去访问权限。',
                      'The list shows up to 100 tokens. Revocation removes access for tools using that token.',
                    ),
                  ),
                  if (c.page?.truncated == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      t(
                        '当前列表已达到返回上限，可能还有未显示记录。',
                        'The returned list has reached its cap. Other records may exist.',
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenNameDialog extends StatefulWidget {
  const _TokenNameDialog({required this.english});
  final bool english;
  @override
  State<_TokenNameDialog> createState() => _TokenNameDialogState();
}

class _TokenNameDialogState extends State<_TokenNameDialog> {
  final _name = TextEditingController(), _form = GlobalKey<FormState>();
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _name.text);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('创建API令牌', 'Create API token'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: t('名称', 'Name')),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                try {
                  validateApiTokenName(value ?? '');
                  return null;
                } catch (_) {
                  return t(
                    '名称最多100字节，请减少后重试。',
                    'Name: up to 100 UTF8 bytes. Shorten it and retry.',
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '可以留空使用default；不会自动创建或自动重试。',
                'Leave blank for default. Creation and retries are explicit.',
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: _submit,
                  child: Text(t('创建', 'Create')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CreatedTokenDialog extends StatefulWidget {
  const _CreatedTokenDialog({
    required this.receipt,
    required this.english,
    required this.copy,
  });
  final CreatedApiToken receipt;
  final bool english;
  final Future<void> Function(String) copy;
  @override
  State<_CreatedTokenDialog> createState() => _CreatedTokenDialogState();
}

class _CreatedTokenDialogState extends State<_CreatedTokenDialog> {
  late String _secret = widget.receipt.secret;
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
              t('令牌已创建', 'Token created'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.receipt.entry.name} · ID ${widget.receipt.entry.id}',
            ),
            const SizedBox(height: 16),
            SelectableText(
              _revealed ? _secret : widget.receipt.entry.masked,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '完整令牌仅此处显示。关闭后只能看到列表掩码，请妥善保存。',
                'The full token is available only here. After closing, the list shows only its mask. Store it securely.',
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
                        ? t('隐藏令牌', 'Hide token')
                        : t('显示本次令牌', 'Show this token'),
                  ),
                ),
                TextButton(
                  onPressed: _copying || _closing ? null : _copy,
                  child: Text(
                    _copied
                        ? t('已复制', 'Copied')
                        : t('复制本次令牌', 'Copy this token'),
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
