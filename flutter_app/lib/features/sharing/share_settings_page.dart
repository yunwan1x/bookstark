import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/public_share_models.dart';
import '../../core/share_settings_controller.dart';
import '../../core/share_settings_repository.dart';

class ShareSettingsPage extends StatefulWidget {
  const ShareSettingsPage({
    super.key,
    required this.target,
    required this.repository,
    this.english = false,
    this.onRead,
    this.onPassword,
  });
  final OwnerShareTarget target;
  final ShareSettingsRepository repository;
  final bool english;
  final Future<void> Function(PublicShareReference)? onRead;
  final Future<bool?> Function()? onPassword;
  @override
  State<ShareSettingsPage> createState() => _ShareSettingsPageState();
}

class _ShareSettingsPageState extends State<ShareSettingsPage> {
  late final _controller = ShareSettingsController(
    widget.repository,
    widget.target,
  );
  bool _leaving = false;
  late bool _protected = widget.target.protected;
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

  Future<bool> _confirm(
    String title,
    String message,
    String action, {
    bool destructive = false,
  }) async =>
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
                        style: destructive
                            ? TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              )
                            : null,
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
    if (_controller.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('正在核对或提交，请稍候。', 'Checking or submitting. Please wait.'),
          ),
        ),
      );
      return;
    }
    if (_controller.uncertain &&
        !await _confirm(
          t('离开结果待确认的操作？', 'Leave an unconfirmed operation?'),
          t(
            '服务端可能已完成操作。离开只清除本次内存记录，不撤销发布、重置或撤回。',
            'The server may have applied the operation. Leaving clears session memory and does not undo publication, reset or withdrawal.',
          ),
          t('离开', 'Leave'),
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    Navigator.pop(context);
  }

  Future<void> _publish() async {
    final recovery = _controller.uncertain;
    if (!await _confirm(
      t(
        recovery ? '重新获取当前链接？' : '公开并获取链接？',
        recovery ? 'Recover the current link?' : 'Publish and obtain links?',
      ),
      t(
        '此操作将确认当前资源公开可见。文章或笔记会设为公开；标题、作者等信息可能可见，正文密码不等于隐藏全部信息。已有编辑令牌会按服务端回执保留，不会自动重置。',
        'This explicitly publishes this resource. Article or note visibility becomes public; title and author may be visible. A body password does not hide all metadata. Existing editing tokens are retained according to the actual receipt.',
      ),
      t('确认公开并获取', 'Publish and obtain'),
    )) {
      return;
    }
    await _controller.publish(acknowledgeUnknown: recovery);
  }

  Future<void> _token(ShareTokenAction action) async {
    final reset = action == ShareTokenAction.reset,
        disable = action == ShareTokenAction.disable;
    if (!await _confirm(
      t(
        disable
            ? '关闭编辑链接？'
            : reset
            ? '重置编辑链接？'
            : '开启编辑链接？',
        disable
            ? 'Disable editing link?'
            : reset
            ? 'Reset editing link?'
            : 'Enable editing link?',
      ),
      t(
        disable
            ? '已有编辑链接将失效，阅读链接保留。'
            : reset
            ? '旧编辑链接立即失效。请将新链接单独发送给可信任的人。'
            : '持有编辑链接的人可以修改正文。受保护内容仍须验证正文密码。',
        disable
            ? 'Existing editing links stop working; the reading link remains.'
            : reset
            ? 'The old editing link becomes invalid. Send the new link separately to trusted people.'
            : 'Anyone holding the editing link may change the body. Protected content still requires its password.',
      ),
      t('确认', 'Confirm'),
      destructive: disable || reset,
    )) {
      return;
    }
    await _controller.changeToken(action);
  }

  Future<void> _unpublish() async {
    final recovery = _controller.uncertain;
    if (!await _confirm(
      t('停止分享？', 'Stop sharing?'),
      t(
        '阅读链接和编辑链接都将失效，原内容不会删除。上次结果若未知，本次是明确请求撤回，不会重新发布。',
        'Both reading and editing links stop working. The source content is retained. If a previous result is unknown, this explicitly requests withdrawal and does not republish.',
      ),
      t('停止分享', 'Stop sharing'),
      destructive: true,
    )) {
      return;
    }
    await _controller.unpublish(acknowledgeUnknown: recovery);
  }

  Future<void> _copy(String value, {bool capability = false}) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              capability
                  ? t('已复制编辑链接，请勿公开。', 'Editing link copied. Keep it private.')
                  : t('已复制阅读链接', 'Reading link copied'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('复制未完成，请重试。', 'Copy failed. Please retry.')),
          ),
        );
      }
    }
  }

  Future<void> _read(PublicShareReference reference) async {
    try {
      await widget.onRead?.call(reference);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开分享阅读。', 'Shared reading could not be opened.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _password() async {
    final callback = widget.onPassword;
    if (callback == null) {
      return;
    }
    try {
      final actual = await callback();
      if (mounted && actual != null) {
        setState(() => _protected = actual);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开密码设置。', 'Password settings could not be opened.'),
            ),
          ),
        );
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
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = _controller, receipt = c.receipt;
    final ready = c.phase == ShareSettingsPhase.ready;
    final observed = c.observedAfterUnknown;
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
          title: Text(t('分享设置', 'Sharing settings')),
          actions: [
            IconButton(
              tooltip: t('刷新状态', 'Refresh status'),
              onPressed: c.busy || c.uncertain ? null : c.load,
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
                  _heading(widget.target.title),
                  Text(
                    c.busy
                        ? t('正在核对或提交…', 'Checking or submitting…')
                        : c.uncertain
                        ? t('上次操作结果待确认', 'Previous result unconfirmed')
                        : c.published == null
                        ? t('发布状态尚未确认', 'Publication status unconfirmed')
                        : c.published!
                        ? t('已发布', 'Published')
                        : t('未发布', 'Unpublished'),
                  ),
                  const SizedBox(height: 8),
                  Text(t('仅管理当前资源。', 'Manage only this resource.')),
                ]),
                if (c.phase == ShareSettingsPhase.failed)
                  _card([
                    Text(
                      t(
                        '未能完成，请检查连接和当前资源权限。',
                        'The operation failed. Check the connection and your permission for this resource.',
                      ),
                    ),
                    TextButton(
                      onPressed: c.load,
                      child: Text(t('重试读取状态', 'Retry status read')),
                    ),
                  ]),
                if (c.uncertain)
                  _card([
                    _heading(t('结果待确认', 'Unconfirmed result')),
                    Text(
                      t(
                        '不会自动重发或重置令牌。布尔发布状态不能确定编辑链接的当前令牌。',
                        'No automatic resend or token reset. A boolean publication status cannot establish the current editing token.',
                      ),
                    ),
                    if (observed != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          observed
                              ? t(
                                  '最新读取：已发布，编辑令牌仍待核对。',
                                  'Latest read: published; editing token remains unconfirmed.',
                                )
                              : t(
                                  '最新读取：未发布。上次操作回执仍未知。',
                                  'Latest read: unpublished. The previous receipt remains unknown.',
                                ),
                        ),
                      ),
                    TextButton(
                      onPressed: c.inspectUnknown,
                      child: Text(t('核对发布状态', 'Check publication status')),
                    ),
                    OutlinedButton(
                      onPressed: _publish,
                      child: Text(
                        t(
                          '明确公开并重新获取链接',
                          'Explicitly publish and recover links',
                        ),
                      ),
                    ),
                  ]),
                if (!c.uncertain)
                  _card([
                    _heading(t('公开阅读链接', 'Public reading link')),
                    if (receipt == null) ...[
                      Text(
                        t(
                          '状态查询不返回链接。确认公开后才能获取真实链接。',
                          'Status reads do not return links. Confirm publication to obtain the actual link.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: c.busy ? null : _publish,
                        child: Text(t('公开并获取链接', 'Publish and obtain links')),
                      ),
                    ] else ...[
                      SelectableText(receipt.reference.canonicalUri.toString()),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: c.busy
                                ? null
                                : () => _copy(
                                    receipt.reference.canonicalUri.toString(),
                                  ),
                            child: Text(t('复制链接', 'Copy link')),
                          ),
                          if (widget.onRead != null)
                            OutlinedButton(
                              onPressed: c.busy
                                  ? null
                                  : () => _read(receipt.reference),
                              child: Text(t('打开阅读', 'Open reader')),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          '阅读链接不包含编辑令牌。',
                          'The reading link contains no editing token.',
                        ),
                      ),
                    ],
                  ]),
                _card([
                  _heading(t('编辑链接', 'Editing link')),
                  if (!widget.target.supportsEditing)
                    Text(
                      t(
                        '书籍整本不支持编辑链接。',
                        'Whole books do not support editing links.',
                      ),
                    )
                  else if (receipt == null)
                    Text(
                      t(
                        '收到发布回执后才能确认和管理编辑链接。',
                        'Obtain a publication receipt before confirming and managing editing links.',
                      ),
                    )
                  else ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t('允许持链接编辑正文', 'Allow link holders to edit the body'),
                      ),
                      value: receipt.editingEnabled,
                      onChanged: !ready
                          ? null
                          : (enabled) => _token(
                              enabled
                                  ? ShareTokenAction.enable
                                  : ShareTokenAction.disable,
                            ),
                    ),
                    Text(
                      t(
                        '持有编辑链接的人可以修改正文，请单独发送给可信任的人。',
                        'Anyone with the editing link may change the body. Send it separately to trusted people.',
                      ),
                    ),
                    if (receipt.editingEnabled) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: !ready
                                ? null
                                : () => _copy(
                                    receipt.editingUri!.toString(),
                                    capability: true,
                                  ),
                            child: Text(t('复制编辑链接', 'Copy editing link')),
                          ),
                          OutlinedButton(
                            onPressed: !ready
                                ? null
                                : () => _token(ShareTokenAction.reset),
                            child: Text(t('重置编辑链接', 'Reset editing link')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          '重置后旧编辑链接立即失效。',
                          'Resetting immediately invalidates the old editing link.',
                        ),
                      ),
                    ],
                  ],
                ]),
                if (widget.target.kind == PublicShareKind.blog)
                  _card([
                    _heading(t('内容保护', 'Body protection')),
                    Text(
                      _protected
                          ? t(
                              '当前正文设有密码。',
                              'This body currently has a password.',
                            )
                          : t(
                              '当前正文未设置密码。',
                              'This body currently has no password.',
                            ),
                    ),
                    if (widget.onPassword != null)
                      TextButton(
                        onPressed: c.busy || c.uncertain ? null : _password,
                        child: Text(t('管理内容密码', 'Manage body password')),
                      ),
                  ]),
                if (c.published == true || c.uncertain)
                  OutlinedButton(
                    onPressed: c.busy ? null : _unpublish,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: Text(t('停止分享', 'Stop sharing')),
                  ),
                const SizedBox(height: 12),
                Text(
                  t(
                    '编辑令牌只保留在本次会话，离开后清除。',
                    'Editing tokens stay in session memory and are cleared on leaving.',
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
