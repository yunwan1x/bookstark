import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_recommendations_controller.dart';

class AdminRecommendationsPage extends StatefulWidget {
  const AdminRecommendationsPage({
    super.key,
    required this.controller,
    required this.onReturn,
  });
  final AdminRecommendationsController controller;
  final VoidCallback onReturn;

  @override
  State<AdminRecommendationsPage> createState() =>
      _AdminRecommendationsPageState();
}

class _AdminRecommendationsPageState extends State<AdminRecommendationsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminRecommendationsController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in AdminRecommendationsController.fields) {
      _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminRecommendationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.dispose();
      for (final field in _fields.values) {
        field.clear();
        field.dispose();
      }
      _fields.clear();
      for (final key in AdminRecommendationsController.fields) {
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
    if (_leaving || c.phase == AdminRecommendationsPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminRecommendationsPhase.unknown,
            AdminRecommendationsPhase.committedNeedsRead,
            AdminRecommendationsPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开推荐设置？')),
            content: Text(
              c.phase == AdminRecommendationsPhase.unknown
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
          if (!mounted || c.phase != AdminRecommendationsPhase.saved) return;
        }
      }
      (destination ?? widget.onReturn)();
    } finally {
      _leaving = false;
    }
  }

  Widget _field(String key, String label, {bool multiline = false}) =>
      AdminSettingsField(
        fieldKey: ValueKey(key),
        controller: _fields[key]!,
        label: label,
        enabled: c.editable,
        onChanged: (value) => c.edit(key, value),
        keyboardType: multiline
            ? TextInputType.multiline
            : TextInputType.number,
        minLines: multiline ? 6 : 1,
        maxLines: multiline ? null : 1,
        helper: multiline ? t('每行一个，最多50项；保存时整理空格与重复项。') : t('1–50 个'),
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
  Widget build(BuildContext context) {
    final names = {
      'recent': t('最近使用'),
      'total': t('总使用次数'),
      'book': t('书籍'),
      'bookmark': t('书签'),
      'manual': t('手动精选'),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: t('标签推荐'),
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
                    if (c.phase == AdminRecommendationsPhase.loading)
                      const Center(child: CircularProgressIndicator()),
                    if (c.message != null)
                      Semantics(liveRegion: true, child: Text(t(c.message!))),
                    if (c.phase == AdminRecommendationsPhase.failed)
                      OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                    if ({
                      AdminRecommendationsPhase.unknown,
                      AdminRecommendationsPhase.committedNeedsRead,
                      AdminRecommendationsPhase.reviewingCurrent,
                    }.contains(c.phase))
                      OutlinedButton(
                        onPressed: c.readCurrent,
                        child: Text(t('只读取当前配置')),
                      ),
                    if (c.phase == AdminRecommendationsPhase.reviewingCurrent &&
                        c.current != null) ...[
                      Text(
                        t('当前服务器配置'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final key in AdminRecommendationsController.fields)
                        SelectableText(
                          f('{0}: {1}', [
                            key,
                            c.current!.records[key]?.value ?? t('未配置'),
                          ]),
                        ),
                      FilledButton(
                        onPressed: c.adoptReviewedCurrent,
                        child: Text(t('采用核对后的配置')),
                      ),
                    ],
                    if (c.baseline != null) ...[
                      _card(t('推荐策略'), [
                        DropdownButtonFormField<String>(
                          key: ValueKey(c.draft['tag_recommend_strategy']),
                          initialValue:
                              names.containsKey(
                                c.draft['tag_recommend_strategy'],
                              )
                              ? c.draft['tag_recommend_strategy']
                              : null,
                          isExpanded: true,
                          isDense: false,
                          itemHeight: null,
                          items: [
                            for (final entry in names.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: c.editable
                              ? (value) {
                                  if (value != null) {
                                    c.edit('tag_recommend_strategy', value);
                                  }
                                }
                              : null,
                          decoration: InputDecoration(
                            labelText: t('推荐策略'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ]),
                      _card(t('推荐数量'), [
                        _field('tag_recommend_page_size', t('数量')),
                      ]),
                      _card(t('手动精选标签'), [
                        _field(
                          'tag_recommend_manual_labels',
                          t('手动标签'),
                          multiline: true,
                        ),
                      ]),
                      Text(t('保存仅影响服务器标签推荐配置。空行与无法无损保存的分隔符会提示修正。')),
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
                      c.phase == AdminRecommendationsPhase.saving
                          ? t('正在保存…')
                          : t('保存推荐设置'),
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
