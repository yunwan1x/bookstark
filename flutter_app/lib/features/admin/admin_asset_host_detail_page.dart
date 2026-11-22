import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_asset_drafts.dart';
import 'admin_community_widgets.dart';

class AdminAssetHostDetailPage extends StatelessWidget {
  const AdminAssetHostDetailPage({
    super.key,
    required this.host,
    required this.onReturn,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
    required this.onMigrate,
    this.onTerminal,
    this.onFiles,
    this.onDocker,
    this.receipt,
    this.staleSnapshot = false,
    this.enabled = true,
    this.busy = false,
    this.english = false,
  });
  final AdminAssetHostMetadata host;
  final AdminAssetConnectionReceipt? receipt;
  final VoidCallback? onTerminal, onFiles, onDocker;
  final VoidCallback onReturn, onTest, onEdit, onDelete, onRefresh, onMigrate;
  final bool enabled, busy, english, staleSnapshot;
  String t(String zh, String en) => english ? en : zh;
  String get _storedStatus => switch (host.status) {
    AdminAssetStatus.online => t('在线', 'Online'),
    AdminAssetStatus.offline => t('离线', 'Offline'),
    AdminAssetStatus.unknown =>
      host.neverChecked ? t('尚未检测', 'Not tested') : t('状态未知', 'Unknown status'),
  };
  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Builder(
      builder: (context) {
        if (MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 4), Text(value)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label)),
            const SizedBox(width: 12),
            Expanded(child: Text(value)),
          ],
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: Text(t('SSH 主机详情', 'SSH host details')),
      leading: IconButton(
        onPressed: onReturn,
        tooltip: t('返回', 'Back'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('服务器空间', 'Server workspace')),
          const SizedBox(height: 20),
          if (staleSnapshot) ...[
            AdminCommunityInfo(
              text: t(
                '以下为上次读取资料，请刷新保存状态。',
                'The following is the last-read snapshot. Refresh stored status.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          _card(host.name, [
            _value('ID', host.id.toString()),
            _value(t('地址', 'Address'), '${host.host}:${host.port}'),
            _value(t('用户', 'User'), host.username),
            _value(
              t('登录凭据', 'Login credential'),
              host.credentialId == 0
                  ? t('旧式内联凭据', 'Legacy inline credential')
                  : host.credentialName.isEmpty
                  ? t('凭据引用需核对', 'Review credential reference')
                  : '${host.credentialName} #${host.credentialId}',
            ),
            _value('Shell', host.shell),
          ]),
          if (host.credentialId == 0) ...[
            AdminCommunityInfo(
              tone: AdminCommunityTone.warning,
              text: t(
                '更换或关闭加密前，请先迁移此主机的内联凭据。',
                'Migrate this host inline credential before replacing or disabling encryption.',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: enabled && !busy ? onMigrate : null,
              child: Text(t('迁移为独立凭据', 'Migrate to independent credential')),
            ),
            const SizedBox(height: 16),
          ],
          _card(t('连接状态', 'Connection status'), [
            Text(_storedStatus, key: const ValueKey('asset-stored-status')),
            const SizedBox(height: 10),
            Text(
              t('保存的检测结果，不代表实时状态。', 'A stored test result, not a live status.'),
            ),
            if (host.lastCheck?.meaningful == true)
              _value(t('上次检测', 'Last test'), host.lastCheck!.raw),
            if (receipt != null) ...[
              const SizedBox(height: 12),
              AdminCommunityInfo(
                text:
                    '${t('本次检测回执', 'This test receipt')}: ${receipt!.status == AdminAssetStatus.online ? t('连接成功', 'Connected') : t('连接失败', 'Connection failed')}\n${receipt!.checked.raw}\n${t('回执与数据库保存状态分别展示。', 'Receipt and stored database status are shown separately.')}',
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled && !busy ? onTest : null,
              child: Text(
                busy ? t('正在检测', 'Testing') : t('检测连接', 'Test connection'),
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(t('刷新保存状态', 'Refresh stored status')),
            ),
          ]),
          Material(
            color: const Color(0xffeaf2ff),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: Text(t('高级配置', 'Advanced configuration')),
              initiallyExpanded: true,
              childrenPadding: const EdgeInsets.all(16),
              children: [
                _value(
                  t('工作目录', 'Working directory'),
                  host.cwd.isEmpty ? t('默认目录', 'Default directory') : host.cwd,
                ),
                _value('Docker Socket', host.dockerSocket),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (onTerminal != null) ...[
            FilledButton.icon(
              onPressed: enabled && !busy ? onTerminal : null,
              icon: const Icon(Icons.terminal),
              label: Text(t('远程终端', 'Remote terminal')),
            ),
            const SizedBox(height: 10),
          ],
          if (onFiles != null) ...[
            FilledButton.icon(
              onPressed: enabled && !busy ? onFiles : null,
              icon: const Icon(Icons.folder_outlined),
              label: Text(t('远程文件', 'Remote files')),
            ),
            const SizedBox(height: 10),
          ],
          if (onDocker != null) ...[
            FilledButton.icon(
              onPressed: enabled && !busy ? onDocker : null,
              icon: const Icon(Icons.view_in_ar_outlined),
              label: const Text('Docker'),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: enabled && !busy ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
            label: Text(t('编辑主机', 'Edit host')),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: enabled && !busy ? onDelete : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xffbf2637),
            ),
            child: Text(t('删除主机', 'Delete host')),
          ),
        ],
      ),
    ),
  );
}
