import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_signaling_controller.dart';
import 'admin_settings_repository.dart';

class AdminSignalingPage extends StatefulWidget {
  const AdminSignalingPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminSignalingController controller;
  final VoidCallback onReturn;

  @override
  State<AdminSignalingPage> createState() => _AdminSignalingPageState();
}

class _AdminSignalingPageState extends State<AdminSignalingPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminSignalingController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  bool _revealKey = false;
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in c.fields) {
      _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminSignalingPage oldWidget) {
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
    if (c.phase == AdminSignalingPhase.permissionLost) _revealKey = false;
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
          title: Text(t('清空 TURN 凭据？')),
          content: Text(t('保存后会删除服务器当前保存的 TURN 凭据。')),
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
    if (_leaving || c.phase == AdminSignalingPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminSignalingPhase.unknown,
            AdminSignalingPhase.committedNeedsRead,
            AdminSignalingPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开信令设置？')),
            content: Text(
              c.phase == AdminSignalingPhase.unknown
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
          if (!mounted || c.phase != AdminSignalingPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    bool multiline = false,
  }) => AdminSettingsField(
    fieldKey: ValueKey(key),
    controller: _fields[key]!,
    label: label,
    enabled: c.editable,
    onChanged: (value) => c.edit(key, value),
    keyboardType: multiline
        ? TextInputType.multiline
        : number
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    obscureText: key == 'webrtc_signaling_turn_credential' && !_revealKey,
    minLines: multiline ? 3 : 1,
    maxLines: multiline ? 6 : 1,
    helper: key == 'webrtc_signaling_turn_credential'
        ? t('主动清空并保存会删除 TURN 凭据；未修改则保留。')
        : null,
    suffixIcon: key == 'webrtc_signaling_turn_credential'
        ? IconButton(
            tooltip: _revealKey ? t('隐藏 TURN 凭据') : t('显示 TURN 凭据'),
            onPressed: c.editable
                ? () => setState(() => _revealKey = !_revealKey)
                : null,
            icon: Icon(_revealKey ? Icons.visibility_off : Icons.visibility),
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

  Widget _toggle(String key, String label) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: c.draft[key] == '1',
    onChanged: c.editable ? (value) => c.edit(key, value ? '1' : '0') : null,
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
        title: t('协作信令'),
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
                  if (c.phase == AdminSignalingPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminSignalingPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminSignalingPhase.unknown,
                    AdminSignalingPhase.committedNeedsRead,
                    AdminSignalingPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminSignalingPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('服务器当前配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final field in AdminSignalingField.values)
                      SelectableText(
                        f('{0}: {1}', [
                          t(field.label),
                          field == AdminSignalingField.turnCredential &&
                                  !_revealKey
                              ? '••••••••'
                              : c.current!.records[field.key]?.value ??
                                    t('未配置'),
                        ]),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _revealKey = !_revealKey),
                      child: Text(_revealKey ? t('隐藏核对凭据') : t('显示核对凭据')),
                    ),
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的配置')),
                    ),
                  ],
                  if (c.baseline != null) ...[
                    _card(t('WebRTC 信令'), [
                      _toggle('webrtc_signaling_enabled', t('启用信令')),
                      _field('webrtc_signaling_default_url', t('默认信令地址')),
                      _field(
                        'webrtc_signaling_max_peers',
                        t('单房间连接数（2–64）'),
                        number: true,
                      ),
                      _field(
                        'webrtc_signaling_max_message_kb',
                        t('信令消息上限（8–512 KB）'),
                        number: true,
                      ),
                    ]),
                    _card(t('来源与网络'), [
                      _field(
                        'webrtc_signaling_allowed_origins',
                        t('允许的来源'),
                        multiline: true,
                      ),
                      _field(
                        'webrtc_signaling_stun_urls',
                        t('STUN 地址'),
                        multiline: true,
                      ),
                      const SizedBox(height: 12),
                      Text(t('每行一个或逗号分隔；地址格式通过不代表实际可连接。')),
                    ]),
                    ExpansionTile(
                      title: Text(t('TURN 服务')),
                      subtitle: Text(t('地址、账号与凭据')),
                      children: [
                        _field('webrtc_signaling_turn_url', t('TURN 地址')),
                        _field('webrtc_signaling_turn_username', t('TURN 账号')),
                        _field(
                          'webrtc_signaling_turn_credential',
                          t('TURN 凭据'),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                    _card(t('本地调试'), [
                      _toggle(
                        'webrtc_signaling_allow_local_file',
                        t('允许本地文件调试'),
                      ),
                      Text(t('仅用于需要的本地协作调试。')),
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
                    c.phase == AdminSignalingPhase.saving
                        ? t('正在保存…')
                        : t('保存信令设置'),
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
