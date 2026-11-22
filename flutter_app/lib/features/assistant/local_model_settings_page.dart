import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/local_model_config.dart';
import 'local_model_settings_controller.dart';

class LocalModelSettingsPage extends StatefulWidget {
  const LocalModelSettingsPage({
    super.key,
    required this.controller,
    this.english = false,
  });
  final LocalModelSettingsController controller;
  final bool english;
  @override
  State<LocalModelSettingsPage> createState() => _LocalModelSettingsPageState();
}

class _LocalModelSettingsPageState extends State<LocalModelSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _endpoint = TextEditingController(),
      _model = TextEditingController(),
      _key = TextEditingController();
  bool _showKey = false, _allowExit = false, _confirming = false;
  LocalModelSettingsController get state => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    state.addListener(_changed);
    unawaited(state.load());
  }

  void _changed() {
    if (!mounted) return;
    for (final entry in [
      (_endpoint, state.endpoint),
      (_model, state.model),
      (_key, state.apiKey),
    ]) {
      if (entry.$1.text != entry.$2) entry.$1.text = entry.$2;
    }
    setState(() {});
  }

  @override
  void dispose() {
    state.removeListener(_changed);
    state.dispose();
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    if (state.retired) {
      await _finish();
      return;
    }
    if (state.saving || _confirming) return;
    state.cancelTest();
    if (state.dirty || state.unknown) {
      _confirming = true;
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('离开模型配置？', 'Leave model settings?')),
          content: Text(
            state.unknown
                ? t(
                    '保存结果尚未确认。再次打开会读取实际配置，当前表单可能尚未保存。',
                    'The save result is unknown. Reopening reads the stored configuration; your current form may not be saved.',
                  )
                : t('当前修改尚未保存。', 'Your changes have not been saved.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('继续编辑', 'Keep editing')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('放弃并离开', 'Leave anyway')),
            ),
          ],
        ),
      );
      _confirming = false;
      if (yes != true || !mounted) return;
    }
    await _finish();
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    if (await state.save() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('配置已保存', 'Configuration saved'))),
      );
    }
  }

  Future<void> _test() async {
    if (_form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    await state.testConnection();
  }

  Future<void> _reset() async {
    if (_confirming || state.busy) return;
    _confirming = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('清除本地模型配置？', 'Clear local model configuration?')),
        content: Text(
          t(
            '只清除当前本地空间的模型地址、密钥和检索授权。笔记、会话、书籍与附件不会删除。',
            'Clear only this local space’s model endpoint, credential and knowledge permission. Notes, conversations, books and attachments remain.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('清除配置', 'Clear configuration')),
          ),
        ],
      ),
    );
    _confirming = false;
    if (yes == true && mounted) await state.reset();
  }

  String? _validate(String? value, String field) {
    try {
      LocalModelConfig(
        endpoint: field == 'endpoint'
            ? value ?? ''
            : 'https://model.example.invalid',
        model: field == 'model' ? value ?? '' : 'validation',
        apiKey: field == 'key' ? value ?? '' : '',
      );
      return null;
    } on FormatException {
      return switch (field) {
        'endpoint' => t(
          '请输入有效的HTTP/HTTPS地址，不含账号、查询参数或片段。',
          'Use an HTTP/HTTPS address without credentials, query or fragment.',
        ),
        'model' => t(
          '请输入有效模型标识，最多256个UTF-8字节。',
          'Enter a valid model ID, up to 256 UTF-8 bytes.',
        ),
        _ => t(
          '密钥需为可见字符，不含空格或换行，最多8192字节。',
          'Use visible ASCII credential characters without whitespace, up to 8192 bytes.',
        ),
      };
    }
  }

  String get _probeLabel {
    if (state.probing) return t('正在测试…', 'Testing…');
    if (state.probeOK) return t('连接成功（当前表单）', 'Connected (current form)');
    return switch (state.probeIssue) {
      LocalModelProbeIssue.authentication => t(
        '认证失败，请核对密钥。',
        'Authentication failed. Check the credential.',
      ),
      LocalModelProbeIssue.busy => t(
        '服务繁忙，请稍后重试。',
        'Service is busy. Retry later.',
      ),
      LocalModelProbeIssue.redirect => t(
        '服务返回重定向，请填写最终服务地址。',
        'The service redirects. Enter its final endpoint.',
      ),
      LocalModelProbeIssue.protocol => t(
        '服务响应不符合兼容模型协议。',
        'The response does not match the compatible model protocol.',
      ),
      LocalModelProbeIssue.timeout => t(
        '连接测试超时，请重试。',
        'The connection test timed out. Retry.',
      ),
      LocalModelProbeIssue.network => t(
        '连接测试失败，请检查地址、网络和模型。',
        'Connection failed. Check the endpoint, network and model.',
      ),
      null => t('尚未测试', 'Not tested'),
    };
  }

  Widget _problem() {
    final corrupt = state.problem is LocalModelConfigCorrupt;
    final message = state.unknown
        ? t(
            '保存结果尚未确认，请先重新读取核对，不要重复保存。',
            'The save result is unknown. Read back before saving again.',
          )
        : corrupt
        ? t(
            '本地模型配置无法读取，原记录仍保留。可重试或明确清除此配置。',
            'The stored model configuration is unreadable and has been retained. Retry or explicitly clear this configuration.',
          )
        : t(
            '配置操作未完成，请重试。',
            'The configuration operation did not finish. Retry.',
          );
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: state.busy ? null : state.load,
            child: Text(
              state.unknown
                  ? t('重新读取核对', 'Read back configuration')
                  : t('重试读取', 'Retry loading'),
            ),
          ),
          if (corrupt)
            TextButton(
              onPressed: state.busy ? null : _reset,
              child: Text(t('清除损坏配置', 'Clear corrupt configuration')),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        state.loaded && !state.busy && !state.unknown && !state.retired;
    final test = OutlinedButton(
      onPressed: state.probing
          ? state.cancelTest
          : enabled
          ? _test
          : null,
      child: Text(
        state.probing ? t('取消测试', 'Cancel test') : t('测试连接', 'Test connection'),
      ),
    );
    final save = FilledButton(
      onPressed: enabled && state.dirty ? _save : null,
      child: Text(
        state.saving ? t('正在保存…', 'Saving…') : t('保存配置', 'Save configuration'),
      ),
    );
    return PopScope<Object?>(
      canPop:
          _allowExit ||
          (!state.dirty && !state.unknown && !state.saving && !state.probing),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 28
              ? 112
              : 56,
          leading: BackButton(onPressed: _leave),
          title: Text(t('本地模型配置', 'Local model settings')),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  const Icon(Icons.storage_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('本地空间 · 当前数据库', 'Local space · Current database'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffeff6ff),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  t(
                    '问答内容会发送到你配置的模型服务',
                    'Questions and answers are sent to your configured model service',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (state.loading) const LinearProgressIndicator(),
              if (state.problem != null) _problem(),
              if (state.readbackDifferent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t(
                      '已读取实际配置，当前表单仍保留。保存会替换实际配置。',
                      'Stored configuration was read. Your form is retained; saving replaces the stored configuration.',
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('服务地址', 'Service endpoint'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('local-model-endpoint'),
                        controller: _endpoint,
                        enabled: enabled,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.url,
                        validator: (v) => _validate(v, 'endpoint'),
                        onChanged: (v) => state.edit(endpoint: v),
                        decoration: InputDecoration(
                          errorMaxLines: 10,
                          hintText: 'https://model.example.com/v1',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t('模型名称', 'Model ID'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('local-model-name'),
                        controller: _model,
                        enabled: enabled,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (v) => _validate(v, 'model'),
                        onChanged: (v) => state.edit(model: v),
                        decoration: InputDecoration(
                          errorMaxLines: 10,
                          hintText: t('输入模型标识', 'Enter a model ID'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t('API 密钥', 'API credential'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('local-model-key'),
                        controller: _key,
                        enabled: enabled,
                        obscureText: !_showKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (v) => _validate(v, 'key'),
                        onChanged: (v) => state.edit(apiKey: v),
                        decoration: InputDecoration(
                          errorMaxLines: 10,
                          helperText: t(
                            '仅加密保存在本机，可留空',
                            'Encrypted on this device; optional',
                          ),
                          helperMaxLines: 3,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _showKey
                                ? t('隐藏密钥', 'Hide credential')
                                : t('显示密钥', 'Show credential'),
                            onPressed: enabled
                                ? () => setState(() => _showKey = !_showKey)
                                : null,
                            icon: Icon(
                              _showKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          t('允许本地知识检索', 'Allow local knowledge search'),
                        ),
                        subtitle: Text(
                          t(
                            '开启后，模型可请求检索当前本地空间的资料',
                            'When enabled, the model may request searches of this local space',
                          ),
                        ),
                        value: state.allowKnowledge,
                        onChanged: enabled
                            ? (v) => state.edit(allowKnowledge: v)
                            : null,
                      ),
                      const Divider(height: 32),
                      Semantics(
                        key: const Key('local-model-probe-status'),
                        container: true,
                        liveRegion: true,
                        label: _probeLabel,
                        excludeSemantics: true,
                        child: Text(_probeLabel),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, box) =>
                            MediaQuery.textScalerOf(context).scale(14) > 18 ||
                                box.maxWidth < 260
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  test,
                                  const SizedBox(height: 12),
                                  save,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: test),
                                  const SizedBox(width: 12),
                                  Expanded(child: save),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t(
                  '模型配置和密钥不会随内容备份导出。',
                  'Model settings and credentials are excluded from content backups.',
                ),
              ),
              if (state.loaded && state.saved != null)
                TextButton(
                  onPressed: state.busy || state.unknown ? null : _reset,
                  child: Text(t('清除模型配置', 'Clear model configuration')),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
