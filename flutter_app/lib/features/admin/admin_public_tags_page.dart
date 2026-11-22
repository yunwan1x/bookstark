import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_public_tags.dart';
import 'admin_public_tags_controller.dart';

class AdminPublicTagsPage extends StatefulWidget {
  const AdminPublicTagsPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminPublicTagsController controller;
  final VoidCallback onReturn;
  @override
  State<AdminPublicTagsPage> createState() => _AdminPublicTagsPageState();
}

class _AdminPublicTagsPageState extends State<AdminPublicTagsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminPublicTagsController get c => widget.controller;
  final _text = TextEditingController();
  final _labels = TextEditingController();
  bool _editingLabels = false;
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminPublicTagsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      _text.clear();
      _labels.clear();
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
    if (!_editingLabels) {
      try {
        final labels = AdminPublicTagConfig.decodeForEditing(
          c.text,
        ).labels.join('\n');
        if (_labels.text != labels) _labels.text = labels;
      } on FormatException {
        _labels.clear();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _text.clear();
    _text.dispose();
    _labels.clear();
    _labels.dispose();
    super.dispose();
  }

  Future<void> _replaceInvalid() async {
    final revision = c.revision;
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(t('替换当前场景配置草稿？')),
        scrollable: true,
        content: Text(
          t(
            '将当前原文草稿替换为空的自动模式。服务器尚不会更改，'
            '需要再点保存；其他场景草稿保留。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('替换草稿')),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    c.replaceReviewedInvalid(confirmedRevision: revision, mode: 'auto');
  }

  Future<void> _leave() async {
    if (_leaving || {AdminPublicTagsPhase.saving}.contains(c.phase)) {
      return;
    }
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminPublicTagsPhase.unknown,
            AdminPublicTagsPhase.committedNeedsRead,
            AdminPublicTagsPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开公开标签设置？')),
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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    AdminPublicTagConfig? config;
    try {
      config = AdminPublicTagConfig.decodeForEditing(c.text);
    } on FormatException {
      config = null;
    }
    final selectedConfig = config;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: t('公开页面标签'),
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
                        for (final kind in c.tagKinds)
                          ChoiceChip(
                            label: Text(t(kind.label)),
                            selected: c.selected == kind,
                            onSelected: c.editable
                                ? (_) => c.select(kind)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (c.phase == AdminPublicTagsPhase.loading)
                      const Center(child: CircularProgressIndicator()),
                    if (c.message != null)
                      Semantics(liveRegion: true, child: Text(t(c.message!))),
                    if (c.phase == AdminPublicTagsPhase.failed)
                      OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                    if ({
                      AdminPublicTagsPhase.unknown,
                      AdminPublicTagsPhase.committedNeedsRead,
                      AdminPublicTagsPhase.reviewingCurrent,
                    }.contains(c.phase))
                      OutlinedButton(
                        onPressed: c.readCurrent,
                        child: Text(t('只读取服务器当前配置')),
                      ),
                    if (c.phase == AdminPublicTagsPhase.reviewingCurrent &&
                        c.current != null) ...[
                      Text(
                        t('服务器当前原文'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final kind in c.tagKinds) ...[
                        Text(t(kind.label)),
                        SelectableText(
                          c.current!.records[kind.key]?.value ?? t('未配置'),
                        ),
                      ],
                      FilledButton(
                        onPressed: c.adoptReviewedCurrent,
                        child: Text(t('采用核对后的服务器配置')),
                      ),
                    ],
                    if (selectedConfig == null && c.editable) ...[
                      Text(t('当前未配置或结构无效。原文已保留，请在高级原始配置中修正。')),
                      OutlinedButton(
                        onPressed: _replaceInvalid,
                        child: Text(t('明确替换为新的自动模式草稿')),
                      ),
                    ],
                    if (selectedConfig != null) ...[
                      _card(t('展示方式'), [
                        for (final mode in ['auto', 'manual'])
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              selectedConfig.mode == mode
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: const Color(0xff1a54ef),
                            ),
                            title: Text(
                              mode == 'auto'
                                  ? t('自动：显示公开内容的热门标签')
                                  : t('手动：按下方顺序展示'),
                            ),
                            onTap: c.editable ? () => c.editMode(mode) : null,
                          ),
                      ]),
                      _card(t('手动标签'), [
                        if (selectedConfig.multilineLabels)
                          Text(t('原有标签包含换行，请使用高级原文编辑以完整保留。'))
                        else
                          AdminSettingsField(
                            fieldKey: const ValueKey('public-tag-labels'),
                            controller: _labels,
                            label: t('每行一个标签'),
                            enabled:
                                c.editable && selectedConfig.mode == 'manual',
                            onChanged: (value) {
                              _editingLabels = true;
                              try {
                                c.editLabels(value);
                              } finally {
                                _editingLabels = false;
                              }
                            },
                            keyboardType: TextInputType.multiline,
                            minLines: 6,
                            maxLines: null,
                            helper: t('最多100项，每项200字节；保留顺序与空格。'),
                          ),
                      ]),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(t('标签展示以服务器公开页面规则为准。')),
                    ),
                    ExpansionTile(
                      key: const ValueKey('admin-public-tags-raw-section'),
                      title: Text(t('高级原始配置')),
                      initiallyExpanded: selectedConfig == null,
                      children: [
                        AdminSettingsField(
                          fieldKey: const ValueKey('public-tag-raw'),
                          controller: _text,
                          label: t('原始 JSON'),
                          enabled: c.editable,
                          onChanged: c.editRaw,
                          keyboardType: TextInputType.multiline,
                          minLines: 8,
                          maxLines: null,
                        ),
                      ],
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
                      c.phase == AdminPublicTagsPhase.saving
                          ? t('正在保存…')
                          : t('保存当前更改'),
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
}
