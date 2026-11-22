import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_assets_controller.dart';
import 'admin_community_widgets.dart';

class AdminAssetsCatalogPage extends StatefulWidget {
  const AdminAssetsCatalogPage({
    super.key,
    required this.controller,
    required this.catalog,
    required this.onCatalog,
    required this.onReturn,
    required this.onSettings,
    required this.onCreate,
    required this.onHost,
    required this.onCredential,
    required this.onRevealCredential,
    required this.onDeleteCredential,
    this.onWebdav,
    this.english = false,
  });
  final AdminAssetsController controller;
  final AdminAssetCatalog catalog;
  final ValueChanged<AdminAssetCatalog> onCatalog;
  final VoidCallback onReturn, onSettings, onCreate;
  final VoidCallback? onWebdav;
  final ValueChanged<AdminAssetHostMetadata> onHost;
  final ValueChanged<AdminAssetCredentialMetadata> onCredential,
      onRevealCredential,
      onDeleteCredential;
  final bool english;
  @override
  State<AdminAssetsCatalogPage> createState() => _CatalogState();
}

class _CatalogState extends State<AdminAssetsCatalogPage> {
  late final TextEditingController _query;
  AdminAssetsController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get isHosts => widget.catalog == AdminAssetCatalog.hosts;
  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: c.appliedQuery);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _load({AdminAssetStatus? status}) {
    c.load(
      widget.catalog,
      query: _query.text,
      status: status ?? c.appliedStatus,
    );
  }

  String _status(AdminAssetHostMetadata host) => switch (host.status) {
    AdminAssetStatus.online => t('在线', 'Online'),
    AdminAssetStatus.offline => t('离线', 'Offline'),
    AdminAssetStatus.unknown =>
      host.neverChecked ? t('未检测', 'Not tested') : t('状态未知', 'Unknown status'),
  };
  String _auth(AdminAssetAuth auth) => auth == AdminAssetAuth.key
      ? t('SSH 私钥', 'SSH private key')
      : t('密码', 'Password');
  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xfff0f5ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
  Widget _host(AdminAssetHostMetadata host) {
    final large = MediaQuery.textScalerOf(context).scale(16) > 24;
    final color = switch (host.status) {
      AdminAssetStatus.online => const Color(0xff167747),
      AdminAssetStatus.offline => const Color(0xffbf2637),
      AdminAssetStatus.unknown => const Color(0xff946100),
    };
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: switch (host.status) {
          AdminAssetStatus.online => const Color(0xffd9f7e5),
          AdminAssetStatus.offline => const Color(0xffffe8ea),
          AdminAssetStatus.unknown => const Color(0xfffff2d5),
        },
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _status(host),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
    final name = Text(
      host.name,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    final timestamp = Text(
      host.lastCheck?.meaningful == true
          ? '${t('上次检测', 'Last test')} ${host.lastCheck!.utc.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}'
          : t('尚未检测', 'Not tested yet'),
    );
    final action = TextButton.icon(
      onPressed: () => widget.onHost(host),
      label: Text(
        t('查看主机', 'View host'),
        semanticsLabel: '${t('查看主机', 'View host')} ${host.name} ID ${host.id}',
      ),
      icon: const Icon(Icons.chevron_right),
    );
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xffd8e7ff),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dns_outlined,
                  color: Color(0xff1b3760),
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (large) ...[
                      name,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: badge),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: name),
                          const SizedBox(width: 8),
                          badge,
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text('ID: ${host.id}'),
                    Text('${host.username}@${host.host}:${host.port}'),
                    Text(
                      '${_auth(host.auth)} · ${host.credentialId == 0
                          ? t('旧式内联凭据', 'Legacy inline credential')
                          : host.credentialName.isEmpty
                          ? t('凭据引用需核对', 'Review credential reference')
                          : host.credentialName}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          if (large) ...[
            timestamp,
            Align(alignment: Alignment.centerRight, child: action),
          ] else
            Row(
              children: [
                Expanded(child: timestamp),
                action,
              ],
            ),
        ],
      ),
    );
  }

  Widget _credential(AdminAssetCredentialMetadata value) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, color: Color(0xff1b3760), size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text('ID: ${value.id}'),
                  Text('${t('用户', 'User')}: ${value.username}'),
                  Text('${t('类型', 'Type')}: ${_auth(value.auth)}'),
                  Text(t('凭据默认隐藏', 'Credential hidden by default')),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: t('凭据操作', 'Credential actions'),
              onSelected: (action) {
                if (action == 'view') widget.onRevealCredential(value);
                if (action == 'delete') widget.onDeleteCredential(value);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'view',
                  child: Text(t('查看凭据', 'View credential')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: c.canWrite,
                  child: Text(t('删除凭据', 'Delete credential')),
                ),
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: c.canWrite ? () => widget.onCredential(value) : null,
            child: Text(t('编辑凭据', 'Edit credential')),
          ),
        ),
      ],
    ),
  );

  String? _operationNotice() {
    if (c.migrationPartial) {
      return '${t('凭据已创建，ID', 'Credential created, ID')} ${c.migrationCreated!.credential.id}。${t('主机绑定未确认。请读取主机与凭据资料核对，不要重复创建。', 'Host binding is unconfirmed. Read hosts and credentials; do not create again.')}';
    }
    if (c.operation == AdminAssetOperationState.idle &&
        c.lastUnconfirmedOperation != null) {
      return t(
        '上次操作仍未经确认；结束核对不代表保存成功。',
        'The previous operation remains unconfirmed. Finishing review does not confirm success.',
      );
    }
    return switch (c.operation) {
      AdminAssetOperationState.unknown => t(
        '上次提交结果未知。请读取当前资料并明确结束核对；不会自动重发。',
        'The previous result is unknown. Read current data and explicitly finish review. Nothing is replayed.',
      ),
      AdminAssetOperationState.acknowledged => t(
        '服务器已确认操作。下方资料需单独刷新核对。',
        'The server acknowledged the operation. Refresh current data separately.',
      ),
      AdminAssetOperationState.changed => t(
        '资料已变化，未发送修改。请重新读取。',
        'Data changed. No modification was sent. Read it again.',
      ),
      AdminAssetOperationState.refused => t(
        '本次操作未完成，请重新核对资料。',
        'The operation did not complete. Review the data again.',
      ),
      AdminAssetOperationState.migrationRequired => t(
        '部分主机需要迁移凭据或重新绑定，尚未更换密钥。',
        'Some hosts require credential migration or rebinding. The key was not changed.',
      ),
      AdminAssetOperationState.ownerLost => t(
        '管理员会话已失效，请返回重新登录。',
        'The administrator session is no longer valid. Return and sign in again.',
      ),
      AdminAssetOperationState.submitting => t(
        '正在提交，请稍候。',
        'Submitting. Please wait.',
      ),
      AdminAssetOperationState.idle => null,
    };
  }

  Widget _footer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: c.canWrite && !c.migrationPartial ? widget.onCreate : null,
        child: Text(
          isHosts ? t('新增主机', 'Add host') : t('新增凭据', 'Add credential'),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        isHosts
            ? t('连接检测由手动操作发起', 'Connection tests are started manually')
            : t(
                '凭据默认隐藏，查看需明确操作',
                'Credentials are hidden; viewing requires an explicit action',
              ),
        textAlign: TextAlign.center,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final load = c.loadState(widget.catalog);
      final notice = _operationNotice();
      final rows = isHosts ? c.hosts : c.credentials;
      final large = MediaQuery.textScalerOf(context).scale(16) > 24;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            onPressed: widget.onReturn,
            tooltip: t('返回', 'Back'),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('资产管理', 'Asset management')),
          actions: [
            if (widget.onWebdav != null)
              IconButton(
                onPressed: c.canWrite ? widget.onWebdav : null,
                tooltip: t('WebDAV 连接', 'WebDAV connections'),
                icon: const Icon(Icons.cloud_outlined),
              ),
            IconButton(
              onPressed: c.closed ? null : widget.onSettings,
              tooltip: t('资产设置', 'Asset settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      t('管理员 · 服务器空间', 'Administrator · Server workspace'),
                      style: const TextStyle(color: Color(0xff586882)),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<AdminAssetCatalog>(
                      segments: [
                        ButtonSegment(
                          value: AdminAssetCatalog.hosts,
                          label: Text(t('SSH 主机', 'SSH hosts')),
                        ),
                        ButtonSegment(
                          value: AdminAssetCatalog.credentials,
                          label: Text(t('凭据', 'Credentials')),
                        ),
                      ],
                      selected: {
                        isHosts
                            ? AdminAssetCatalog.hosts
                            : AdminAssetCatalog.credentials,
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: const Color(0xff2563eb),
                        selectedForegroundColor: Colors.white,
                        backgroundColor: const Color(0xffeef2f9),
                        foregroundColor: const Color(0xff172c50),
                        side: BorderSide.none,
                        minimumSize: const Size(0, 48),
                      ),
                      onSelectionChanged: c.closed
                          ? null
                          : (values) => widget.onCatalog(values.single),
                    ),
                    const SizedBox(height: 20),
                    if (notice != null) ...[
                      AdminCommunityInfo(
                        text: notice,
                        tone: c.operation == AdminAssetOperationState.unknown
                            ? AdminCommunityTone.warning
                            : AdminCommunityTone.info,
                      ),
                      const SizedBox(height: 12),
                      if (c.operation == AdminAssetOperationState.unknown)
                        OutlinedButton(
                          onPressed:
                              load == AdminAssetLoadState.ready &&
                                  !c.migrationPartial &&
                                  c.unknownReviewCatalog == widget.catalog
                              ? () => c.finishUnknownReview(widget.catalog)
                              : null,
                          child: Text(t('结束本次核对', 'Finish this review')),
                        ),
                    ],
                    if (c.migrationPartial) ...[
                      OutlinedButton(
                        onPressed:
                            c.closed ||
                                c.operation ==
                                    AdminAssetOperationState.submitting
                            ? null
                            : () async {
                                await c.load(AdminAssetCatalog.hosts);
                                if (!c.closed) {
                                  await c.load(AdminAssetCatalog.credentials);
                                }
                              },
                        child: Text(
                          t('读取迁移当前资料', 'Read migration current data'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed:
                            c.loadState(AdminAssetCatalog.hosts) ==
                                    AdminAssetLoadState.ready &&
                                c.loadState(AdminAssetCatalog.credentials) ==
                                    AdminAssetLoadState.ready
                            ? () => c.finishMigrationReview()
                            : null,
                        child: Text(t('结束迁移核对', 'Finish migration review')),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (isHosts) ...[
                      TextField(
                        controller: _query,
                        enabled:
                            !c.closed &&
                            c.operation != AdminAssetOperationState.submitting,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: InputDecoration(
                          labelText: t(
                            '搜索主机名称、地址或用户名',
                            'Search host name, address or username',
                          ),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            onPressed: c.closed ? null : () => _load(),
                            tooltip: t('搜索', 'Search'),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in <AdminAssetStatus?>[
                            null,
                            AdminAssetStatus.online,
                            AdminAssetStatus.offline,
                            AdminAssetStatus.unknown,
                          ])
                            ChoiceChip(
                              label: Text(
                                value == null
                                    ? t('全部', 'All')
                                    : switch (value) {
                                        AdminAssetStatus.online => t(
                                          '在线',
                                          'Online',
                                        ),
                                        AdminAssetStatus.offline => t(
                                          '离线',
                                          'Offline',
                                        ),
                                        AdminAssetStatus.unknown => t(
                                          '未知 / 未检测',
                                          'Unknown / Not tested',
                                        ),
                                      },
                              ),
                              selected: c.appliedStatus == value,
                              showCheckmark: false,
                              selectedColor: const Color(0xff2563eb),
                              backgroundColor: const Color(0xffeef2f9),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              labelStyle: TextStyle(
                                color: c.appliedStatus == value
                                    ? Colors.white
                                    : const Color(0xff172c50),
                              ),

                              onSelected:
                                  c.closed ||
                                      c.operation ==
                                          AdminAssetOperationState.submitting
                                  ? null
                                  : (_) => c.load(
                                      AdminAssetCatalog.hosts,
                                      query: _query.text,
                                      status: value,
                                    ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: rows == null
                              ? Text(t('当前资料', 'Current data'))
                              : Text(
                                  '${t('当前显示', 'Showing')} ${rows.length} ${isHosts ? t('台', 'hosts') : t('项', 'items')}',
                                ),
                        ),
                        IconButton(
                          onPressed:
                              c.closed ||
                                  load == AdminAssetLoadState.loading ||
                                  c.operation ==
                                      AdminAssetOperationState.submitting
                              ? null
                              : () => _load(),
                          tooltip: t('刷新资料', 'Refresh data'),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (load == AdminAssetLoadState.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (load == AdminAssetLoadState.failed)
                      AdminCommunityInfo(
                        text: t(
                          '读取失败，请重试。当前数量未知。',
                          'Read failed. Try again. The current count is unknown.',
                        ),
                        tone: AdminCommunityTone.warning,
                      )
                    else if (rows != null) ...[
                      if (rows.isEmpty)
                        AdminCommunityInfo(
                          text: t('没有符合条件的记录。', 'No matching records.'),
                        ),
                      if (isHosts)
                        ...c.hosts!.map(_host)
                      else
                        ...c.credentials!.map(_credential),
                    ] else if (!c.closed)
                      AdminCommunityInfo(
                        text: t('请读取当前资料。', 'Read current data.'),
                      ),
                    if (large) ...[const SizedBox(height: 24), _footer()],
                  ],
                ),
              ),
              if (!large)
                Padding(padding: const EdgeInsets.all(16), child: _footer()),
            ],
          ),
        ),
      );
    },
  );
}
