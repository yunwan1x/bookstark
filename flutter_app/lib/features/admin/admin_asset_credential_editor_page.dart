import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_asset_drafts.dart';
import 'admin_asset_secure_window.dart';
import 'admin_community_widgets.dart';

class AdminAssetCredentialEditorPage extends StatefulWidget {
  const AdminAssetCredentialEditorPage({
    super.key,
    required this.onReturn,
    required this.onSave,
    required this.onEditPrivateKey,
    this.initial,
    this.english = false,
    this.secureWindow,
  });
  final AdminAssetCredentialMetadata? initial;
  final VoidCallback onReturn;
  final Future<bool> Function(AdminAssetCredentialDraft, String?, VoidCallback)
  onSave;
  final void Function(ValueChanged<String> onApply) onEditPrivateKey;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  @override
  State<AdminAssetCredentialEditorPage> createState() =>
      _CredentialEditorState();
}

class _CredentialEditorState extends State<AdminAssetCredentialEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _name, _username;
  final _password = TextEditingController();
  late final AdminAssetWindowGuard _secure;
  late AdminAssetAuth _auth;
  String? _keyReplacement;
  late bool _replace;
  bool _ready = false,
      _secureFailed = false,
      _saving = false,
      _visible = false,
      _cleared = false,
      _invalid = false,
      _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get isNew => widget.initial == null;
  bool get _mustReplace => isNew || widget.initial!.auth != _auth;
  @override
  void initState() {
    super.initState();
    _secure = widget.secureWindow ?? AdminAssetSecureWindow();
    final value = widget.initial;
    _name = TextEditingController(text: value?.name ?? '');
    _username = TextEditingController(text: value?.username ?? '');
    _auth = value?.auth ?? AdminAssetAuth.password;
    _replace = isNew;
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

  void _clearSecret() {
    _password.clear();
    _keyReplacement = null;
    _visible = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _clearSecret();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        setState(() {
          _cleared = _replace;
        });
      }
    }
  }

  void _leave() {
    if (_saving) return;
    _clearSecret();
    widget.onReturn();
  }

  Future<void> _save() async {
    if (!_ready || _saving) return;
    final draft = AdminAssetCredentialDraft(
      name: _name.text,
      username: _username.text,
      auth: _auth,
    );
    final replacement = _replace
        ? (_auth == AdminAssetAuth.key ? _keyReplacement : _password.text)
        : null;
    try {
      if (_mustReplace && !_replace || _replace && replacement == null) {
        throw const AdminAssetDraftInvalid();
      }
      draft.toRequest(creating: isNew, replacement: replacement);
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
      accepted = await widget.onSave(draft, replacement, () {
        _clearSecret();
        if (mounted) {
          setState(() {
            _cleared = _replace;
          });
        }
      });
    } catch (_) {
      accepted = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = !accepted;
    });
    // Navigation after an acknowledged save belongs to the owning feature.
  }

  Widget _field(TextEditingController controller, String label, String id) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextField(
          key: ValueKey(id),
          controller: controller,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearSecret();
    _password.dispose();
    _name.dispose();
    _username.dispose();
    unawaited(_secure.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isNew ? t('新建凭据', 'New credential') : t('编辑凭据', 'Edit credential'),
        ),
        leading: IconButton(
          onPressed: _saving ? null : _leave,
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
            _section(t('基本资料', 'Basic information'), [
              _field(_name, t('名称', 'Name'), 'asset-credential-name'),
              _field(
                _username,
                t('用户名', 'Username'),
                'asset-credential-username',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<AdminAssetAuth>(
                key: ValueKey(_auth),
                initialValue: _auth,
                isExpanded: true,
                isDense: MediaQuery.textScalerOf(context).scale(16) <= 24,
                decoration: InputDecoration(
                  labelText: t('认证方式', 'Authentication'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: AdminAssetAuth.password,
                    child: Text(t('密码', 'Password')),
                  ),
                  DropdownMenuItem(
                    value: AdminAssetAuth.key,
                    child: Text(t('SSH 私钥', 'SSH private key')),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        _clearSecret();
                        setState(() {
                          _auth = value;
                          _replace = _mustReplace || _replace;
                        });
                      },
              ),
            ]),
            if (!isNew) ...[
              DropdownButtonFormField<bool>(
                key: ValueKey('replace-$_replace'),
                initialValue: _replace,
                isExpanded: true,
                isDense: MediaQuery.textScalerOf(context).scale(16) <= 24,
                decoration: InputDecoration(
                  labelText: t('更新方式', 'Update mode'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: false,
                    enabled: !_mustReplace,
                    child: Text(t('保持原凭据', 'Keep current credential')),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(t('替换凭据', 'Replace credential')),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null || !value && _mustReplace) return;
                        _clearSecret();
                        setState(() {
                          _replace = value;
                          _cleared = false;
                        });
                      },
              ),
              const SizedBox(height: 16),
            ],
            if (_replace)
              _section(
                _auth == AdminAssetAuth.key
                    ? t('更新私钥', 'Update private key')
                    : t('更新密码', 'Update password'),
                [
                  const SizedBox(height: 14),
                  if (_secureFailed)
                    Text(
                      t(
                        '无法启用安全窗口，不能输入凭据。',
                        'Secure window unavailable. Credential input is blocked.',
                      ),
                    )
                  else if (!_ready)
                    const Center(child: CircularProgressIndicator())
                  else if (_auth == AdminAssetAuth.key) ...[
                    Text(
                      _keyReplacement == null
                          ? t('尚未填写私钥', 'No private key entered')
                          : t(
                              '已填写私钥 · 保留原始换行',
                              'Private key entered · Original line breaks preserved',
                            ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              widget.onEditPrivateKey((value) {
                                if (!mounted ||
                                    _saving ||
                                    !_replace ||
                                    _auth != AdminAssetAuth.key) {
                                  return;
                                }
                                setState(() {
                                  _keyReplacement = value;
                                  _cleared = false;
                                });
                              });
                            },
                      child: Text(t('编辑私钥', 'Edit private key')),
                    ),
                  ] else
                    TextField(
                      key: const ValueKey('asset-credential-password'),
                      controller: _password,
                      obscureText: !_visible,
                      enabled: !_saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      decoration: InputDecoration(
                        labelText: t('新密码', 'New password'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _visible = !_visible;
                                  });
                                },
                          tooltip: _visible
                              ? t('隐藏密码', 'Hide password')
                              : t('显示密码', 'Show password'),
                          icon: Icon(
                            _visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (_cleared && _replace) ...[
              AdminCommunityInfo(
                text: t(
                  '输入已清除，请重新填写替换凭据。不会自动保留原值。',
                  'Input cleared. Enter the replacement again. The original is not silently kept.',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_invalid || _failed) ...[
              AdminCommunityInfo(
                text: _invalid
                    ? t(
                        '请填写名称、用户名和所需的新凭据。',
                        'Enter a name, username and any required replacement credential.',
                      )
                    : t(
                        '操作尚未完成，请返回核对当前资料。',
                        'Operation not completed. Return to review current data.',
                      ),
                tone: AdminCommunityTone.warning,
              ),
              const SizedBox(height: 12),
            ],
            AdminCommunityInfo(
              text: t(
                '此凭据可能被多台主机使用，修改后会同时生效。',
                'This credential may be shared by multiple hosts. Changes apply to all of them.',
              ),
              tone: AdminCommunityTone.warning,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ready && !_saving ? _save : null,
              child: Text(
                _saving ? t('正在保存', 'Saving') : t('保存凭据', 'Save credential'),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _saving ? null : _leave,
              child: Text(t('取消', 'Cancel')),
            ),
          ],
        ),
      ),
    ),
  );
}
