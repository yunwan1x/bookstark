import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/go_text.dart';
import 'admin_asset_secure_window.dart';
import 'admin_community_widgets.dart';

/// New replacement input only. Never receives an existing server secret.
class AdminAssetPrivateKeyPage extends StatefulWidget {
  const AdminAssetPrivateKeyPage({
    super.key,
    required this.onApply,
    required this.onReturn,
    this.english = false,
    this.secureWindow,
  });
  final ValueChanged<String> onApply;
  final VoidCallback onReturn;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  @override
  State<AdminAssetPrivateKeyPage> createState() => _PrivateKeyState();
}

class _PrivateKeyState extends State<AdminAssetPrivateKeyPage>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late final AdminAssetWindowGuard _secure;
  bool _ready = false, _failed = false, _cleared = false, _invalid = false;
  String t(String zh, String en) => widget.english ? en : zh;

  @override
  void initState() {
    super.initState();
    _secure = widget.secureWindow ?? AdminAssetSecureWindow();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enable());
  }

  Future<void> _enable() async {
    try {
      await _secure.acquire();
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _text.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        setState(() {
          _cleared = true;
          _invalid = false;
        });
      }
    }
  }

  void _leave() {
    _text.clear();
    widget.onReturn();
  }

  void _apply() {
    final value = _text.text;
    if (trimGoSpace(value).isEmpty) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    _text.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onApply(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.clear();
    _text.dispose();
    unawaited(_secure.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(t('编辑私钥', 'Edit private key')),
        leading: IconButton(
          onPressed: _leave,
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminCommunityInfo(
              text: t(
                '此页面会显示你输入的私钥，请留意周围环境。',
                'This page shows your private-key input. Check your surroundings.',
              ),
              tone: AdminCommunityTone.warning,
            ),
            const SizedBox(height: 20),
            if (_failed)
              AdminCommunityInfo(
                text: t(
                  '无法启用安全窗口，不能输入私钥。',
                  'Secure window unavailable. Private-key input is blocked.',
                ),
                tone: AdminCommunityTone.danger,
              )
            else if (!_ready)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_cleared) ...[
                AdminCommunityInfo(
                  text: t(
                    '切换到后台后已清除输入，请重新填写。',
                    'Input was cleared in the background. Enter it again.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const ValueKey('asset-private-key-input'),
                controller: _text,
                minLines: 12,
                maxLines: 20,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  labelText: t('私钥内容', 'Private key'),
                  hintText: t(
                    '粘贴完整私钥，保留换行。',
                    'Paste the complete private key, preserving line breaks.',
                  ),
                  border: const OutlineInputBorder(),
                  errorText: _invalid
                      ? t('请输入完整私钥。', 'Enter a private key.')
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '返回后仅显示已填写状态。',
                  'Only a filled status is shown after returning.',
                ),
              ),
            ],
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final cancel = OutlinedButton(
                  onPressed: _leave,
                  child: Text(t('取消', 'Cancel')),
                );
                final apply = FilledButton(
                  onPressed: _ready && !_failed ? _apply : null,
                  child: Text(t('使用此私钥', 'Use this private key')),
                );
                if (constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(16) > 24) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cancel, const SizedBox(height: 8), apply],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: 12),
                    Expanded(child: apply),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
