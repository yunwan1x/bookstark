import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_settings_repository.dart';
import 'admin_text_settings_controller.dart';

String adminTextLabel(AdminAiTextField field) => switch (field) {
  AdminAiTextField.markdown => 'Markdown',
  AdminAiTextField.html => 'HTML',
  AdminAiTextField.drawing => '画板',
  AdminAiTextField.selection => '选中文本',
  AdminAiTextField.htmlActions => 'HTML',
  AdminAiTextField.book => '书籍',
  AdminAiTextField.article => '文章',
  AdminAiTextField.note => '笔记',
  AdminAiTextField.task => '待办',
  AdminAiTextField.empty => '空场景',
};

class AdminTextSettingsPage extends StatefulWidget {
  const AdminTextSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminTextSettingsController controller;
  final VoidCallback onReturn;
  @override
  State<AdminTextSettingsPage> createState() => _AdminTextSettingsPageState();
}

class _AdminTextSettingsPageState extends State<AdminTextSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminTextSettingsController get c => widget.controller;
  final _text = TextEditingController();
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminTextSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      _text.clear();
      c.addListener(_changed);
      c.load();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_text.text != c.text) {
      _text.value = TextEditingValue(
        text: c.text,
        selection: TextSelection.collapsed(offset: c.text.length),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _text.clear();
    _text.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final field = c.selected;
    final revision = c.revision;
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(f('恢复 {0} 默认值？', [t(adminTextLabel(field))])),
        scrollable: true,
        content: Text(
          t(
            '此操作会立即覆盖这项服务器保存的文本和当前草稿，'
            '不需要再点保存。其他场景的草稿会保留。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('立即恢复默认')),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    await c.resetToDefault(confirmedField: field, confirmedRevision: revision);
  }

  Future<void> _leave() async {
    if (_leaving ||
        {AdminTextPhase.saving, AdminTextPhase.resetting}.contains(c.phase)) {
      return;
    }
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminTextPhase.unknown,
            AdminTextPhase.receiptNeedsRead,
            AdminTextPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开文本配置？')),
            scrollable: true,
            content: Text(t('未保存草稿会丢弃；离开不会撤销服务器可能已完成的操作。')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: Text(t('继续编辑')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(t('放弃草稿并离开')),
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
          await c.save();
          if (!mounted || !c.editable || c.dirty) return;
        }
      }
      widget.onReturn();
    } finally {
      _leaving = false;
    }
  }

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
        title: c.prompts ? t('系统提示词') : t('编辑动作'),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final field in c.fields)
                        ChoiceChip(
                          label: Text(t(adminTextLabel(field))),
                          selected: c.selected == field,
                          onSelected: c.editable
                              ? (_) => c.select(field)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.prompts ? t('提示词原文') : t('动作原文'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.prompts
                        ? t('保留原始文本，不执行 HTML 或脚本。')
                        : t(
                            '每行动作为 label | prompt；# 开头为注释。保留空行与 {subject} 占位符。',
                          ),
                  ),
                  const SizedBox(height: 16),
                  if (c.phase == AdminTextPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminTextPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if (c.phase == AdminTextPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('服务器当前文本'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final field in c.fields) ...[
                      Text(t(adminTextLabel(field))),
                      SelectableText(
                        c.current!.records[field.key]?.value ?? '',
                      ),
                      const Divider(),
                    ],
                    FilledButton(
                      onPressed: c.adoptReviewedCurrent,
                      child: Text(t('采用核对后的服务器文本')),
                    ),
                  ],
                  if ({
                    AdminTextPhase.unknown,
                    AdminTextPhase.receiptNeedsRead,
                    AdminTextPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取服务器当前文本')),
                    ),
                  AdminSettingsField(
                    key: const ValueKey('admin-raw-text-container'),
                    fieldKey: const ValueKey('admin-raw-text'),
                    controller: _text,
                    label: t('原始纯文本'),
                    enabled: c.editable,
                    onChanged: c.edit,
                    keyboardType: TextInputType.multiline,
                    minLines: 12,
                    maxLines: null,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(t('保存空文本后，服务器重启时可能重新填入默认值。')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: c.editable ? _reset : null,
                      icon: const Icon(Icons.restart_alt),
                      label: Text(t('恢复当前场景默认值')),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: c.editable && c.dirty ? c.save : null,
                  child: Text(
                    c.phase == AdminTextPhase.saving ? t('正在保存…') : t('保存文本'),
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
