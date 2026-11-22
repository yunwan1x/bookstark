import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_mail_settings_controller.dart';
import 'admin_settings_repository.dart';

class AdminMailSettingsPage extends StatefulWidget {
  const AdminMailSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onSmtp,
  });
  final AdminMailSettingsController controller;
  final VoidCallback onReturn;
  final VoidCallback onSmtp;

  @override
  State<AdminMailSettingsPage> createState() => _AdminMailSettingsPageState();
}

class _AdminMailSettingsPageState extends State<AdminMailSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminMailSettingsController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  final _recipient = TextEditingController();
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in AdminMailSettingsController.fields) {
      _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminMailSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      for (final field in _fields.values) {
        field.clear();
      }
      _recipient.clear();
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
    if (c.phase == AdminMailPhase.permissionLost) _recipient.clear();
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _recipient.clear();
    _recipient.dispose();
    for (final field in _fields.values) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() => c.save();

  Future<void> _leave({VoidCallback? destination}) async {
    if (_leaving || c.serviceBusy || c.phase == AdminMailPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminMailPhase.unknown,
            AdminMailPhase.committedNeedsRead,
            AdminMailPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开邮件配置？')),
            content: Text(
              c.phase == AdminMailPhase.unknown
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
          if (!mounted || c.phase != AdminMailPhase.saved) return;
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
      );

  Widget _toggle(String key, String label) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: c.draft[key] == '1',
    onChanged: c.editable ? (value) => c.edit(key, value ? '1' : '0') : null,
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
        title: t('邮件服务'),
        dirty: c.dirty,
        onReturn: _leave,
        backLabel: t('返回'),
        dirtyLabel: t('未保存'),
        actions: [
          IconButton(
            tooltip: t('刷新发送状态'),
            onPressed: c.editable ? c.refreshStatus : null,
            icon: const Icon(Icons.refresh),
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
                  if (c.phase == AdminMailPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminMailPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminMailPhase.unknown,
                    AdminMailPhase.committedNeedsRead,
                    AdminMailPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminMailPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('当前服务器配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final key in AdminMailSettingsController.fields)
                      SelectableText(
                        '$key: ${c.current!.records[key]?.value ?? ''}',
                      ),
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的配置')),
                    ),
                  ],
                  if (c.baseline != null) ...[
                    AdminSettingsLink(
                      title: t('SMTP 连接'),
                      subtitle: t('主机、加密与发件人'),
                      icon: Icons.dns_outlined,
                      onTap: c.editable
                          ? () => _leave(destination: widget.onSmtp)
                          : null,
                    ),
                    _card(t('功能设置'), [
                      _toggle('mail_enabled', t('启用邮件服务')),
                      _toggle('task_email_reminder_enabled', t('待办邮件提醒')),
                      _toggle('password_reset_enabled', t('邮件找回密码')),
                      _field('mail_public_url', t('公开站点地址')),
                      _field(
                        'password_reset_expiry_minutes',
                        t('重置链接有效期（分钟）'),
                        number: true,
                      ),
                      const SizedBox(height: 12),
                      Text(t('保存设置不代表 SMTP 连接或实际投递成功。')),
                    ]),
                    _card(t('发送测试'), [
                      Text(t('始终使用服务器已保存配置。只有点击发送才会发出测试邮件。')),
                      if (c.dirty) Text(t('本页有未保存更改，本次测试不会使用这些更改。')),
                      const SizedBox(height: 12),
                      AdminSettingsField(
                        fieldKey: const ValueKey('mail-test-recipient'),
                        controller: _recipient,
                        label: t('测试收件邮箱'),
                        enabled: c.editable,
                        onChanged: (value) {},
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: c.editable
                            ? () => c.sendTest(_recipient.text)
                            : null,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(t('发送测试邮件')),
                      ),
                      if (c.serviceBusy) const LinearProgressIndicator(),
                      if (c.serviceMessage != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(t(c.serviceMessage!)),
                        ),
                      if (c.testOutcome != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(switch (c.testOutcome!.state) {
                            AdminMailTestState.sent => t('测试邮件已发送；请自行核对是否收到。'),
                            AdminMailTestState.rateLimited => t(
                              '发送次数已达限制，请稍后再试。',
                            ),
                            AdminMailTestState.rejected => t(
                              '服务器拒绝发送，请检查已保存配置。',
                            ),
                            AdminMailTestState.unknown => t(
                              '发送结果未知，邮件可能已发送；不会自动重试。',
                            ),
                          }),
                        ),
                    ]),
                    _card(t('发送状态'), [
                      if (c.status == null)
                        Text(t('尚无当前状态，请刷新读取。'))
                      else ...[
                        Text(f('待发送：{0}', [c.status!.pending])),
                        Text(f('失败：{0}', [c.status!.failed])),
                        Text(f('已发送：{0}', [c.status!.sent])),
                        Text(
                          c.status!.lastSent == null
                              ? t('尚无发送记录')
                              : f('最近发送（本地时间）：{0}', [
                                  c.status!.lastSent!.toLocal(),
                                ]),
                        ),
                        if (c.status!.hasLastError)
                          Text(t('服务端记录了发送错误，请检查连接配置。')),
                      ],
                      if (c.statusReadAt != null)
                        Text(f('最近刷新（本地时间）：{0}', [c.statusReadAt!.toLocal()])),
                      OutlinedButton(
                        onPressed: c.editable ? c.refreshStatus : null,
                        child: Text(t('刷新发送状态')),
                      ),
                    ]),
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
                    c.phase == AdminMailPhase.saving ? t('正在保存…') : t('保存功能设置'),
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
