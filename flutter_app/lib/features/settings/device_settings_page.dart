import 'package:flutter/material.dart';
import '../../core/owned_download_cache.dart';
import 'settings_connection_controller.dart';

const _purple = Color(0xff6530ad);
const _canvas = Color(0xfffcfaff);
const _ink = Color(0xff172033);
const _border = Color(0xffe5d9f5);

/// Opens from the home route, after any editor has completed its leave barrier.
/// Destination is returned to the app, which changes the real workspace.
class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({
    super.key,
    required this.connection,
    required this.english,
    required this.onLanguage,
    required this.prepareSwitch,
    required this.cache,
    required this.canBackup,
    this.onLocalModel,
  });
  final SettingsConnectionController connection;
  final bool english, canBackup;
  final Future<bool> Function() onLanguage;
  final Future<void> Function() prepareSwitch;
  final OwnedDownloadCache cache;
  final Future<void> Function()? onLocalModel;
  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  late bool english = widget.english;
  String t(String zh, String en) => english ? en : zh;
  bool _languageBusy = false;
  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.connection.removeListener(_changed);
    widget.connection.dispose();
    super.dispose();
  }

  void _finish(String destination) {
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((current) => current == route);
    Navigator.of(context).pop(destination);
  }

  Future<void> _connections() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ConnectionPage(
        state: widget.connection,
        english: english,
        prepareSwitch: widget.prepareSwitch,
        onDestination: _finish,
      ),
    ),
  );
  Future<void> _language() async {
    if (_languageBusy) return;
    setState(() => _languageBusy = true);
    try {
      final next = await widget.onLanguage();
      if (mounted) setState(() => english = next);
    } catch (_) {
      if (mounted) {
        _notice(
          context,
          t('语言未能保存，请重试。', 'Language could not be saved. Retry.'),
        );
      }
    } finally {
      if (mounted) setState(() => _languageBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Shell(
    title: t('设置', 'Settings'),
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Card(
          color: const Color(0xfff0e5ff),
          child: _Row(
            icon: Icons.layers_outlined,
            title: t('当前空间', 'Current space'),
            emphasized: true,
            subtitle: widget.connection.local
                ? t('本地空间\n数据保存在此设备', 'Local space\nData stays on this device')
                : t('服务器空间', 'Server space'),
            onTap: _connections,
          ),
        ),
        _Section(t('连接与离线', 'Connection & offline')),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: Icons.link,
                title: t('连接管理', 'Connections'),
                onTap: _connections,
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.wifi_outlined,
                title: t('网络状态', 'Network status'),
                value: _status(widget.connection.state, english),
                valueBadge: true,
                valueWarning: _attention(widget.connection.state),
                onTap: _connections,
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.description_outlined,
                title: t('切换前保存草稿', 'Drafts before switching'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ModalTheme(
                    child: AlertDialog(
                      title: Text(t('切换前保存草稿', 'Drafts before switching')),
                      content: Text(
                        t(
                          '编辑器会在离开前保存工作副本。未知提交需要显式核对，切换不会自动重发写入。',
                          'Editors preserve working copies before leaving. Uncertain saves require explicit review; switching does not replay writes.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t('知道了', 'Got it')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.connection.local && widget.onLocalModel != null) ...[
          _Section(t('本地 AI', 'Local AI')),
          _Card(
            child: _Row(
              icon: Icons.smart_toy_outlined,
              title: t('本地模型配置', 'Local model settings'),
              subtitle: t(
                '当前设备的模型服务与密钥',
                'Model service and credential on this device',
              ),
              onTap: widget.onLocalModel,
            ),
          ),
        ],
        _Section(t('显示', 'Display')),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: Icons.language,
                title: t('语言', 'Language'),
                value: english ? 'English' : '简体中文',
                onTap: _languageBusy ? null : _language,
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.light_mode_outlined,
                title: t('应用外观', 'Appearance'),
                value: t('浅色', 'Light'),
              ),
            ],
          ),
        ),
        _Section(t('存储与维护', 'Storage & maintenance')),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: Icons.cleaning_services_outlined,
                title: t('缓存管理', 'Cache management'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _CachePage(cache: widget.cache, english: english),
                  ),
                ),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.storage_outlined,
                title: t('本地备份与恢复', 'Local backup & recovery'),
                subtitle: widget.canBackup
                    ? null
                    : t('进入本地空间后管理', 'Manage from local space'),
                onTap: widget.canBackup ? () => _finish('local-backup') : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t(
            '本地内容与附件不会随缓存清理删除。',
            'Cache cleanup preserves local content and attachments.',
          ),
          style: const TextStyle(color: Color(0xff64606c)),
        ),
      ],
    ),
  );
}

class _ConnectionPage extends StatefulWidget {
  const _ConnectionPage({
    required this.state,
    required this.english,
    required this.prepareSwitch,
    required this.onDestination,
  });
  final SettingsConnectionController state;
  final bool english;
  final Future<void> Function() prepareSwitch;
  final void Function(String) onDestination;
  @override
  State<_ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<_ConnectionPage> {
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  Future<void> _enter(String destination) async {
    try {
      await widget.state.switchSpace(
        prepare: widget.prepareSwitch,
        enter: () async {
          widget.onDestination(destination);
        },
      );
    } catch (_) {
      if (mounted) {
        _notice(
          context,
          t(
            '切换尚未完成，请重试。草稿已保留。',
            'Switch did not complete. Drafts are retained; retry.',
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => _ModalTheme(
        child: AlertDialog(
          title: Text(t('退出当前账号？', 'Sign out of this account?')),
          content: Text(
            t(
              '本地内容、附件与草稿保留。再次连接需要登录。',
              'Local content, attachments and drafts stay on this device. Connecting again requires sign-in.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('退出登录', 'Sign out')),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) await _enter('settings-logout');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return _Shell(
      title: t('连接管理', 'Connections'),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if ({
                  ConnectionCheckState.unavailable,
                  ConnectionCheckState.loginExpired,
                  ConnectionCheckState.accessDenied,
                }.contains(state.state)) ...[
                  _Card(
                    color: const Color(0xfffff1d7),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xffa14500),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  state.state ==
                                          ConnectionCheckState.loginExpired
                                      ? t('登录已失效', 'Sign-in expired')
                                      : state.state ==
                                            ConnectionCheckState.accessDenied
                                      ? t('当前账号无法访问', 'Access denied')
                                      : t(
                                          '当前服务器暂时无法访问',
                                          'Server is unavailable',
                                        ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t(
                                    '可重试连接，或进入本地空间。',
                                    'Retry the connection or enter local space.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (state.displayAddress != null) ...[
                  _Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('当前连接', 'Current connection'),
                            style: const TextStyle(
                              color: _purple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _ConnectionIdentity(
                            icon: Icons.menu_book_outlined,
                            title: t('服务器空间', 'Server space'),
                            subtitle: state.displayAddress!,
                            selectable: true,
                            status: Semantics(
                              container: true,
                              liveRegion: true,
                              child: _Badge(
                                _status(state.state, widget.english),
                                warning: _attention(state.state),
                              ),
                            ),
                          ),
                          const Divider(height: 28),
                          _ConnectionAction(
                            onPressed: state.busy || state.local
                                ? null
                                : state.check,
                            label: state.state == ConnectionCheckState.checking
                                ? t('检查中…', 'Checking…')
                                : t('检查连接', 'Check connection'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('本地空间', 'Local space'),
                          style: const TextStyle(
                            color: _purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ConnectionIdentity(
                          icon: Icons.computer_outlined,
                          title: t('本地空间', 'Local space'),
                          subtitle: t('无需网络', 'No network required'),
                        ),
                        const Divider(height: 28),
                        _ConnectionAction(
                          onPressed: state.busy || state.local
                              ? null
                              : () => _enter('settings-local'),
                          label: state.local
                              ? t('当前空间', 'Current space')
                              : t('进入本地空间', 'Enter local space'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!state.local)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton(
                      onPressed: state.busy ? null : _logout,
                      child: Text(t('退出当前账号', 'Sign out of current account')),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.busy ? null : () => _enter('space'),
                  child: Text(t('连接其他服务器', 'Connect another server')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionIdentity extends StatelessWidget {
  const _ConnectionIdentity({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selectable = false,
    this.status,
  });
  final IconData icon;
  final String title, subtitle;
  final bool selectable;
  final Widget? status;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(16) > 20;
      return Row(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: _purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (selectable)
                  Semantics(
                    container: true,
                    child: SelectableText(
                      subtitle,
                      style: const TextStyle(fontSize: 14),
                    ),
                  )
                else
                  Text(subtitle, style: const TextStyle(fontSize: 14)),
                if (stacked && status != null) ...[
                  const SizedBox(height: 8),
                  status!,
                ],
              ],
            ),
          ),
          if (!stacked && status != null) ...[
            const SizedBox(width: 12),
            status!,
          ],
        ],
      );
    },
  );
}

class _ConnectionAction extends StatelessWidget {
  const _ConnectionAction({required this.onPressed, required this.label});
  final VoidCallback? onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(16) > 20;
      return Center(
        child: SizedBox(
          width: large
              ? constraints.maxWidth
              : constraints.maxWidth.clamp(0, 200).toDouble(),
          child: OutlinedButton(onPressed: onPressed, child: Text(label)),
        ),
      );
    },
  );
}

class _CachePage extends StatefulWidget {
  const _CachePage({required this.cache, required this.english});
  final OwnedDownloadCache cache;
  final bool english;
  @override
  State<_CachePage> createState() => _CachePageState();
}

class _CachePageState extends State<_CachePage> {
  OwnedCacheResult? _result;
  bool _busy = true;
  String? _error, _noticeText;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool clear = false}) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final removed = clear ? await widget.cache.clear() : null;
      final result = await widget.cache.inspect();
      if (!mounted) return;
      setState(() {
        _result = result;
        _noticeText = removed == null
            ? null
            : removed.failedEntries > 0
            ? t('部分缓存未能清理，请重试。', 'Some cache could not be cleared. Retry.')
            : t(
                '已清理 ${removed.removedBytes} 字节。',
                'Cleared ${removed.removedBytes} bytes.',
              );
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '缓存统计或清理未完成，请重试。',
            'Cache operation did not complete. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || (_result?.eligibleEntries ?? 0) == 0) return;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ModalTheme(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('清理缓存？', 'Clear cache?'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    '仅清理已结束下载的临时文件。本地内容、附件与草稿保留。',
                    'Only temporary files from finished downloads are cleared. Local content, attachments and drafts are retained.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 302 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20;
                    final cancel = OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('取消', 'Cancel')),
                    );
                    final clear = FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('清理', 'Clear')),
                    );
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancel,
                              const SizedBox(height: 12),
                              clear,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: cancel),
                              const SizedBox(width: 12),
                              Expanded(child: clear),
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (yes == true && mounted) await _load(clear: true);
  }

  @override
  Widget build(BuildContext context) => _Shell(
    title: t('缓存管理', 'Cache management'),
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cleaning_services_outlined,
                      color: _purple,
                      size: 44,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('可清理缓存', 'Clearable cache'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _busy
                                ? t('正在统计…', 'Calculating…')
                                : _result == null
                                ? t('暂时无法统计', 'Unavailable')
                                : '${_result!.eligibleBytes} B',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Text(
                  t(
                    '仅包含已结束下载留下的临时文件。',
                    'Only temporary files left by finished downloads are included.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: Icons.shield_outlined,
                title: t('受保护的数据', 'Protected data'),
              ),
              const Divider(height: 1),
              for (final item in [
                (
                  Icons.description_outlined,
                  t('本地笔记与附件', 'Local notes & attachments'),
                ),
                (Icons.edit_outlined, t('草稿与恢复记录', 'Drafts & recovery')),
                (Icons.key_outlined, t('登录与密钥', 'Sign-in & keys')),
              ])
                _Row(icon: item.$1, title: item.$2, value: t('保留', 'Retained')),
            ],
          ),
        ),
        if (_result case final value?) ...[
          const SizedBox(height: 16),
          Text(
            t(
              '使用中的下载：${value.activeEntries}；保留的未识别项目：${value.skippedEntries}。',
              'Active downloads: ${value.activeEntries}; retained unrecognized entries: ${value.skippedEntries}.',
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!),
          ),
        if (_noticeText != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_noticeText!),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || (_result?.eligibleEntries ?? 0) == 0
              ? null
              : _confirm,
          child: Text(
            (_result?.eligibleEntries ?? 0) == 0 && !_busy
                ? t('无需清理', 'Nothing to clear')
                : t('清理缓存', 'Clear cache'),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: Text(t('重新统计', 'Recalculate')),
        ),
      ],
    ),
  );
}

String _status(ConnectionCheckState state, bool english) => switch (state) {
  ConnectionCheckState.local => english ? 'No network required' : '无需网络',
  ConnectionCheckState.unverified => english ? 'Unverified' : '未验证',
  ConnectionCheckState.checking => english ? 'Checking…' : '检查中…',
  ConnectionCheckState.verified => english ? 'Verified' : '已验证',
  ConnectionCheckState.unavailable => english ? 'Connection failed' : '连接失败',
  ConnectionCheckState.loginExpired => english ? 'Sign-in expired' : '登录失效',
  ConnectionCheckState.accessDenied => english ? 'Access denied' : '无法访问',
};
void _notice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: _theme(context),
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: color,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _border),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        color: _purple,
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.valueBadge = false,
    this.valueWarning = false,
    this.emphasized = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  final bool valueBadge, valueWarning, emphasized;
  @override
  Widget build(BuildContext context) {
    final stacked =
        value != null && MediaQuery.textScalerOf(context).scale(16) > 20;
    final valueWidget = value == null
        ? null
        : valueBadge
        ? _Badge(value!, warning: valueWarning)
        : Text(
            value!,
            style: const TextStyle(color: Color(0xff64606c), fontSize: 14),
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Semantics(
        container: true,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Icon(icon, color: _purple, size: emphasized ? 32 : 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _ink,
                          fontSize: emphasized ? 18 : 16,
                          fontWeight: emphasized
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xff64606c),
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (stacked) ...[const SizedBox(height: 8), valueWidget!],
                    ],
                  ),
                ),
                if (valueWidget != null && !stacked) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .35,
                    ),
                    child: valueWidget,
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _attention(ConnectionCheckState state) => {
  ConnectionCheckState.unavailable,
  ConnectionCheckState.loginExpired,
  ConnectionCheckState.accessDenied,
}.contains(state);

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: warning ? const Color(0xffffedcb) : const Color(0xfff0e5ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: warning ? const Color(0xff9a4a00) : _purple,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

ThemeData _theme(BuildContext context) => Theme.of(context).copyWith(
  scaffoldBackgroundColor: _canvas,
  colorScheme: Theme.of(
    context,
  ).colorScheme.copyWith(primary: _purple, onPrimary: Colors.white),
  appBarTheme: const AppBarThemeData(
    backgroundColor: _canvas,
    foregroundColor: _ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: _ink,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      backgroundColor: _purple,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      foregroundColor: _purple,
      side: const BorderSide(color: _purple),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: _purple),
  ),
);

class _ModalTheme extends StatelessWidget {
  const _ModalTheme({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Theme(data: _theme(context), child: child);
}
