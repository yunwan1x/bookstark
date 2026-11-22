import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_numeric_settings_controller.dart';

class AdminNumericSettingsPage extends StatefulWidget {
  const AdminNumericSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
    this.onPagination,
  });
  final AdminNumericSettingsController controller;
  final VoidCallback onReturn;
  final VoidCallback? onPagination;

  @override
  State<AdminNumericSettingsPage> createState() =>
      _AdminNumericSettingsPageState();
}

class _AdminNumericSettingsPageState extends State<AdminNumericSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminNumericSettingsController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
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
  void didUpdateWidget(covariant AdminNumericSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      for (final field in _fields.values) {
        field.clear();
        field.dispose();
      }
      _fields.clear();
      for (final key in c.fields) {
        _fields[key] = TextEditingController();
      }
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

  Future<void> _leave({VoidCallback? destination}) async {
    if (_leaving || c.phase == AdminNumericPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminNumericPhase.unknown,
            AdminNumericPhase.committedNeedsRead,
            AdminNumericPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开设置？')),
            content: Text(
              c.phase == AdminNumericPhase.unknown
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
          if (!mounted || c.phase != AdminNumericPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(String key, String label) {
    final field = c.numericFields.singleWhere((field) => field.key == key);
    return AdminSettingsField(
      fieldKey: ValueKey(key),
      controller: _fields[key]!,
      label: label,
      enabled: c.editable,
      onChanged: (value) => c.edit(key, value),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      helper: f('{0}–{1}{2}', [
        field.minimum,
        field.maximum,
        c.baseline?.records.containsKey(key) == false ? t(' · 尚未配置') : '',
      ]),
    );
  }

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
        title: c.terminal
            ? t('终端策略')
            : c.general
            ? t('通用设置')
            : t('分页与列表'),
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
                  if (c.phase == AdminNumericPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminNumericPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminNumericPhase.unknown,
                    AdminNumericPhase.committedNeedsRead,
                    AdminNumericPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminNumericPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('当前服务器配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final field in c.numericFields)
                      SelectableText(
                        f('{0}: {1}', [
                          t(field.label),
                          c.current!.records[field.key]?.value ?? t('未配置'),
                        ]),
                      ),
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的配置')),
                    ),
                  ],
                  if (c.baseline != null) ...[
                    if (c.terminal) ...[
                      _card(t('会话策略'), [
                        _field(
                          'asset_terminal_idle_timeout_seconds',
                          t('无操作断开时间（秒）'),
                        ),
                      ]),
                      _card(t('终端显示'), [
                        _field('asset_terminal_scrollback_lines', t('历史保留行数')),
                      ]),
                      Text(t('只保存终端策略，不修改资产登录凭据或加密密钥。实际终端连接的生效时机由服务器决定。')),
                    ] else if (c.general) ...[
                      _card(t('会话与编辑'), [
                        _field('login_session_days', t('登录有效期（天）')),
                        _field('save_interval', t('自动保存间隔（秒）')),
                      ]),
                      _card(t('浏览与导航'), [
                        _field('nav_max_items', t('导航书签上限')),
                        _field('favicon_cache_days', t('图标缓存（天）')),
                      ]),
                      Text(t('服务器设置的会话作用以服务端为准；自动保存间隔不改变本地空间草稿策略。')),
                      if (widget.onPagination != null)
                        AdminSettingsLink(
                          title: t('分页与列表'),
                          subtitle: t('各模块分页大小与标签列表上限'),
                          icon: Icons.list_alt_outlined,
                          onTap: c.editable
                              ? () => _leave(destination: widget.onPagination)
                              : null,
                        ),
                    ] else ...[
                      _card(t('分页大小'), [
                        for (final field in c.numericFields)
                          if (field.key != 'label_list_limit')
                            _field(field.key, t(field.label)),
                      ]),
                      _card(t('标签列表'), [
                        _field('label_list_limit', t('标签列表上限')),
                      ]),
                    ],
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
                    c.phase == AdminNumericPhase.saving
                        ? t('正在保存…')
                        : c.terminal
                        ? t('保存终端策略')
                        : t('保存设置'),
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
