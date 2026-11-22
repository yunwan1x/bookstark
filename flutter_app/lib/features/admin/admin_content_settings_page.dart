import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_content_settings_controller.dart';
import 'admin_settings_repository.dart';

class AdminContentSettingsPage extends StatefulWidget {
  const AdminContentSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onRecommendations,
    required this.onPublicTags,
  });
  final AdminContentSettingsController controller;
  final VoidCallback onReturn;
  final VoidCallback onRecommendations;
  final VoidCallback onPublicTags;

  @override
  State<AdminContentSettingsPage> createState() =>
      _AdminContentSettingsPageState();
}

class _AdminContentSettingsPageState extends State<AdminContentSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminContentSettingsController get c => widget.controller;
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
  void didUpdateWidget(covariant AdminContentSettingsPage oldWidget) {
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
    if (_leaving || c.phase == AdminContentPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminContentPhase.unknown,
            AdminContentPhase.committedNeedsRead,
            AdminContentPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开内容设置？')),
            content: Text(
              c.phase == AdminContentPhase.unknown
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
          if (!mounted || c.phase != AdminContentPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(String key, String label) {
    final field = c.contentFields.singleWhere((field) => field.key == key);
    return AdminSettingsField(
      fieldKey: ValueKey(key),
      controller: _fields[key]!,
      label: label,
      enabled: c.editable,
      onChanged: (value) => c.edit(key, value),
      keyboardType: field.minimum == null
          ? TextInputType.multiline
          : const TextInputType.numberWithOptions(signed: true),
      minLines: field.minimum == null ? 2 : 1,
      maxLines: field.minimum == null ? 5 : 1,
      helper: field.minimum == null
          ? t('逗号分隔，保留原文')
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
        title: t('内容与上传'),
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
                  if (c.phase == AdminContentPhase.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (c.message != null)
                    Semantics(liveRegion: true, child: Text(t(c.message!))),
                  if (c.phase == AdminContentPhase.failed)
                    OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                  if ({
                    AdminContentPhase.unknown,
                    AdminContentPhase.committedNeedsRead,
                    AdminContentPhase.reviewingCurrent,
                  }.contains(c.phase))
                    OutlinedButton(
                      onPressed: c.readCurrent,
                      child: Text(t('只读取当前配置')),
                    ),
                  if (c.phase == AdminContentPhase.reviewingCurrent &&
                      c.current != null) ...[
                    Text(
                      t('当前服务器配置'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final field in c.contentFields)
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
                    _card(t('上传限制'), [
                      for (final field in c.contentFields)
                        if (!{
                          AdminContentField.comments,
                          AdminContentField.commentLength,
                        }.contains(field))
                          _field(field.key, t(field.label)),
                      const SizedBox(height: 12),
                      Text(t('MIME 留空使用服务器默认图片类型；更新可能有约 60 秒缓存。')),
                    ]),
                    _card(t('评论设置'), [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('公开分享评论')),
                        value: c.draft['share_comments_enabled'] == '1',
                        onChanged: c.editable
                            ? (value) => c.edit(
                                'share_comments_enabled',
                                value ? '1' : '0',
                              )
                            : null,
                      ),
                      _field('share_comment_max_length', t('评论字符上限')),
                    ]),
                    AdminSettingsLink(
                      title: t('标签推荐'),
                      subtitle: t('策略与手动标签'),
                      icon: Icons.list_alt_outlined,
                      onTap: c.editable
                          ? () => _leave(destination: widget.onRecommendations)
                          : null,
                    ),
                    AdminSettingsLink(
                      title: t('公开页面标签'),
                      subtitle: t('文章、笔记、书籍、书签'),
                      icon: Icons.list_alt_outlined,
                      onTap: c.editable
                          ? () => _leave(destination: widget.onPublicTags)
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
                    c.phase == AdminContentPhase.saving
                        ? t('正在保存…')
                        : t('保存本页设置'),
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
