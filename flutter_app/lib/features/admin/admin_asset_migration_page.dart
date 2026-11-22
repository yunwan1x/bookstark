import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_assets_controller.dart';
import 'admin_community_widgets.dart';

class AdminAssetMigrationPage extends StatefulWidget {
  const AdminAssetMigrationPage({
    super.key,
    required this.controller,
    required this.host,
    required this.onReturn,
    required this.onBound,
    this.english = false,
  });
  final AdminAssetsController controller;
  final AdminAssetHostMetadata host;
  final VoidCallback onReturn, onBound;
  final bool english;
  @override
  State<AdminAssetMigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<AdminAssetMigrationPage>
    with WidgetsBindingObserver {
  late final TextEditingController _name;
  bool _attempted = false, _busy = false, _bindAttempted = false;
  AdminAssetsController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: '${widget.host.name} ${t('凭据', 'credential')}',
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      c.background();
      if (mounted) setState(() {});
    }
  }

  Future<void> _create() async {
    if (_busy || _attempted || !c.canWrite || c.migrationCreated != null) {
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
    });
    if (await c.prepareMigration(widget.host, _name.text) && mounted) {
      await c.createMigrationCredential();
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _bind() async {
    if (_busy || _bindAttempted || !c.canWrite || c.migrationRetired) return;
    setState(() {
      _busy = true;
    });
    _bindAttempted = true;
    final saved = await c.bindMigration();
    if (!mounted) return;
    setState(() {
      _busy = false;
    });
    if (saved) widget.onBound();
  }

  Future<void> _read() async {
    if (_busy || c.closed) return;
    setState(() {
      _busy = true;
    });
    await c.load(AdminAssetCatalog.hosts);
    if (!c.closed) await c.load(AdminAssetCatalog.credentials);
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  void _leave() {
    if (_busy) return;
    c.background();
    widget.onReturn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final created = c.migrationCreated;
      final bound = c.migrationBound;
      final canFinish =
          c.loadState(AdminAssetCatalog.hosts) == AdminAssetLoadState.ready &&
          c.loadState(AdminAssetCatalog.credentials) ==
              AdminAssetLoadState.ready;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(t('确认迁移凭据', 'Confirm credential migration')),
            leading: IconButton(
              onPressed: _busy ? null : _leave,
              tooltip: t('返回', 'Back'),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.host.name),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xffeaf2ff),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        enabled: !_attempted && !_busy && created == null,
                        decoration: InputDecoration(
                          labelText: t('新凭据名称', 'New credential name'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('${t('用户名', 'Username')}: ${widget.host.username}'),
                      Text(
                        widget.host.auth == AdminAssetAuth.key
                            ? t('认证方式：私钥', 'Authentication: private key')
                            : t('认证方式：密码', 'Authentication: password'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xffcbd5e1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        created == null
                            ? t('1  创建独立凭据', '1  Create independent credential')
                            : '${t('1  凭据已创建，ID', '1  Credential created, ID')} ${created.credential.id}',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        bound == null
                            ? t(
                                '2  绑定到本主机：尚未确认',
                                '2  Bind to this host: unconfirmed',
                              )
                            : '${t('2  绑定已确认，主机 ID', '2  Binding acknowledged, host ID')} ${bound.host.id}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdminCommunityInfo(
                  tone: AdminCommunityTone.warning,
                  text: t(
                    '分两步提交；中断时先读取核对，不要重复创建。已创建凭据不会被自动删除。',
                    'Submitted in two steps. Read and review after interruption. Do not create again. Created credentials are never automatically deleted.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    '不会连接远端主机，也不会显示秘密。',
                    'No remote host connection or secret display.',
                  ),
                ),
                if (c.migrationRetired) ...[
                  const SizedBox(height: 12),
                  AdminCommunityInfo(
                    text: t(
                      '本次迁移已停止，请读取当前资料核对。',
                      'This migration was retired. Read current data to review it.',
                    ),
                  ),
                ],
                if ({
                  AdminAssetOperationState.changed,
                  AdminAssetOperationState.refused,
                }.contains(c.operation)) ...[
                  const SizedBox(height: 12),
                  AdminCommunityInfo(
                    text: t(
                      '资料已变化或本次操作未完成，请读取当前资料核对。',
                      'Data changed or the operation did not complete. Read current data to review.',
                    ),
                    tone: AdminCommunityTone.warning,
                  ),
                ],
                if (c.operation == AdminAssetOperationState.unknown) ...[
                  const SizedBox(height: 12),
                  AdminCommunityInfo(
                    text: t(
                      '提交结果未知，不会自动重发。',
                      'Result unknown. Nothing is replayed.',
                    ),
                    tone: AdminCommunityTone.warning,
                  ),
                ],
                const SizedBox(height: 24),
                if (created == null)
                  FilledButton(
                    onPressed: _busy || _attempted || !c.canWrite
                        ? null
                        : _create,
                    child: Text(t('确认迁移', 'Confirm migration')),
                  )
                else if (bound == null)
                  FilledButton(
                    onPressed:
                        _busy ||
                            _bindAttempted ||
                            c.migrationRetired ||
                            !c.canWrite
                        ? null
                        : _bind,
                    child: Text(t('核对并绑定本主机', 'Review and bind this host')),
                  ),
                if (_attempted || created != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy || c.closed ? null : _read,
                    child: Text(t('读取当前资料', 'Read current data')),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !canFinish
                        ? null
                        : () {
                            if (c.finishMigrationReview()) widget.onReturn();
                          },
                    child: Text(t('结束迁移核对', 'Finish migration review')),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _leave,
                  child: Text(t('取消', 'Cancel')),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
