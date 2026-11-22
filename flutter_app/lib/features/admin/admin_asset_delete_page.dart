import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_community_widgets.dart';

class AdminAssetDeletePage extends StatefulWidget {
  const AdminAssetDeletePage({
    super.key,
    required this.onConfirm,
    required this.onCancel,
    this.host,
    this.credential,
    this.english = false,
  }) : assert((host == null) != (credential == null));
  final AdminAssetHostMetadata? host;
  final AdminAssetCredentialMetadata? credential;
  final Future<void> Function() onConfirm;
  final VoidCallback onCancel;
  final bool english;
  @override
  State<AdminAssetDeletePage> createState() => _DeletePageState();
}

class _DeletePageState extends State<AdminAssetDeletePage> {
  bool _busy = false, _failed = false, _attempted = false;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<void> _confirm() async {
    if (_busy || _attempted) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _failed = false;
    });
    try {
      await widget.onConfirm();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final credential = widget.credential;
    final title = host != null
        ? t('删除 SSH 主机', 'Delete SSH host')
        : t('删除凭据', 'Delete credential');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) widget.onCancel();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            onPressed: _busy ? null : widget.onCancel,
            tooltip: t('返回', 'Back'),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminCommunityInfo(
                tone: AdminCommunityTone.danger,
                text: host != null
                    ? t(
                        '仅删除保存的主机记录，不会删除远端服务器或关联凭据。',
                        'Deletes only the saved host record. The remote server and linked credential remain.',
                      )
                    : t(
                        '此操作无法恢复。若仍被 SSH 主机或 WebDAV 引用，服务器将拒绝删除。',
                        'This cannot be undone. The server refuses deletion while referenced by SSH hosts or WebDAV.',
                      ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host?.name ?? credential!.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (host != null) Text('${host.host}:${host.port}'),
                    Text(
                      '${t('用户名', 'Username')}: ${host?.username ?? credential!.username}',
                    ),
                    Text('ID: ${host?.id ?? credential!.id}'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (host != null)
                Text(
                  t(
                    '删除后需重新添加才能在应用中访问。',
                    'Add the host again to access it from this app after deletion.',
                  ),
                ),
              if (_failed)
                AdminCommunityInfo(
                  text: t(
                    '操作未完成，请返回核对资料。',
                    'The operation did not complete. Return to review data.',
                  ),
                  tone: AdminCommunityTone.warning,
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy || _attempted ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffbf2637),
                ),
                child: Text(
                  _busy
                      ? t('正在提交', 'Submitting')
                      : host != null
                      ? t('确认删除主机', 'Confirm host deletion')
                      : t('确认删除凭据', 'Confirm credential deletion'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : widget.onCancel,
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
