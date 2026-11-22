import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/go_text.dart';
import 'admin_asset_settings.dart';
import 'admin_asset_secure_window.dart';
import 'admin_assets_controller.dart';
import 'admin_community_widgets.dart';

class AdminAssetSettingsPage extends StatefulWidget {
  const AdminAssetSettingsPage({
    super.key,
    required this.controller,
    required this.initial,
    required this.onReturn,
    required this.onSaved,
    required this.onRevealKey,
    required this.onMigrate,
    this.english = false,
    this.secureWindow,
  });
  final AdminAssetsController controller;
  final AdminAssetSettingsMetadata initial;
  final VoidCallback onReturn, onSaved, onRevealKey, onMigrate;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  @override
  State<AdminAssetSettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<AdminAssetSettingsPage>
    with WidgetsBindingObserver {
  late final TextEditingController _idle, _scroll;
  final _key = TextEditingController(), _repeat = TextEditingController();
  late final AdminAssetWindowGuard _secure;
  AdminAssetKeyAction _action = AdminAssetKeyAction.keep;
  bool _ready = false,
      _secureFailed = false,
      _saving = false,
      _invalid = false,
      _cleared = false,
      _confirming = false,
      _attempted = false;
  AdminAssetsController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  String _mode(AdminAssetKeyAction action) => switch (action) {
    AdminAssetKeyAction.keep => t('保持当前密钥', 'Keep current key'),
    AdminAssetKeyAction.replace => t('更换密钥', 'Replace key'),
    AdminAssetKeyAction.disable => t('关闭加密', 'Disable encryption'),
  };
  @override
  void initState() {
    super.initState();
    _secure = widget.secureWindow ?? AdminAssetSecureWindow();
    _idle = TextEditingController(text: widget.initial.idleSeconds.toString());
    _scroll = TextEditingController(
      text: widget.initial.scrollbackLines.toString(),
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enable());
  }

  Future<void> _enable() async {
    try {
      await _secure.acquire();
      if (mounted) {
        setState(() {
          _ready = true;
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

  void _clearKey() {
    _key.clear();
    _repeat.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _clearKey();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        setState(() {
          _cleared = _action == AdminAssetKeyAction.replace;
          _confirming = false;
        });
      }
    }
  }

  bool _valid() {
    final idle = int.tryParse(_idle.text), scroll = int.tryParse(_scroll.text);
    return idle != null &&
        idle >= 1 &&
        idle <= 86400 &&
        scroll != null &&
        scroll >= 500 &&
        scroll <= 50000 &&
        (_action != AdminAssetKeyAction.replace ||
            _ready &&
                trimGoSpace(_key.text).isNotEmpty &&
                trimGoSpace(_key.text) == trimGoSpace(_repeat.text));
  }

  Future<void> _prepare() async {
    if (_saving || _attempted || !c.canWrite) return;
    if (!_valid()) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _invalid = false;
    });
    if (_action == AdminAssetKeyAction.replace) {
      setState(() {
        _confirming = true;
      });
      return;
    }
    if (_action == AdminAssetKeyAction.disable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('关闭凭据加密', 'Disable credential encryption')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminCommunityInfo(
                tone: AdminCommunityTone.danger,
                text: t(
                  '关闭后，资产凭据将以明文保存在服务器数据库中。',
                  'After disabling encryption, asset credentials will be stored as plaintext in the server database.',
                ),
              ),
              const SizedBox(height: 12),
              Text(t('不会测试 SSH 连接。', 'No SSH connection will be tested.')),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffbf2637),
              ),
              child: Text(t('确认关闭', 'Confirm disable')),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    if (_saving || _attempted || !c.canWrite || !_valid()) return;
    setState(() {
      _saving = true;
      _attempted = true;
    });
    final saved = await c.saveSettings(
      widget.initial,
      idleSeconds: int.parse(_idle.text),
      scrollbackLines: int.parse(_scroll.text),
      action: _action,
      replacement: _action == AdminAssetKeyAction.replace ? _key.text : null,
      onSubmitted: () {
        _clearKey();
      },
    );
    if (!mounted) return;
    _clearKey();
    setState(() {
      _saving = false;
      _confirming = false;
    });
    if (saved) widget.onSaved();
  }

  void _leave() {
    if (_saving) return;
    _clearKey();
    widget.onReturn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearKey();
    _key.dispose();
    _repeat.dispose();
    _idle.dispose();
    _scroll.dispose();
    unawaited(_secure.close());
    super.dispose();
  }

  Widget _card(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    String id, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: ValueKey(id),
      controller: controller,
      enabled: !_saving && !_attempted,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: secret ? TextInputType.text : TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        if (_confirming) {
          setState(() {
            _confirming = false;
          });
        } else {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            _confirming
                ? t('确认更换密钥', 'Confirm key replacement')
                : t('资产设置', 'Asset settings'),
          ),
          leading: IconButton(
            onPressed: _saving
                ? null
                : () {
                    if (_confirming) {
                      setState(() {
                        _confirming = false;
                      });
                    } else {
                      _leave();
                    }
                  },
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
              if (_confirming) ...[
                AdminCommunityInfo(
                  tone: AdminCommunityTone.warning,
                  text: t(
                    '将重新加密所有已保存的资产凭据。请妥善保管新密钥。',
                    'Saved asset credentials will be encrypted again. Keep the new key safe.',
                  ),
                ),
                const SizedBox(height: 16),
                _card(t('变更摘要', 'Change summary'), [
                  Text(
                    '${t('空闲超时（秒）', 'Idle timeout (seconds)')}: ${_idle.text}',
                  ),
                  const Divider(),
                  Text('${t('回滚行数', 'Scrollback lines')}: ${_scroll.text}'),
                  const Divider(),
                  Text(_mode(_action)),
                ]),
                Text(
                  t(
                    '保存不会连接远端主机。其他管理员仍可能同时修改资料。',
                    'Saving does not connect to remote hosts. Another administrator may modify data concurrently.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving || !c.canWrite ? null : _submit,
                  child: Text(t('确认保存', 'Confirm save')),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _confirming = false;
                          });
                        },
                  child: Text(t('返回核对', 'Return to review')),
                ),
              ] else ...[
                _card(t('终端策略', 'Terminal policy'), [
                  _field(
                    _idle,
                    t('空闲超时（秒）', 'Idle timeout (seconds)'),
                    'asset-settings-idle',
                  ),
                  _field(
                    _scroll,
                    t('回滚行数', 'Scrollback lines'),
                    'asset-settings-scroll',
                  ),
                ]),
                _card(t('凭据加密', 'Credential encryption'), [
                  Text(
                    widget.initial.encryptionEnabled
                        ? t('已启用', 'Enabled')
                        : t('未启用', 'Disabled'),
                  ),
                  const SizedBox(height: 12),
                  Text(t('当前密钥：••••••••', 'Current key: ••••••••')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _saving || c.closed
                          ? null
                          : widget.onRevealKey,
                      child: Text(t('显示当前密钥', 'Show current key')),
                    ),
                  ),
                  RadioGroup<AdminAssetKeyAction>(
                    groupValue: _action,
                    onChanged: (value) {
                      if (value == null || _saving || _attempted) return;
                      _clearKey();
                      setState(() {
                        _action = value;
                        _cleared = false;
                      });
                    },
                    child: Column(
                      children: [
                        for (final action in AdminAssetKeyAction.values)
                          RadioListTile<AdminAssetKeyAction>(
                            value: action,
                            title: Text(_mode(action)),
                          ),
                      ],
                    ),
                  ),
                  if (_action == AdminAssetKeyAction.replace) ...[
                    if (_ready) ...[
                      _field(
                        _key,
                        t('新密钥', 'New key'),
                        'asset-settings-key',
                        secret: true,
                      ),
                      _field(
                        _repeat,
                        t('确认新密钥', 'Confirm new key'),
                        'asset-settings-key-confirm',
                        secret: true,
                      ),
                    ] else
                      Text(
                        _secureFailed
                            ? t(
                                '安全窗口不可用，不能输入密钥。',
                                'Secure window unavailable. Key input is blocked.',
                              )
                            : t('正在启用安全窗口。', 'Enabling secure window.'),
                      ),
                  ],
                  Text(
                    t(
                      '更换密钥会重新加密已保存的资产凭据。',
                      'Replacing the key encrypts saved asset credentials again.',
                    ),
                  ),
                ]),
                if (_cleared)
                  AdminCommunityInfo(
                    text: t(
                      '密钥输入已清除，请重新填写。',
                      'Key input cleared. Enter it again.',
                    ),
                  ),
                if (_invalid)
                  AdminCommunityInfo(
                    tone: AdminCommunityTone.warning,
                    text: t(
                      '请检查终端参数；更换时需填写一致的非空新密钥。',
                      'Check policy values. Replacement requires matching nonempty keys.',
                    ),
                  ),
                if (!_attempted &&
                    c.operation == AdminAssetOperationState.unknown) ...[
                  AdminCommunityInfo(
                    text: t(
                      '以下为重新读取的当前资料，不能据此确认上次请求结果。',
                      'This is freshly read current data; it does not confirm the previous request.',
                    ),
                    tone: AdminCommunityTone.warning,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_attempted) ...[
                  AdminCommunityInfo(
                    text: c.operation == AdminAssetOperationState.unknown
                        ? t(
                            '结果未知，请返回读取当前资料核对。不会自动重发。',
                            'Result unknown. Return to read current data. Nothing is replayed.',
                          )
                        : t(
                            '请返回重新读取当前资料后核对本次操作。',
                            'Return and read current data to review this operation.',
                          ),
                    tone: AdminCommunityTone.warning,
                  ),
                  if (c.operation == AdminAssetOperationState.migrationRequired)
                    OutlinedButton(
                      onPressed: widget.onMigrate,
                      child: Text(
                        t(
                          '处理旧式凭据与引用',
                          'Resolve legacy credentials and references',
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                if (c.operation == AdminAssetOperationState.unknown &&
                    c.unknownReviewCatalog == AdminAssetCatalog.settings)
                  OutlinedButton(
                    onPressed:
                        c.loadState(AdminAssetCatalog.settings) ==
                            AdminAssetLoadState.ready
                        ? () {
                            if (c.finishUnknownReview(
                              AdminAssetCatalog.settings,
                            )) {
                              widget.onReturn();
                            }
                          }
                        : null,
                    child: Text(t('结束本次核对', 'Finish this review')),
                  ),
                FilledButton(
                  onPressed: _saving || _attempted || !c.canWrite
                      ? null
                      : _prepare,
                  child: Text(
                    _saving ? t('正在保存', 'Saving') : t('保存设置', 'Save settings'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
