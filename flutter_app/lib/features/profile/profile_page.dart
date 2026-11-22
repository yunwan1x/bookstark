import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/profile_repository.dart';
import 'profile_edit_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.repository,
    required this.server,
    required this.onLanguage,
    required this.onLogout,
    this.english = false,
    this.onSecurity,
    this.onReminders,
    this.onAppearance,
    this.onApi,
    this.onTrash,
    this.onAdminDashboard,
    this.onAdminSettings,
    this.onAdminMembers,
    this.onAdminFriendLinks,
    this.onAdminShareComments,
    this.onAdminAssets,
    this.onNavigate,
  });
  final ValueChanged<String>? onNavigate;
  final ProfileRepository repository;
  final Uri server;
  final bool english;
  final Future<void> Function(bool) onLanguage;
  final Future<void> Function() onLogout;
  final Future<void> Function()? onSecurity,
      onReminders,
      onAppearance,
      onApi,
      onTrash,
      onAdminDashboard,
      onAdminSettings,
      onAdminMembers,
      onAdminFriendLinks,
      onAdminShareComments,
      onAdminAssets;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  MemberProfile? _profile;
  bool _loading = false, _working = false;
  String? _error;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _profile = null;
    });
    try {
      final actual = await widget.repository.read();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _profile = actual);
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _error = t(
          '无法读取当前账号资料，请检查登录状态和连接。',
          'Could not read this account. Check your session and connection.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      await action();
      if (mounted && reload) {
        await _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('操作未完成，请重试。', 'The action failed. Please retry.')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _edit(MemberProfile profile) async => _open(() async {
    await Navigator.push<MemberProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditPage(
          repository: widget.repository,
          profile: profile,
          english: widget.english,
        ),
      ),
    );
  });
  Future<void> _language() async {
    if (_working) {
      return;
    }
    final selected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(t('应用语言', 'App language')), onTap: null),
              ListTile(
                title: const Text('中文'),
                trailing: !widget.english ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                title: const Text('English'),
                trailing: widget.english ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == widget.english || !mounted) {
      return;
    }
    await _open(() => widget.onLanguage(selected));
  }

  Future<void> _logout() async {
    if (_working) {
      return;
    }
    final confirmed = await showDialog<bool>(
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
                  t('退出服务器空间？', 'Leave the server space?'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    '清除当前设备保存的服务器会话并停止播放。本地数据库和附件会保留。',
                    'Clear this device’s saved server session and stop playback. Local databases and attachments are retained.',
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
                      child: Text(t('确认退出', 'Leave server')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _open(widget.onLogout, reload: false);
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
  Widget _row(
    IconData icon,
    String title,
    Future<void> Function() callback, {
    String? subtitle,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: _working ? null : () => _open(callback),
  );
  String _module(String value) => switch (value) {
    'home' => t('首页', 'Home'),
    'notes' => t('笔记', 'Notes'),
    'tasks' => t('待办', 'Tasks'),
    'articles' => t('文章', 'Articles'),
    'books' => t('书籍', 'Books'),
    'bookmarks' => t('书签', 'Bookmarks'),
    'nav' => t('导航', 'Navigation'),
    'search' => t('搜索', 'Search'),
    _ => value,
  };
  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final server = widget.server;
    final serverLabel =
        '${server.host}${server.hasPort ? ':${server.port}' : ''}${server.path}';
    return Scaffold(
      backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
      appBar: AppBar(
        title: Text(t('我的', 'My account')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: t('刷新', 'Refresh'),
            onPressed: _loading || _working ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.onNavigate == null
          ? null
          : BottomNavigationBar(
              currentIndex: 4,
              type: BottomNavigationBarType.fixed,
              onTap: _working
                  ? null
                  : (index) {
                      if (index != 4) {
                        widget.onNavigate!(
                          [
                            'home',
                            'notes',
                            'bookmarks',
                            'files',
                            'profile',
                          ][index],
                        );
                      }
                    },
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.home_outlined),
                  label: t('首页', 'Home'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.menu_book_outlined),
                  label: t('知识', 'Knowledge'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.bookmark_border),
                  label: t('收藏', 'Bookmarks'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.folder_outlined),
                  label: t('文件', 'Files'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.person),
                  label: t('我的', 'My account'),
                ),
              ],
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                _card([
                  Text(_error!),
                  TextButton(onPressed: _load, child: Text(t('重试', 'Retry'))),
                ]),
              if (profile != null) ...[
                _card([
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xff0b4eff),
                        foregroundColor: Colors.white,
                        child: Text(
                          String.fromCharCode(
                            profile.account.runes.first,
                          ).toUpperCase(),
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                      Text(
                        profile.account,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Chip(
                        label: Text(
                          profile.role == 0
                              ? t('管理员', 'Administrator')
                              : t('普通账号', 'Member'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('${t('当前服务器', 'Server')} $serverLabel'),
                ]),
                _card([
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        t('个人资料', 'Profile'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: _working ? null : () => _edit(profile),
                        child: Text(t('编辑资料', 'Edit profile')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${t('邮箱', 'Email')}  ${profile.email.isEmpty ? t('未设置', 'Not set') : profile.email}',
                  ),
                  const Divider(height: 32),
                  Text(
                    '${t('默认打开', 'Default module')}  ${_module(profile.defaultHome)}',
                  ),
                ]),
                if ([
                  widget.onSecurity,
                  widget.onReminders,
                  widget.onAppearance,
                  widget.onApi,
                  widget.onTrash,
                ].any((callback) => callback != null))
                  _card([
                    if (widget.onSecurity != null)
                      _row(
                        Icons.lock_outline,
                        t('账户安全', 'Account security'),
                        widget.onSecurity!,
                      ),
                    if (widget.onReminders != null)
                      _row(
                        Icons.mail_outline,
                        t('邮件提醒', 'Email reminders'),
                        widget.onReminders!,
                        subtitle: t('待办提醒', 'Task reminders'),
                      ),
                    if (widget.onAppearance != null)
                      _row(
                        Icons.palette_outlined,
                        t('外观与背景', 'Appearance and background'),
                        widget.onAppearance!,
                      ),
                    if (widget.onApi != null)
                      _row(
                        Icons.key_outlined,
                        t('API与应用密码', 'API and app passwords'),
                        widget.onApi!,
                      ),
                    if (widget.onTrash != null)
                      _row(
                        Icons.delete_outline,
                        t('回收站', 'Trash'),
                        widget.onTrash!,
                      ),
                  ]),
              ],
              if (_profile?.role == 0 && widget.onAdminDashboard != null)
                _card([
                  _row(
                    Icons.query_stats,
                    t('访问统计', 'Dashboard'),
                    widget.onAdminDashboard!,
                    subtitle: t('管理员 · 服务器空间', 'Administrator · Server space'),
                  ),
                ]),
              if (_profile?.role == 0 && widget.onAdminSettings != null)
                _card([
                  _row(
                    Icons.settings_outlined,
                    t('系统设置', 'System settings'),
                    widget.onAdminSettings!,
                    subtitle: t(
                      '管理员 · 当前服务器',
                      'Administrator · Current server',
                    ),
                  ),
                ]),
              if (_profile?.role == 0 && widget.onAdminMembers != null)
                _card([
                  _row(
                    Icons.people_outline,
                    t('用户管理', 'User management'),
                    widget.onAdminMembers!,
                    subtitle: t(
                      '管理员 · 当前服务器',
                      'Administrator · Current server',
                    ),
                  ),
                ]),
              if (_profile?.role == 0 && widget.onAdminFriendLinks != null)
                _card([
                  _row(
                    Icons.link_outlined,
                    t('友情链接', 'Friend links'),
                    widget.onAdminFriendLinks!,
                    subtitle: t(
                      '管理员 · 当前服务器',
                      'Administrator · Current server',
                    ),
                  ),
                ]),
              if (_profile?.role == 0 && widget.onAdminShareComments != null)
                _card([
                  _row(
                    Icons.forum_outlined,
                    t('评论管理', 'Comment management'),
                    widget.onAdminShareComments!,
                    subtitle: t(
                      '管理员 · 当前服务器',
                      'Administrator · Current server',
                    ),
                  ),
                ]),
              if (_profile?.role == 0 && widget.onAdminAssets != null)
                _card([
                  _row(
                    Icons.dns_outlined,
                    t('资产管理', 'Asset management'),
                    widget.onAdminAssets!,
                    subtitle: t(
                      '管理员 · 当前服务器',
                      'Administrator · Current server',
                    ),
                  ),
                ]),
              _card([
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language),
                  title: Text(t('应用语言', 'App language')),
                  subtitle: Text(widget.english ? 'English' : '中文'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _working ? null : _language,
                ),
              ]),
              OutlinedButton(
                onPressed: _working ? null : _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(t('退出服务器空间', 'Leave server space')),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '本地资料会保留，可切换到本地空间。',
                  'Local data stays available in the local space.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
