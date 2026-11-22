import '../../core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/public_edit_link.dart';
import '../../core/public_edit_repository.dart';
import '../../core/public_edit_controller.dart';
import '../../core/public_shares_repository.dart';
import '../../core/public_share_models.dart';
import 'share_unlock_page.dart';
import 'share_edit_page.dart';

class ShareEditLinkPage extends StatefulWidget {
  const ShareEditLinkPage({
    super.key,
    required this.server,
    required this.repository,
    required this.shares,
    required this.attachments,
    this.english = false,
    this.openComplex,
  });
  final Uri server;
  final PublicEditRepository repository;
  final PublicSharesRepository shares;
  final AttachmentRepository attachments;
  final bool english;
  final Future<bool> Function(BuildContext, PublicEditLink)? openComplex;
  @override
  State<ShareEditLinkPage> createState() => _ShareEditLinkPageState();
}

class _ShareEditLinkPageState extends State<ShareEditLinkPage> {
  final _link = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _abort = Completer<void>();
  PublicEditController? _session;
  bool _busy = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    _session?.close();
    _link.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    PublicEditController? controller;
    try {
      final link = PublicEditLink.parse(widget.server, _link.text);
      final complex = widget.openComplex;
      if (complex != null && await complex(context, link)) return;
      if (!mounted) return;
      controller = PublicEditController(widget.repository, link);
      _session = controller;
      await controller.initialize(abortTrigger: _abort.future);
      if (!mounted) return;
      if (controller.phase == PublicEditPhase.unsupported) {
        setState(
          () => _error = t(
            '此格式尚未接入共享编辑，请先返回只读阅读。',
            'Shared editing for this format is not available yet. Return to read-only viewing.',
          ),
        );
        return;
      }
      if (controller.phase == PublicEditPhase.locked) {
        var returnToReader = false;
        final current = controller;
        final unlocked = await Navigator.push<PublicShareDetail>(
          context,
          MaterialPageRoute(
            builder: (passwordContext) => ShareUnlockPage(
              detail: current.snapshot!.detail,
              repository: widget.shares,
              english: widget.english,
              editing: true,
              verifyPassword: (password, abort) async {
                await current.initialize(
                  password: password,
                  abortTrigger: abort,
                );
                if (current.phase != PublicEditPhase.ready) {
                  throw StateError('Protected editor is not ready');
                }
                return current.snapshot!.detail;
              },
              onReturnToReader: () {
                returnToReader = true;
                Navigator.pop(passwordContext);
              },
            ),
          ),
        );
        if (!mounted) return;
        if (returnToReader) {
          _link.clear();
          Navigator.pop(context);
          return;
        }
        if (unlocked == null) return;
      }
      if (controller.phase != PublicEditPhase.ready) {
        throw StateError('Editing link is not writable');
      }
      _link.clear();
      final editorRoute = MaterialPageRoute<void>(
        builder: (_) => ShareEditPage(
          controller: controller!,
          attachments: widget.attachments,
          english: widget.english,
        ),
      );
      await Navigator.push<void>(context, editorRoute);
      // The pop result precedes reverse-transition disposal. The outgoing page
      // still builds from this snapshot until its route has actually completed.
      await editorRoute.completed;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            '无法验证编辑链接，请核对链接、权限和网络后重试。',
            'Unable to verify the editing link. Check the link, permission and connection, then retry.',
          ),
        );
      }
    } finally {
      controller?.close();
      _session = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
    appBar: AppBar(
      title: Text(
        t('打开编辑链接', 'Open editing link'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: Color(0xff155af5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.link,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  t(
                    '使用分享者提供的编辑链接',
                    'Use the editing link provided by the sharer',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    '普通分享链接只能阅读。编辑链接可修改对应正文。',
                    'Ordinary share links are read-only. Editing links can modify the corresponding content.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t('编辑链接', 'Editing link'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _link,
                            enabled: !_busy,
                            minLines: 3,
                            maxLines: 6,
                            keyboardType: TextInputType.url,
                            autofillHints: const [],
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            decoration: InputDecoration(
                              hintText: t(
                                '粘贴当前服务器的完整编辑链接',
                                'Paste a complete editing link for the current server',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              try {
                                PublicEditLink.parse(
                                  widget.server,
                                  value ?? '',
                                );
                                return null;
                              } catch (_) {
                                return t(
                                  '请输入当前服务器的有效完整编辑链接',
                                  'Enter a valid complete editing link for the current server',
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t(
                              '链接仅在本次会话使用，不保存或加入公开分享。',
                              'The link is used only in this session. It is not saved or added to public sharing.',
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _busy ? null : _open,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            child: Text(
                              _busy
                                  ? t('正在验证…', 'Verifying…')
                                  : t('验证并打开', 'Verify and open'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xffe3edff),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Color(0xff155af5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('核对服务器与文档', 'Check the server and document'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t(
                                '只连接当前服务器。令牌失效、链接类型或权限变化时停止编辑。',
                                'Only the current server is contacted. Editing stops if the capability expires or the link type or permission changes.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  t(
                    '持有编辑链接即拥有编辑能力，请妥善保管。',
                    'Possession of the editing link grants editing capability. Keep it private.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
