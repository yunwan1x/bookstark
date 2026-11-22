import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/local_legacy_format_selection.dart';
import '../../core/native_local_content_crypto.dart';
import '../admin/admin_asset_secure_window.dart';
import 'legacy_format_ui.dart';

typedef LegacyPreviewUnlocker =
    Future<String> Function(
      LegacyFormatItem item,
      String password,
      AttachmentCancellation cancellation,
    );

/// A temporary escaped text excerpt, never an HTML/document execution context.
class LocalLegacyPreviewPage extends StatefulWidget {
  const LocalLegacyPreviewPage({
    super.key,
    required this.item,
    required this.isCurrentScope,
    this.selectedFormat,
    this.english = false,
    this.unlocker,
    this.windowGuardFactory,
  });
  final LegacyFormatItem item;
  final bool Function() isCurrentScope;
  final LegacyContentFormat? selectedFormat;
  final bool english;
  final LegacyPreviewUnlocker? unlocker;
  final AdminAssetWindowGuard Function()? windowGuardFactory;
  @override
  State<LocalLegacyPreviewPage> createState() => _LocalLegacyPreviewPageState();
}

class _LocalLegacyPreviewPageState extends State<LocalLegacyPreviewPage>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  AdminAssetWindowGuard? _window;
  AttachmentCancellation? _request;
  LegacyContentFormat? _format;
  String? _snippet;
  LocalContentCryptoReason? _error;
  bool _secureReady = false,
      _secureFailed = false,
      _busy = false,
      _obscure = true,
      _leaving = false,
      _active = true;
  int _epoch = 0, _windowEpoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current =>
      mounted && !_leaving && _active && widget.isCurrentScope();

  @override
  void initState() {
    super.initState();
    _format = widget.selectedFormat;
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableSecure());
  }

  void _closeAfterFrame(AdminAssetWindowGuard? guard) {
    if (guard == null) return;
    // Clear the rendered input/excerpt before releasing its screenshot lease.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(guard.close().catchError((Object _) {}));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _retire() {
    _epoch++;
    _windowEpoch++;
    _request?.cancel();
    _request = null;
    _password.clear();
    _snippet = null;
    _error = null;
    _busy = false;
    _obscure = true;
    _secureReady = false;
    final guard = _window;
    _window = null;
    _closeAfterFrame(guard);
  }

  Future<void> _enableSecure() async {
    if (!current || _window != null || _secureReady) return;
    final epoch = ++_windowEpoch;
    AdminAssetWindowGuard? guard;
    try {
      guard = widget.windowGuardFactory?.call() ?? AdminAssetSecureWindow();
      _window = guard;
      await guard.acquire();
      if (!current || epoch != _windowEpoch) {
        _closeAfterFrame(guard);
        return;
      }
      setState(() {
        _secureReady = true;
        _secureFailed = false;
        if (!widget.item.isProtected) {
          _snippet = String.fromCharCodes(
            widget.item.originalBody.runes.take(2048),
          );
        }
      });
    } catch (_) {
      if (identical(_window, guard)) _window = null;
      _closeAfterFrame(guard);
      if (current && epoch == _windowEpoch) {
        setState(() {
          _secureReady = false;
          _secureFailed = true;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      if (mounted && !_leaving) {
        setState(() => _secureFailed = false);
        unawaited(_enableSecure());
      }
    } else {
      _active = false;
      _retire();
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant LocalLegacyPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item)) {
      _retire();
      _format = widget.selectedFormat;
      _secureFailed = false;
      unawaited(_enableSecure());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retire();
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!current || !_secureReady || _busy || _password.text.isEmpty) return;
    final epoch = ++_epoch;
    final cancellation = AttachmentCancellation();
    _request = cancellation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = widget.unlocker == null
          ? await NativeLocalContentCrypto().unlock(
              password: _password.text,
              passwordHash: widget.item.passwordHash,
              body: widget.item.originalBody,
              cancellation: cancellation,
            )
          : await widget.unlocker!(widget.item, _password.text, cancellation);
      if (!current || epoch != _epoch || cancellation.cancelled) return;
      setState(() {
        _snippet = String.fromCharCodes(value.runes.take(2048));
        _password.clear();
        _error = null;
      });
    } on LocalContentCryptoFailure catch (error) {
      if (current && epoch == _epoch && !cancellation.cancelled) {
        setState(() => _error = error.reason);
      }
    } catch (_) {
      if (current && epoch == _epoch && !cancellation.cancelled) {
        setState(() => _error = LocalContentCryptoReason.unavailable);
      }
    } finally {
      if (identical(_request, cancellation)) _request = null;
      if (current && epoch == _epoch) setState(() => _busy = false);
    }
  }

  String _errorText(LocalContentCryptoReason reason) => switch (reason) {
    LocalContentCryptoReason.wrongPassword => t(
      '密码不正确，请重试',
      'Incorrect password. Try again.',
    ),
    LocalContentCryptoReason.unsupported => t(
      '此内容的保护格式暂不支持预览',
      'This protection format cannot be previewed.',
    ),
    LocalContentCryptoReason.invalidContent => t(
      '原文无法解密，请核对备份文件',
      'Could not decrypt the source. Check the backup.',
    ),
    LocalContentCryptoReason.busy => t(
      '另一次解锁尚未结束，请稍后重试',
      'Another unlock is still finishing. Try again shortly.',
    ),
    LocalContentCryptoReason.cancelled => t('已取消预览', 'Preview cancelled'),
    LocalContentCryptoReason.unavailable => t(
      '暂时无法预览，请重试',
      'Preview unavailable. Try again.',
    ),
  };
  void _leave([LegacyContentFormat? format]) {
    if (_leaving || !mounted) return;
    if (format != null && (!current || _snippet == null)) return;
    setState(() {
      _leaving = true;
      _retire();
    });
    Navigator.of(context).pop(format);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title.isEmpty
        ? t('未命名', 'Untitled')
        : widget.item.title;
    final valid = widget.isCurrentScope();
    return LegacyFormatFrame(
      title: _snippet == null
          ? t('解锁后预览', 'Unlock to preview')
          : t('原文片段', 'Source excerpt'),
      onBack: () => _leave(),
      content: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            );
            final badge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xffe5efff),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t('只读预览', 'Read-only preview'),
                style: const TextStyle(color: legacyBlue, fontSize: 14),
              ),
            );
            if (_snippet == null || !valid) return heading;
            if (constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 8), badge],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                badge,
              ],
            );
          },
        ),
        if (!valid)
          Text(
            t('来源已失效，请返回重新选择', 'Source expired. Go back and choose it again.'),
          )
        else if (!_active)
          Text(
            t('预览已锁定，返回后重新解锁', 'Preview locked. Unlock again when you return.'),
          )
        else if (_secureFailed)
          Text(
            t(
              '无法开启受保护预览，请返回后重试',
              'Protected preview could not start. Go back and try again.',
            ),
          )
        else if (!_secureReady)
          Text(t('正在开启受保护预览', 'Opening protected preview'))
        else if (_snippet != null) ...[
          Container(
            key: const ValueKey('legacy-preview-snippet'),
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xffeff0f3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _snippet!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
          ),
          LegacyFormatDropdown(
            value: _format,
            english: widget.english,
            onChanged: (value) => setState(() => _format = value),
          ),
          Text(t('返回时关闭预览', 'Preview closes when you go back.')),
        ] else ...[
          LegacyFormatInfo(
            t('密码仅用于此次预览', 'The password is used only for this preview.'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text(t('原密码', 'Original password'))),
              const SizedBox(height: 8),
              Semantics(
                label: t('原密码', 'Original password'),
                child: TextField(
                  key: const ValueKey('legacy-preview-password'),
                  controller: _password,
                  obscureText: _obscure,
                  enabled: !_busy,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autocorrect: false,
                  autofillHints: const [],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _unlock(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIconColor: legacyInk,
                    errorText: _error == null ? null : _errorText(_error!),
                    errorMaxLines: 5,
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? t('显示密码', 'Show password')
                          : t('隐藏密码', 'Hide password'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
      actions: [
        if (valid && _active && _secureReady && _snippet == null)
          FilledButton(
            onPressed: _busy || _password.text.isEmpty ? null : _unlock,
            child: Text(
              _busy ? t('正在解锁', 'Unlocking') : t('解锁并预览', 'Unlock and preview'),
              textAlign: TextAlign.center,
            ),
          ),
        if (valid && _active && _secureReady && _snippet != null)
          FilledButton(
            onPressed: _format == null ? null : () => _leave(_format),
            child: Text(
              t('使用此格式', 'Use this format'),
              textAlign: TextAlign.center,
            ),
          ),
        OutlinedButton(
          onPressed: () => _leave(),
          child: Text(
            t('返回选择', 'Back to choices'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
