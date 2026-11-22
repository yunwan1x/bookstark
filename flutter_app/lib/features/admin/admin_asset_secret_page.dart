import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_asset_secure_window.dart';
import 'admin_asset_secret_lease.dart';
import 'admin_community_widgets.dart';

class AdminAssetSecretPage extends StatefulWidget {
  const AdminAssetSecretPage({
    super.key,
    required this.title,
    required this.details,
    required this.onReveal,
    required this.onHide,
    required this.onReturn,
    this.english = false,
    this.secureWindow,
  });
  final String title;
  final List<(String, String)> details;
  final Future<AdminAssetSecretLease> Function() onReveal;
  final VoidCallback onHide, onReturn;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  @override
  State<AdminAssetSecretPage> createState() => _SecretPageState();
}

class _SecretPageState extends State<AdminAssetSecretPage>
    with WidgetsBindingObserver {
  late final AdminAssetWindowGuard _secure;
  AdminAssetSecretLease? _secret;
  Timer? _timer;
  bool _ready = false, _secureFailed = false, _loading = false, _failed = false;
  int _generation = 0;
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
          _secureFailed = true;
        });
      }
    }
  }

  void _clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _secret?.close();
    _secret = null;
    widget.onHide();
    _loading = false;
    _failed = false;
  }

  void _hide() {
    _clear();
    if (mounted) setState(() {});
  }

  Future<void> _reveal() async {
    if (!_ready || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final lease = await widget.onReveal();
      if (!mounted || generation != _generation) {
        lease.close();
        return;
      }
      setState(() {
        _secret = lease;
        _loading = false;
      });
      _timer = Timer(const Duration(seconds: 60), _hide);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _leave() {
    _clear();
    widget.onReturn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    unawaited(_secure.close());
    super.dispose();
  }

  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final value = _secret?.value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.title),
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
              Text(t('服务器空间', 'Server workspace')),
              const SizedBox(height: 20),
              _card(t('基本资料', 'Basic information'), [
                for (final (label, value) in widget.details)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        const SizedBox(height: 4),
                        Text(value),
                      ],
                    ),
                  ),
              ]),
              _card(t('保存的秘密', 'Stored secret'), [
                if (value == null) ...[
                  const Icon(Icons.visibility_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '••••••••',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28),
                  ),
                ] else
                  Text(
                    value.isEmpty ? t('秘密为空。', 'The secret is empty.') : value,
                    key: const ValueKey('asset-revealed-secret'),
                  ),
                const SizedBox(height: 16),
                Text(
                  t(
                    '默认隐藏，离开或切到后台后自动隐藏。',
                    'Hidden by default. Leaving or backgrounding hides it.',
                  ),
                ),
                const SizedBox(height: 20),
                if (_secureFailed)
                  AdminCommunityInfo(
                    text: t(
                      '无法启用安全窗口，不能显示秘密。',
                      'Secure window unavailable. Secret display is blocked.',
                    ),
                    tone: AdminCommunityTone.danger,
                  ),
                if (_failed)
                  AdminCommunityInfo(
                    text: t(
                      '无法读取秘密，请返回刷新资料后重试。',
                      'Could not read the secret. Return, refresh data and try again.',
                    ),
                    tone: AdminCommunityTone.warning,
                  ),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  OutlinedButton(
                    onPressed: !_ready
                        ? null
                        : value == null
                        ? _reveal
                        : _hide,
                    child: Text(
                      value == null
                          ? t('显示秘密', 'Show secret')
                          : t('隐藏秘密', 'Hide secret'),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  t(
                    '仅在本页临时查看，60 秒后自动隐藏。',
                    'View temporarily on this page. Automatically hidden after 60 seconds.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ]),
              OutlinedButton(onPressed: _leave, child: Text(t('返回', 'Back'))),
            ],
          ),
        ),
      ),
    );
  }
}
