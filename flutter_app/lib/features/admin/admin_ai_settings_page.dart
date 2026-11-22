import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'package:flutter/material.dart';

import 'admin_ai_settings_controller.dart';

class AdminAiSettingsPage extends StatefulWidget {
  const AdminAiSettingsPage({
    super.key,
    required this.controller,
    required this.onReturn,
    required this.onPrompts,
    required this.onActions,
  });
  final AdminAiSettingsController controller;
  final VoidCallback onReturn;
  final VoidCallback onPrompts;
  final VoidCallback onActions;

  @override
  State<AdminAiSettingsPage> createState() => _AdminAiSettingsPageState();
}

class _AdminAiSettingsPageState extends State<AdminAiSettingsPage> {
  String t(String value) => adminSettingsText(context, value);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values);
  AdminAiSettingsController get c => widget.controller;
  final Map<String, TextEditingController> _fields = {};
  bool _revealKey = false;
  bool _leaving = false;
  @override
  void initState() {
    super.initState();
    for (final key in AdminAiSettingsController.fields) {
      if (key != 'ai_enabled') _fields[key] = TextEditingController();
    }
    c.addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant AdminAiSettingsPage oldWidget) {
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
    if (c.phase == AdminAiPhase.permissionLost) _revealKey = false;
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
    if (c.clearingKey) {
      final revision = c.revision;
      final approved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(t('清空 API Key？')),
          content: Text(t('保存后会删除服务器当前保存的 AI 密钥。')),
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
    if (_leaving || c.phase == AdminAiPhase.saving) return;
    _leaving = true;
    try {
      if (c.dirty ||
          {
            AdminAiPhase.unknown,
            AdminAiPhase.committedNeedsRead,
            AdminAiPhase.reviewingCurrent,
          }.contains(c.phase)) {
        final choice = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(t('离开 AI 配置？')),
            content: Text(
              c.phase == AdminAiPhase.unknown
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
          if (!mounted || c.phase != AdminAiPhase.saved) return;
        }
      }
      c.cancelTest();
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
        obscureText: key == 'ai_api_key' && !_revealKey,
        helper: key == 'ai_api_key' ? t('主动清空并保存会删除密钥；未修改则保留。') : null,
        suffixIcon: key == 'ai_api_key'
            ? IconButton(
                tooltip: _revealKey ? t('隐藏密钥') : t('显示密钥'),
                onPressed: c.editable
                    ? () => setState(() => _revealKey = !_revealKey)
                    : null,
                icon: Icon(
                  _revealKey ? Icons.visibility_off : Icons.visibility,
                ),
              )
            : null,
      );

  Widget _provider() => AdminSettingsChoice(
    fieldKey: const ValueKey('ai_provider'),
    label: t('接口类型'),
    value: c.draft['ai_provider'],
    revision: c.revision,
    options: {'openai': t('OpenAI 兼容'), 'anthropic': t('Anthropic（Claude）')},
    enabled: c.editable,
    onChanged: (value) => c.edit('ai_provider', value),
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

  Widget _usageRow(String label, int? value) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final count = Text(
          value?.toString() ?? t('未提供'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), count],
          );
        }
        return Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            count,
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = c.baseline != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: t('AI 模型与提示词'),
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
                    if (c.phase == AdminAiPhase.loading)
                      const Center(child: CircularProgressIndicator()),
                    if (c.message != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(t(c.message!)),
                        ),
                      ),
                    if (c.phase == AdminAiPhase.failed)
                      OutlinedButton(onPressed: c.load, child: Text(t('重新读取'))),
                    if ({
                      AdminAiPhase.unknown,
                      AdminAiPhase.committedNeedsRead,
                      AdminAiPhase.reviewingCurrent,
                    }.contains(c.phase))
                      OutlinedButton(
                        onPressed: c.readCurrent,
                        child: Text(t('只读取当前配置')),
                      ),
                    if (c.phase == AdminAiPhase.reviewingCurrent &&
                        c.current != null) ...[
                      Text(
                        t('当前服务器配置（密钥始终隐藏）'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final key in AdminAiSettingsController.fields)
                        if (key != 'ai_api_key')
                          SelectableText(
                            '$key: ${c.current!.records[key]?.value ?? ''}',
                          ),
                      Text(
                        c.current!.ai.apiKey?.isNotEmpty == true
                            ? t('API Key：已设置')
                            : t('API Key：未设置'),
                      ),
                      FilledButton(
                        onPressed: c.adoptReviewedCurrent,
                        child: Text(t('采用核对后的服务器配置')),
                      ),
                    ],
                    if (ready) ...[
                      _card(t('连接配置'), [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t('启用 AI')),
                          value: c.draft['ai_enabled'] == '1',
                          onChanged: c.editable
                              ? (value) =>
                                    c.edit('ai_enabled', value ? '1' : '0')
                              : null,
                        ),
                        _provider(),
                        _field('ai_base_url', t('接口地址')),
                        _field('ai_api_key', 'API Key'),
                        _field('ai_model', t('模型')),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: c.testRunning
                                ? c.cancelTest
                                : c.editable
                                ? c.testConnection
                                : null,
                            icon: Icon(
                              c.testRunning
                                  ? Icons.close
                                  : Icons.monitor_heart_outlined,
                            ),
                            label: Text(
                              c.testRunning ? t('取消测试') : t('测试当前配置'),
                            ),
                          ),
                        ),
                        Text(t('测试不会保存，可能产生模型调用。')),
                        if (c.testUsesSavedFallback)
                          Text(t('空的连接字段会回退到服务器已保存的配置。')),
                        if (c.testStale) Text(t('测试结果已过期，请重新测试。')),
                        if (c.testOutcome != null && !c.testStale)
                          Text(
                            c.testOutcome!.connected
                                ? t('连接测试成功')
                                : t('连接测试失败'),
                          ),
                      ]),
                      _card(t('生成参数'), [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final temperature = _field(
                              'ai_temperature',
                              t('温度'),
                              number: true,
                            );
                            final tokens = _field(
                              'ai_max_tokens',
                              t('最大输出'),
                              number: true,
                            );
                            if (constraints.maxWidth < 340 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    20) {
                              return Column(children: [temperature, tokens]);
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: temperature),
                                const SizedBox(width: 12),
                                Expanded(child: tokens),
                              ],
                            );
                          },
                        ),
                      ]),
                      AdminSettingsLink(
                        title: t('系统提示词'),
                        subtitle: t('Markdown、HTML、画板'),
                        icon: Icons.chat_outlined,
                        onTap: c.editable
                            ? () => _leave(destination: widget.onPrompts)
                            : null,
                      ),
                      AdminSettingsLink(
                        title: t('编辑动作'),
                        subtitle: t('选择、全文与扩写指令'),
                        icon: Icons.edit_outlined,
                        onTap: c.editable
                            ? () => _leave(destination: widget.onActions)
                            : null,
                      ),
                      Material(
                        color: const Color(0xffedf4ff),
                        borderRadius: BorderRadius.circular(12),
                        child: ExpansionTile(
                          title: Text(t('AI 累计用量')),
                          initiallyExpanded: true,
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            _usageRow(
                              t('输入 Tokens'),
                              c.baseline!.ai.usage.promptTokens,
                            ),
                            _usageRow(
                              t('输出 Tokens'),
                              c.baseline!.ai.usage.completionTokens,
                            ),
                            _usageRow(t('请求次数'), c.baseline!.ai.usage.requests),
                            const SizedBox(height: 12),
                            Text(t('只读统计，以服务器返回为准；缺失时显示未提供。')),
                          ],
                        ),
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
                      c.phase == AdminAiPhase.saving ? t('正在保存…') : t('保存配置'),
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
