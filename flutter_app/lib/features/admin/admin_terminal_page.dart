import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'admin_asset_models.dart';
import 'admin_asset_secure_window.dart';
import 'admin_terminal_access.dart';
import 'admin_terminal_session_access.dart';
import 'admin_terminal_browser.dart';
import 'admin_terminal_controller.dart';
import 'admin_terminal_protocol.dart';
import 'admin_terminal_transport.dart';
import 'admin_assets_scope.dart';
import 'admin_docker_widgets.dart';

class AdminTerminalPage extends StatefulWidget {
  const AdminTerminalPage({
    super.key,
    required this.scope,
    required this.host,
    required this.onReturn,
    this.english = false,
    this.secureWindow,
    this.transportFactory,
    this.sessionAccess,
    this.containerName,
    this.containerId,
  });
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final VoidCallback onReturn;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  final TerminalTransport Function()? transportFactory;
  final AdminTerminalSessionAccess? sessionAccess;
  final String? containerName, containerId;
  @override
  State<AdminTerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<AdminTerminalPage>
    with WidgetsBindingObserver {
  late final AdminTerminalSessionAccess _access;
  late final AdminTerminalController c;
  late final AdminAssetWindowGuard _secure;
  var _browser = GlobalKey<AdminTerminalBrowserState>();
  final _paste = ValueNotifier<String?>(null);
  bool _secureReady = false,
      _secureFailed = false,
      _dialogOpen = false,
      _leaving = false,
      _containerReviewOpen = false;
  int? _bodyGeneration;
  DialogRoute<dynamic>? _ownedDialog;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _access =
        widget.sessionAccess ?? AdminTerminalAccess(widget.scope, widget.host);
    c = widget.scope.own(
      _access.create(transportFactory: widget.transportFactory),
    );
    c.addListener(_changed);
    _secure = widget.secureWindow ?? AdminAssetSecureWindow();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableSecure());
  }

  Future<void> _enableSecure() async {
    try {
      await _secure.acquire();
      if (mounted) {
        setState(() {
          _secureReady = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _secureFailed = true;
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (c.phase == TerminalPhase.connecting &&
        _bodyGeneration != c.generation) {
      _bodyGeneration = c.generation;
      _browser = GlobalKey<AdminTerminalBrowserState>();
    }
    if ({
      TerminalPhase.review,
      TerminalPhase.verifying,
      TerminalPhase.background,
      TerminalPhase.revoked,
    }.contains(c.phase)) {
      _bodyGeneration = null;
      _paste.value = null;
    }
    setState(() {});
    if (c.phase == TerminalPhase.revoked) {
      scheduleMicrotask(() {
        if (mounted) widget.scope.close();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _paste.value = null;
      _containerReviewOpen = false;
      c.background();
      final dialog = _ownedDialog;
      final owner = dialog?.navigator;
      if (dialog != null && dialog.isActive && owner != null && owner.mounted) {
        owner.removeRoute(dialog);
      }
    }
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    if (view.viewInsets.bottom <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _browser.currentContext;
      if (mounted && target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: 1));
      }
    });
  }

  Future<T?> _showOwnedDialog<T>(WidgetBuilder builder) async {
    final owner = Navigator.of(
      context,
      rootNavigator: widget.containerId == null,
    );
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: owner.context),
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _ownedDialog = route;
    try {
      return await owner.push<T>(route);
    } finally {
      if (identical(_ownedDialog, route)) _ownedDialog = null;
    }
  }

  Future<void> _close({bool leave = false}) async {
    if (_leaving || _dialogOpen) return;
    if (leave &&
        widget.containerId != null &&
        _containerReviewOpen &&
        !c.hasSession) {
      setState(() => _containerReviewOpen = false);
      return;
    }
    if (c.hasSession) {
      _dialogOpen = true;
      final confirmed = await _showOwnedDialog<bool>(
        (context) => AlertDialog(
          title: Text(t('断开终端？', 'Disconnect terminal?')),
          content: SingleChildScrollView(
            child: Text(
              t(
                '会话将关闭，重新连接不会重发已输入的命令。',
                'The session will close. Reconnecting never replays previous input.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续会话', 'Keep session')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('断开', 'Disconnect')),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (!mounted || confirmed != true) return;
    }
    c.disconnect();
    setState(() {
      _bodyGeneration = null;
      _containerReviewOpen = false;
    });
    if (leave) {
      _leaving = true;
      widget.onReturn();
    }
  }

  Future<void> _pasteInput() async {
    if (!c.canInput || _dialogOpen) return;
    final held = c.generation;
    ClipboardData? clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !c.canInput || c.generation != held) {
      clipboard = null;
      return;
    }
    _paste.value = clipboard?.text;
    clipboard = null;
    final allowed = _paste.value != null && terminalPasteAllowed(_paste.value!);
    _dialogOpen = true;
    await _showOwnedDialog<void>(
      (context) => ValueListenableBuilder<String?>(
        valueListenable: _paste,
        builder: (context, text, _) => AlertDialog(
          title: Text(t('确认发送粘贴内容', 'Confirm pasted input')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  !allowed
                      ? t(
                          '内容为空、过长或含不支持的控制字符，不能发送。',
                          'Empty, oversized or unsupported control characters. Cannot send.',
                        )
                      : t(
                          '保留原有换行，不追加回车；多行内容可能立即执行。',
                          'Original line endings are preserved. No return is added. Multiple lines may execute immediately.',
                        ),
                ),
                const SizedBox(height: 12),
                if (allowed && text != null)
                  Text(text, style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _paste.value = null;
                Navigator.pop(context);
              },
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed:
                  allowed && text != null && c.canInput && c.generation == held
                  ? () {
                      c.input(held, text);
                      _paste.value = null;
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(t('发送一次', 'Send once')),
            ),
          ],
        ),
      ),
    );
    _dialogOpen = false;
    if (mounted) _paste.value = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    widget.scope.release(c);
    _access.dispose();
    _ownedDialog = null;
    _paste.value = null;
    _paste.dispose();
    unawaited(_secure.close());
    super.dispose();
  }

  String get _status => switch (c.phase) {
    TerminalPhase.review => t('连接前核对', 'Review connection'),
    TerminalPhase.verifying => t('正在核对身份与主机', 'Verifying identity and host'),
    TerminalPhase.connecting =>
      widget.containerId == null
          ? t('正在连接 SSH', 'Connecting SSH')
          : t('正在连接容器', 'Connecting container'),
    TerminalPhase.ready => t('已连接', 'Connected'),
    TerminalPhase.disconnected => t('已断开', 'Disconnected'),
    TerminalPhase.background => t(
      '后台已关闭，请重新连接',
      'Closed in background. Reconnect.',
    ),
    TerminalPhase.revoked => t('管理员会话已失效', 'Administrator session expired'),
  };
  Widget _notice(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff3ca) : const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline : Icons.info_outline,
          color: warning ? const Color(0xffa97200) : const Color(0xff0b57ee),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [Text(label), Text(value)],
          ),
        ),
      ],
    ),
  );
  bool get _canConnect =>
      _secureReady &&
      !c.connecting &&
      c.phase != TerminalPhase.revoked &&
      c.failure != TerminalFailure.targetChanged;
  void _connectOrReview() {
    if (!_canConnect) return;
    if (widget.containerId != null && !_containerReviewOpen) {
      setState(() {
        _containerReviewOpen = true;
        _bodyGeneration = null;
      });
    } else {
      unawaited(c.connect());
    }
  }

  Widget _connectButton({bool reconnect = false}) => Padding(
    padding: const EdgeInsets.all(16),
    child: FilledButton(
      onPressed: _canConnect ? _connectOrReview : null,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff0b57ee),
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        reconnect ? t('重新连接', 'Reconnect') : t('连接终端', 'Connect terminal'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
  Widget _containerIdle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Flexible(
        flex: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .38,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DockerTargetStrip(
                  key: const ValueKey('docker-terminal-target'),
                  title:
                      '${widget.containerName ?? widget.host.name} · SSH #${widget.host.id}',
                  icon: Icons.view_in_ar_outlined,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final status = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffe1e5e9),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 8,
                            color: Color(0xff64748b),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              t('未连接', 'Not connected'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff4b5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    final connect = FilledButton.icon(
                      onPressed: _canConnect ? _connectOrReview : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff0b57ee),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.terminal, size: 20),
                      label: Text(t('连接终端', 'Connect terminal')),
                    );
                    if (constraints.maxWidth < 360 &&
                        MediaQuery.textScalerOf(context).scale(14) > 18) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(alignment: Alignment.centerLeft, child: status),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: connect,
                          ),
                        ],
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: status),
                        const SizedBox(width: 8),
                        connect,
                      ],
                    );
                  },
                ),
                if (c.failure == TerminalFailure.targetChanged) ...[
                  const SizedBox(height: 12),
                  _notice(
                    t(
                      '目标资料已变化，请返回重新读取后再连接。',
                      'The target changed. Return and read it again before connecting.',
                    ),
                    warning: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: Container(
          key: const ValueKey('docker-terminal-idle-panel'),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xff0c192e),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              t('尚未连接', 'Not connected'),
              style: const TextStyle(color: Color(0xffcbd5e1)),
            ),
          ),
        ),
      ),
      Flexible(
        flex: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .28,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final buttons = [
                      for (final item in [
                        (Icons.keyboard_outlined, t('键盘', 'Keyboard')),
                        (Icons.content_paste, t('粘贴', 'Paste')),
                        (Icons.link_off, t('断开', 'Disconnect')),
                      ])
                        OutlinedButton.icon(
                          onPressed: null,
                          style: const ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              Color(0xffe5e7eb),
                            ),
                            side: WidgetStatePropertyAll(BorderSide.none),
                            padding: WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            ),
                          ),
                          icon: Icon(item.$1, size: 18),
                          label: Text(item.$2),
                        ),
                    ];
                    if (MediaQuery.textScalerOf(context).scale(14) > 18 ||
                        constraints.maxWidth < 330) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < buttons.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              buttons[i],
                            ],
                          ],
                        ),
                      );
                    }
                    return Row(
                      children: [
                        for (var i = 0; i < buttons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: buttons[i]),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
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
                        t(
                          '切到后台或退出将断开连接。',
                          'Moving to the background or leaving closes the connection.',
                        ),
                        style: const TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  Widget _review() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t('服务器空间', 'Server workspace'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xffeaf2ff),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dns_outlined, color: Color(0xff0b57ee)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.host.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _row(
                    Icons.tag,
                    t('主机 ID', 'Host ID'),
                    widget.host.id.toString(),
                  ),
                  const Divider(height: 1),
                  _row(
                    Icons.terminal,
                    '',
                    '${widget.host.username}@${widget.host.host}:${widget.host.port}',
                  ),
                  const Divider(height: 1),
                  if (widget.containerId != null) ...[
                    _row(
                      Icons.view_in_ar,
                      t('容器', 'Container'),
                      widget.containerName ?? '',
                    ),
                    _row(
                      Icons.fingerprint,
                      t('完整 ID', 'Full ID'),
                      widget.containerId!,
                    ),
                    const Divider(height: 1),
                  ],
                  _row(
                    Icons.code,
                    'Shell',
                    widget.containerId == null ? widget.host.shell : '/bin/sh',
                  ),
                  const Divider(height: 1),
                  _row(
                    Icons.key_outlined,
                    t('凭据', 'Credential'),
                    widget.host.credentialId == 0
                        ? t('旧式内联凭据', 'Legacy inline credential')
                        : '${widget.host.credentialName} #${widget.host.credentialId}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _notice(
              t(
                '连接后可执行远程命令。断线不会自动重连；退出或进入后台会关闭会话。',
                'Connected input executes on the remote host. No automatic reconnect. Leaving or backgrounding closes the session.',
              ),
            ),
            if (c.phase != TerminalPhase.review) ...[
              const SizedBox(height: 12),
              Text(_status, key: const ValueKey('terminal-status')),
            ],
            if (c.failure != null) ...[
              const SizedBox(height: 12),
              _notice(
                c.failure == TerminalFailure.targetChanged
                    ? t(
                        '主机资料已变化，请返回刷新后重新核对。',
                        'Host details changed. Return, refresh and review again.',
                      )
                    : t(
                        '连接失败或已断开，请核对后重试。',
                        'Connection failed or disconnected. Review before retrying.',
                      ),
                warning: true,
              ),
            ],
          ],
        ),
      ),
      _connectButton(
        reconnect: {
          TerminalPhase.disconnected,
          TerminalPhase.background,
        }.contains(c.phase),
      ),
    ],
  );
  Widget _session() => LayoutBuilder(
    builder: (context, constraints) {
      final minimum = 280 + MediaQuery.textScalerOf(context).scale(14) * 2;
      final content = _sessionContent();
      if (constraints.maxHeight < minimum) {
        return SingleChildScrollView(
          key: const ValueKey('terminal-compact-scroll'),
          child: SizedBox(height: minimum, child: content),
        );
      }
      return content;
    },
  );
  Widget _sessionContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xffeaf2ff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.circle,
              size: 12,
              color: c.canInput
                  ? const Color(0xff239844)
                  : const Color(0xff77808d),
            ),
            Text(
              _status,
              key: const ValueKey('terminal-status'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: c.canInput ? const Color(0xff237d3e) : null,
              ),
            ),
            Text(
              '${widget.host.username} · ${t('主机', 'Host')} #${widget.host.id}',
            ),
          ],
        ),
      ),
      if (c.phase == TerminalPhase.disconnected)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _notice(
            t(
              '会话已结束。重新连接会创建新会话，不会重发命令。',
              'Session ended. Reconnecting starts a new session and never replays commands.',
            ),
            warning: true,
          ),
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(
              color: const Color(0xff080b10),
              child: AdminTerminalBrowser(
                key: _browser,
                controller: c,
                generation: _bodyGeneration!,
                scrollback: _access.scrollbackLines,
                english: widget.english,
              ),
            ),
          ),
        ),
      ),
      if (c.phase == TerminalPhase.disconnected)
        _connectButton(reconnect: true)
      else ...[
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xffeaf2ff),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  ('Esc', 'escape'),
                  ('Tab', 'tab'),
                  ('Ctrl+C', 'interrupt'),
                  ('↑', 'up'),
                  ('↓', 'down'),
                  ('←', 'left'),
                  ('→', 'right'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: const Color(0xffdce7f5),
                        foregroundColor: const Color(0xff0c192e),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: c.canInput
                          ? () => unawaited(
                              _browser.currentState?.shortcut(entry.$2),
                            )
                          : null,
                      child: Text(entry.$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: c.canInput
                    ? () => unawaited(_browser.currentState?.focus())
                    : null,
                icon: const Icon(Icons.keyboard_outlined),
                label: Text(t('键盘', 'Keyboard')),
              ),
              TextButton.icon(
                onPressed: c.canInput ? () => unawaited(_pasteInput()) : null,
                icon: const Icon(Icons.content_paste),
                label: Text(t('粘贴', 'Paste')),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_close()),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffbf2637),
                ),
                icon: const Icon(Icons.link_off),
                label: Text(t('断开', 'Disconnect')),
              ),
            ],
          ),
        ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close(leave: true));
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _bodyGeneration == null
              ? (widget.containerId == null
                    ? t('远程终端', 'Remote terminal')
                    : t('容器终端', 'Container terminal'))
              : (widget.containerName ?? widget.host.name),
        ),
        leading: IconButton(
          onPressed: () => unawaited(_close(leave: true)),
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: !_secureReady
            ? Center(
                child: _secureFailed
                    ? Text(
                        t(
                          '无法启用安全窗口，终端未开启。',
                          'Secure window unavailable. Terminal remains closed.',
                        ),
                      )
                    : const CircularProgressIndicator(),
              )
            : _bodyGeneration == null
            ? (widget.containerId != null && !_containerReviewOpen
                  ? _containerIdle()
                  : _review())
            : _session(),
      ),
    ),
  );
}
