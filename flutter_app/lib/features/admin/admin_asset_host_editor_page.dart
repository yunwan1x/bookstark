import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_asset_drafts.dart';
import 'admin_community_widgets.dart';

class AdminAssetHostEditorPage extends StatefulWidget {
  const AdminAssetHostEditorPage({
    super.key,
    required this.credentials,
    required this.onSave,
    required this.onReturn,
    required this.onNewCredential,
    this.initial,
    this.english = false,
  });
  final List<AdminAssetCredentialMetadata> credentials;
  final AdminAssetHostMetadata? initial;
  final Future<bool> Function(
    AdminAssetHostDraft,
    AdminAssetCredentialMetadata?,
  )
  onSave;
  final VoidCallback onReturn, onNewCredential;
  final bool english;
  @override
  State<AdminAssetHostEditorPage> createState() => _HostEditorState();
}

class _HostEditorState extends State<AdminAssetHostEditorPage> {
  late final TextEditingController _name, _host, _port, _shell, _cwd, _socket;
  int? _credentialId;
  bool _saving = false, _invalid = false, _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  List<TextEditingController> get _fields => [
    _name,
    _host,
    _port,
    _shell,
    _cwd,
    _socket,
  ];
  bool get _legacy => widget.initial?.credentialId == 0;
  AdminAssetCredentialMetadata? get _chosen {
    for (final row in widget.credentials) {
      if (row.id == _credentialId) return row;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    _name = TextEditingController(text: row?.name ?? '');
    _host = TextEditingController(text: row?.host ?? '');
    _port = TextEditingController(text: (row?.port ?? 22).toString());
    _shell = TextEditingController(text: row?.shell ?? '/bin/sh');
    _cwd = TextEditingController(text: row?.cwd ?? '');
    _socket = TextEditingController(
      text: row?.dockerSocket ?? '/var/run/docker.sock',
    );
    _credentialId = row?.credentialId;
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final chosen = _chosen;
    final legacy = _legacy && _credentialId == 0;
    if (!legacy && chosen == null) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    final draft = AdminAssetHostDraft(
      name: _name.text,
      host: _host.text,
      port: int.tryParse(_port.text) ?? -1,
      shell: _shell.text,
      cwd: _cwd.text,
      dockerSocket: _socket.text,
      credentialId: legacy ? 0 : chosen!.id,
      username: legacy ? widget.initial!.username : chosen!.username,
      auth: legacy ? widget.initial!.auth : chosen!.auth,
    );
    try {
      draft.toRequest(creating: widget.initial == null);
    } catch (_) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _invalid = false;
      _failed = false;
    });
    var accepted = false;
    try {
      accepted = await widget.onSave(draft, chosen);
    } catch (_) {
      accepted = false;
    }
    if (mounted) {
      setState(() {
        _saving = false;
        _failed = !accepted;
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String id, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      key: ValueKey(id),
      controller: controller,
      enabled: !_saving,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _section(String title, List<Widget> children) => Container(
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
        ...children,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final validId = _chosen?.id ?? (_legacy && _credentialId == 0 ? 0 : null);
    final large = MediaQuery.textScalerOf(context).scale(16) > 24;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) widget.onReturn();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            widget.initial == null
                ? t('新增 SSH 主机', 'Add SSH host')
                : t('编辑 SSH 主机', 'Edit SSH host'),
          ),
          leading: IconButton(
            onPressed: _saving ? null : widget.onReturn,
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
              _section(t('连接信息', 'Connection information'), [
                _field(_name, t('名称', 'Name'), 'asset-host-name'),
                _field(_host, t('主机地址', 'Host address'), 'asset-host-address'),
                if (large) ...[
                  _field(
                    _port,
                    t('端口', 'Port'),
                    'asset-host-port',
                    numeric: true,
                  ),
                  _field(_shell, 'Shell', 'asset-host-shell'),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          _port,
                          t('端口', 'Port'),
                          'asset-host-port',
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(_shell, 'Shell', 'asset-host-shell'),
                      ),
                    ],
                  ),
              ]),
              _section(t('登录凭据', 'Login credential'), [
                const SizedBox(height: 14),
                Semantics(
                  container: true,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('asset-host-credential-$validId'),
                    initialValue: validId,
                    hint: Text(t('请选择凭据', 'Select a credential')),
                    isExpanded: true,
                    isDense: MediaQuery.textScalerOf(context).scale(16) <= 24,
                    decoration: InputDecoration(
                      labelText: t('使用已有凭据', 'Use existing credential'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      if (_legacy)
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            t('保留旧式内联凭据', 'Keep legacy inline credential'),
                          ),
                        ),
                      for (final row in widget.credentials)
                        DropdownMenuItem(
                          value: row.id,
                          child: Text(
                            '${row.name} #${row.id} · ${row.auth == AdminAssetAuth.key ? t('私钥', 'Private key') : t('密码', 'Password')}',
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (id) {
                            setState(() {
                              _credentialId = id;
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${t('用户名', 'Username')}: ${_chosen?.username ?? (_legacy && _credentialId == 0 ? widget.initial!.username : t('请选择凭据', 'Select a credential'))}',
                ),
                if (widget.credentials.isEmpty)
                  Text(
                    t(
                      '暂无独立凭据，请先新增。',
                      'No independent credentials. Add one first.',
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving ? null : widget.onNewCredential,
                    child: Text(t('新增凭据', 'Add credential')),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: Text(
                      t(
                        '高级设置 · 工作目录与 Docker Socket',
                        'Advanced · Working directory and Docker Socket',
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _field(
                        _cwd,
                        t('工作目录', 'Working directory'),
                        'asset-host-cwd',
                      ),
                      _field(_socket, 'Docker Socket', 'asset-host-socket'),
                    ],
                  ),
                ),
              ),
              AdminCommunityInfo(
                text: t('保存不会自动检测连接。', 'Saving does not test the connection.'),
              ),
              if (_invalid || _failed) ...[
                const SizedBox(height: 12),
                AdminCommunityInfo(
                  text: _invalid
                      ? t(
                          '请核对主机名称、地址、端口、凭据及路径。',
                          'Check the host name, address, port, credential and paths.',
                        )
                      : t(
                          '操作尚未完成，请返回核对当前资料。',
                          'Operation not completed. Return to review current data.',
                        ),
                  tone: AdminCommunityTone.warning,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? t('正在保存', 'Saving') : t('保存主机', 'Save host'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _saving ? null : widget.onReturn,
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
