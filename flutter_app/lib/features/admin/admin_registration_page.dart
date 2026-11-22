import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_registration_controller.dart';

class AdminRegistrationPage extends StatefulWidget {
  const AdminRegistrationPage({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onSignaling,
  });
  final AdminRegistrationController controller;
  final VoidCallback onReturn;
  final VoidCallback onSignaling;

  @override
  State<AdminRegistrationPage> createState() => _AdminRegistrationPageState();
}

class _AdminRegistrationPageState extends State<AdminRegistrationPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminRegistrationController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  bool _revealKey = false;
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in AdminRegistrationController.fields) {
      if (key != 'invite_code_enabled') _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminRegistrationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      for (final field in _fields.values) {
        field.clear();
      }
      _revealKey = false;
      c.addListener(_changed);
      c.load();
    }
  }

  void _changed() {
    if (!mounted) return;
    for (final entry in _fields.entries) {
      final text = c.draft[entry.key] ?? '';
      if (entry.value.text != text) {
        entry.value.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    if (c.phase == AdminRegistrationPhase.permissionLost) _revealKey = false;
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    for (final field in _fields.values) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    int? confirmation;
    if (c.clearingCode) {
      final revision = c.revision;
      final approved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(t('清空邀请码？')),
          content: Text(t('保存后会删除服务器当前保存的邀请码。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续编辑')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认清空并保存')),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
      confirmation = revision;
    }
    await c.save(confirmedClearRevision: confirmation);
  }

  Future<void> _leave({VoidCallback? destination}) async {
    if (_leaving || c.phase == AdminRegistrationPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminRegistrationPhase.unknown,
            AdminRegistrationPhase.committedNeedsRead,
            AdminRegistrationPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开注册设置？')),
            content: Text(
              c.phase == AdminRegistrationPhase.unknown
                  ? t('上次保存结果未知，离开不会撤销服务器可能已保存的更改。')
                  : t('当前有未确认或未保存的更改。'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: Text(t('继续编辑')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(t('放弃本地草稿并离开')),
              ),
              if (c.editable && c.dirty)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'save'),
                  child: Text(t('保存')),
                ),
            ],
          ),
        );
        if (!mounted || choice == null || choice == 'edit') return;
        if (choice == 'save') {
          await _save();
          if (!mounted || c.phase != AdminRegistrationPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(String key, String label, {bool number = false}) =>
      AdminSettingsField(
        fieldKey: ValueKey(key),
        controller: _fields[key]!,
        label: label,
        enabled: c.editable,
        onChanged: (value) => c.edit(key, value),
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        obscureText: key == 'invite_code' && !_revealKey,
        helper: key == 'invite_code' ? t('主动清空并保存会删除邀请码；未修改则保留。') : null,
        suffixIcon: key == 'invite_code'
            ? IconButton(
                tooltip: _revealKey ? t('隐藏邀请码') : t('显示邀请码'),
                onPressed: c.editable
                    ? () => setState(() => _revealKey = !_revealKey)
                    : null,
                icon: Icon(
                  _revealKey ? Icons.visibility_off : Icons.visibility,
                ),
              )
            : null,
      );

  Widget _card(String title, List<Widget> children) => Padding(
    key: ValueKey(('admin-card', title)),
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: const Color(0xffedf4ff),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            ...children,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: adminSettingsAppBar(
        context,
        title: t('邀请码与注册'),
        dirty: c.dirty,
        onReturn: _leave,
        backLabel: t('返回'),
        dirtyLabel: t('未保存'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (c.phase == AdminRegistrationPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminRegistrationPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminRegistrationPhase.unknown,
                    AdminRegistrationPhase.committedNeedsRead,
                    AdminRegistrationPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminRegistrationPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      f('当前服务器开关：{0}', [
                        c.current!.records['invite_code_enabled']?.value ??
                            t('未配置'),
                      ]),
                    ),
                    SelectableText(
                      f('当前服务器邀请码：{0}', [
                        _revealKey
                            ? c.current!.records['invite_code']?.value ?? ''
                            : '••••••••',
                      ]),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _revealKey = !_revealKey),
                      child: Text(_revealKey ? t('隐藏核对邀请码') : t('显示核对邀请码')),
                    ),
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的配置')),
                    ),
                  ],
                  if (c.baseline != null) ...[
                    _card(t('注册邀请码'), [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('启用邀请码')),
                        value: c.draft['invite_code_enabled'] == '1',
                        onChanged: c.editable
                            ? (value) => c.edit(
                                'invite_code_enabled',
                                value ? '1' : '0',
                              )
                            : null,
                      ),
                      _field('invite_code', t('邀请码')),
                      const SizedBox(height: 12),
                      Text(t('关闭验证不会删除已保存的邀请码。')),
                    ]),
                    _card(t('注册影响'), [
                      Text(
                        t(
                          '启用后，匹配邀请码的新账户会自动通过审批；关闭后，新注册账户需要审批。'
                          '修改此处不会改变已有账户状态。',
                        ),
                      ),
                    ]),
                    AdminSettingsLink(
                      title: t('协作信令'),
                      subtitle: t('WebRTC 地址、连接限制与 TURN'),
                      icon: Icons.list_alt_outlined,
                      onTap: c.editable
                          ? () => _leave(destination: widget.onSignaling)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: c.editable && c.dirty ? _save : null,
                  child: Text(
                    c.phase == AdminRegistrationPhase.saving
                        ? t('正在保存…')
                        : t('保存注册设置'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
