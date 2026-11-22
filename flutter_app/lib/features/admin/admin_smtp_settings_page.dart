import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_smtp_settings_controller.dart';

class AdminSmtpSettingsPage extends StatefulWidget {
  const AdminSmtpSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminSmtpSettingsController controller;
  final VoidCallback onReturn;

  @override
  State<AdminSmtpSettingsPage> createState() => _AdminSmtpSettingsPageState();
}

class _AdminSmtpSettingsPageState extends State<AdminSmtpSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminSmtpSettingsController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  bool _revealKey = false;
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in AdminSmtpSettingsController.fields) {
      _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminSmtpSettingsPage oldWidget) {
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
    if (c.phase == AdminSmtpPhase.permissionLost) _revealKey = false;
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

  Future<void> _save() => c.save();

  Future<void> _leave() async {
    if (_leaving || c.phase == AdminSmtpPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminSmtpPhase.unknown,
            AdminSmtpPhase.committedNeedsRead,
            AdminSmtpPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开 SMTP 配置？')),
            content: Text(
              c.phase == AdminSmtpPhase.unknown
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
          if (!mounted || c.phase != AdminSmtpPhase.saved) return;
        }
      }
      widget.onReturn();
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
        obscureText: key == 'smtp_password' && !_revealKey,
        helper: key == 'smtp_password' ? t('留空保留已保存密码；输入新密码会替换。') : null,
        suffixIcon: key == 'smtp_password'
            ? IconButton(
                tooltip: _revealKey ? t('隐藏密码') : t('显示密码'),
                onPressed: c.editable
                    ? () => setState(() => _revealKey = !_revealKey)
                    : null,
                icon: Icon(
                  _revealKey ? Icons.visibility_off : Icons.visibility,
                ),
              )
            : null,
      );

  Widget _encryption() => AdminSettingsChoice(
    fieldKey: const ValueKey('smtp_encryption'),
    label: t('加密方式'),
    value: c.draft['smtp_encryption'],
    revision: c.revision,
    options: {'starttls': 'STARTTLS', 'tls': 'TLS', 'none': t('无加密')},
    enabled: c.editable,
    onChanged: (value) => c.edit('smtp_encryption', value),
    hintLabel: t('请选择'),
    unknownLabel: t('保留当前值；只有明确选择后才更改。'),
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
        title: t('SMTP 连接'),
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
                  Text(t('邮件服务 · 服务器配置')),
                  const SizedBox(height: 16),
                  if (c.phase == AdminSmtpPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminSmtpPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminSmtpPhase.unknown,
                    AdminSmtpPhase.committedNeedsRead,
                    AdminSmtpPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminSmtpPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('当前服务器配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final key in AdminSmtpSettingsController.fields)
                      if (key != 'smtp_password')
                        SelectableText(
                          '$key: ${c.current!.records[key]?.value ?? ''}',
                        ),
                    Text(t('SMTP 密码无法回读，不能通过读取确认上次密码设置结果。')),
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的可读取配置')),
                    ),
                  ],
                  if (c.baseline != null) ...[
                    _card(t('连接配置'), [
                      _field('smtp_host', t('SMTP 主机')),
                      _field('smtp_port', t('端口'), number: true),
                      _encryption(),
                      _field('smtp_username', t('账号')),
                      _field('smtp_password', t('输入新密码')),
                      _field(
                        'mail_timeout_seconds',
                        t('连接超时（秒）'),
                        number: true,
                      ),
                    ]),
                    _card(t('发件人'), [
                      _field('mail_from_name', t('名称')),
                      _field('mail_from_address', t('邮箱')),
                    ]),
                    Text(t('保存连接配置不会发送邮件，也不会自动启用邮件服务。')),
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
                    c.phase == AdminSmtpPhase.saving ? t('正在保存…') : t('保存连接配置'),
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
