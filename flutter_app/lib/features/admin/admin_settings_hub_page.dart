import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_settings_scope.dart';

enum AdminSettingsDestination {
  general,
  content,
  registration,
  ai,
  mail,
  webDav,
  terminal,
}

class AdminSettingsHubPage extends StatefulWidget {
  const AdminSettingsHubPage({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onOpen,
  });
  final AdminSettingsHubController controller;
  final VoidCallback onReturn;
  final ValueChanged<AdminSettingsDestination> onOpen;
  @override
  State<AdminSettingsHubPage> createState() => _AdminSettingsHubPageState();
}

class _AdminSettingsHubPageState extends State<AdminSettingsHubPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminSettingsHubController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.verify();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  Widget _entry(
    AdminSettingsDestination destination,
    IconData icon,
    String title,
    String subtitle,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: const Color(0xffedf4ff),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        minTileHeight: 76,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xff1555ef),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xff0e1b3d),
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xff596780)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: c.ready && !c.loading ? () => widget.onOpen(destination) : null,
      ),
    ),
  );
  Widget _info(String title, {String? subtitle, bool primary = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: const Color(0xffedf4ff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Color(0xff1555ef)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primary ? const Color(0xff1555ef) : null,
                    ),
                  ),
                  if (subtitle != null) Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      );
  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      value,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) widget.onReturn();
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: adminSettingsAppBar(
        context,
        title: t('系统设置'),
        subtitle: t('管理员 · 服务器空间'),
        dirty: false,
        onReturn: widget.onReturn,
        backLabel: t('返回'),
        actions: [
          IconButton(
            tooltip: t('刷新管理员设置'),
            onPressed: c.loading || c.revoked ? null : c.verify,
            icon: const Icon(Icons.refresh, color: Color(0xff1555ef)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.loading) const LinearProgressIndicator(),
          if (c.message != null) ...[
            Semantics(liveRegion: true, child: Text(t(c.message!))),
            if (!c.revoked)
              OutlinedButton(onPressed: c.verify, child: Text(t('重新读取'))),
          ],
          _info(t('修改后需在对应页面保存'), primary: true),
          _heading(t('基础配置')),
          _entry(
            AdminSettingsDestination.general,
            Icons.settings_outlined,
            t('通用设置'),
            t('分页、登录有效期与自动保存'),
          ),
          _entry(
            AdminSettingsDestination.content,
            Icons.upload_file_outlined,
            t('内容与上传'),
            t('公开标签、分享评论与文件限制'),
          ),
          _entry(
            AdminSettingsDestination.registration,
            Icons.people_outline,
            t('访问与注册'),
            t('邀请码与协作信令'),
          ),
          const SizedBox(height: 16),
          _heading(t('服务配置')),
          _entry(
            AdminSettingsDestination.ai,
            Icons.memory_outlined,
            t('AI 模型与提示词'),
            t('模型连接、编辑动作与系统提示词'),
          ),
          _entry(
            AdminSettingsDestination.mail,
            Icons.mail_outline,
            t('邮件服务'),
            t('SMTP、找回密码与待办提醒'),
          ),
          _entry(
            AdminSettingsDestination.webDav,
            Icons.storage_outlined,
            t('WebDAV 服务'),
            t('公开资源地址与访问配置'),
          ),
          _entry(
            AdminSettingsDestination.terminal,
            Icons.terminal_outlined,
            t('终端策略'),
            t('无操作断开时间与历史行数'),
          ),
          const SizedBox(height: 16),
          _info(t('设置来自当前服务器'), subtitle: t('切换账户后会重新验证管理员权限')),
        ],
      ),
    ),
  );
}
