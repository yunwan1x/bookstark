import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_webdav_controller.dart';

class AdminWebDavSettingsPage extends StatefulWidget {
  const AdminWebDavSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminWebDavSettingsController controller;
  final VoidCallback onReturn;

  @override
  State<AdminWebDavSettingsPage> createState() =>
      _AdminWebDavSettingsPageState();
}

class _AdminWebDavSettingsPageState extends State<AdminWebDavSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminWebDavSettingsController get c => widget.controller;
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
  void didUpdateWidget(covariant AdminWebDavSettingsPage oldWidget) {
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
    if (_leaving || c.phase == AdminWebDavPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminWebDavPhase.unknown,
            AdminWebDavPhase.committedNeedsRead,
            AdminWebDavPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开 WebDAV 配置？')),
            content: Text(
              c.phase == AdminWebDavPhase.unknown
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
          if (!mounted || c.phase != AdminWebDavPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(String key, String label) {
    final field = c.webDavFields.singleWhere((field) => field.key == key);
    return AdminSettingsField(
      fieldKey: ValueKey(key),
      controller: _fields[key]!,
      label: label,
      enabled: c.editable,
      onChanged: (value) => c.edit(key, value),
      keyboardType: field.minimum == null
          ? TextInputType.url
          : const TextInputType.numberWithOptions(signed: true),
      minLines: 1,
      maxLines: 1,
      helper: field.minimum == null
          ? t('HTTP(S) 地址，无账号、查询参数或片段')
          : '${field.minimum}–${field.maximum}',
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
        title: t('WebDAV 服务'),
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
                  if (c.phase == AdminWebDavPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminWebDavPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminWebDavPhase.unknown,
                    AdminWebDavPhase.committedNeedsRead,
                    AdminWebDavPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminWebDavPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('服务器当前配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final field in c.webDavFields)
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
                    _card(t('容量与传输'), [
                      for (final field in c.webDavFields)
                        if (field.minimum != null)
                          _field(field.key, t(field.label)),
                    ]),
                    _card(t('公开静态资源'), [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('使用独立资源地址')),
                        value:
                            c.draft['webdav_public_asset_separate_url_enabled'] ==
                            '1',
                        onChanged: c.editable
                            ? (value) => c.edit(
                                'webdav_public_asset_separate_url_enabled',
                                value ? '1' : '0',
                              )
                            : null,
                      ),
                      _field('webdav_public_asset_base_url', t('基础地址')),
                    ]),
                    Text(t('保存策略不会验证资源地址可达性，也不会删除现有文件。')),
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
                    c.phase == AdminWebDavPhase.saving
                        ? t('正在保存…')
                        : t('保存 WebDAV 设置'),
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
