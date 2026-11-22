import '../speech/local_speech_provider_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import '../../core/public_complex_source.dart';
import 'public_complex_readonly_body.dart';

class PublicComplexSourceBody extends StatefulWidget {
  const PublicComplexSourceBody({
    super.key,
    required this.reference,
    required this.expectedKind,
    required this.scopeKey,
    required this.isCurrent,
    required this.onReload,
    required this.onExternalLink,
    required this.markdownBody,
    this.chapterIdentify,
    this.onSpeakSelection,
    this.english = false,
    this.sourceFactory,
    this.onReadabilityChanged,
  });
  final PublicShareReference reference;
  final ComplexEditorKind expectedKind;
  final String? chapterIdentify;
  final Object scopeKey;
  final bool Function() isCurrent;
  final Future<void> Function() onReload;
  final Future<void> Function(Uri) onExternalLink;
  final Widget Function(BuildContext, PublicComplexContent) markdownBody;
  final AnonymousPublicComplexSource Function(bool Function())? sourceFactory;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final bool english;
  final void Function(PublicComplexContent?)? onReadabilityChanged;
  @override
  State<PublicComplexSourceBody> createState() => _SourceState();
}

class _SourceState extends State<PublicComplexSourceBody> {
  AnonymousPublicComplexSource? _source;
  PublicComplexContent? _content;
  String? _readPassword;
  bool _loading = true, _locked = false, _failed = false;
  int _epoch = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  bool current(int epoch) => mounted && epoch == _epoch && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PublicComplexSourceBody old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference ||
        old.chapterIdentify != widget.chapterIdentify ||
        old.scopeKey != widget.scopeKey ||
        old.expectedKind != widget.expectedKind) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _epoch++;
    _source?.close();
    _content = null;
    _readPassword = null;
    super.dispose();
  }

  Future<bool> _load({String? password}) async {
    final epoch = ++_epoch;
    widget.onReadabilityChanged?.call(null);
    _source?.close();
    _readPassword = null;
    setState(() {
      _content = null;
      _loading = true;
      _locked = false;
      _failed = false;
    });
    try {
      final source = _source =
          widget.sourceFactory?.call(() => current(epoch)) ??
          AnonymousPublicComplexSource(isCurrent: () => current(epoch));
      final content = await source.read(
        widget.reference,
        chapterIdentify: widget.chapterIdentify,
        password: password,
      );
      if (!current(epoch)) return false;
      if (content.document.kind != widget.expectedKind) {
        throw const PublicComplexReadFailure();
      }
      setState(() {
        _content = content;
        _readPassword = password;
        _loading = false;
      });
      if (current(epoch)) widget.onReadabilityChanged?.call(content);
      return true;
    } on PublicComplexLocked {
      if (current(epoch)) {
        setState(() {
          _locked = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (current(epoch)) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
    return false;
  }

  Future<void> _unlock() async {
    final reference = widget.reference,
        scope = widget.scopeKey,
        kind = widget.expectedKind;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UnlockDialog(
        english: widget.english,
        submit: (password) async {
          if (!mounted ||
              widget.reference != reference ||
              widget.scopeKey != scope ||
              widget.expectedKind != kind ||
              !widget.isCurrent()) {
            return false;
          }
          return _load(password: password);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent()) return const SizedBox.shrink();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_locked) {
      return Column(
        children: [
          const Icon(Icons.lock_outline),
          Text(t('输入密码后阅读', 'Enter a password to read')),
          FilledButton(
            onPressed: _unlock,
            child: Text(t('解锁阅读', 'Unlock reading')),
          ),
        ],
      );
    }
    if (_failed || _content == null) {
      return Column(
        children: [
          Text(t('分享暂不可用', 'Share unavailable')),
          Text(
            t(
              '链接可能已撤回，或暂时无法连接。',
              'The link may be revoked or temporarily unavailable.',
            ),
          ),
          OutlinedButton(
            onPressed: widget.onReload,
            child: Text(t('重试', 'Retry')),
          ),
        ],
      );
    }
    final epoch = _epoch;
    return PublicComplexReadOnlyBody(
      key: ValueKey((epoch, widget.scopeKey)),
      content: _content!,
      scopeKey: widget.scopeKey,
      isCurrent: () => current(epoch),
      markdownBody: widget.markdownBody,
      onReload: widget.onReload,
      onExternalLink: widget.onExternalLink,
      english: widget.english,
      onSpeakSelection: widget.onSpeakSelection,
      freshSource: () async {
        final active = _source;
        if (active == null || !current(epoch)) {
          throw StateError('Public reader retired');
        }
        final fresh = await active.read(
          widget.reference,
          chapterIdentify: widget.chapterIdentify,
          password: _readPassword,
        );
        if (!current(epoch)) throw StateError('Public reader retired');
        return fresh;
      },
    );
  }
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.english, required this.submit});
  final bool english;
  final Future<bool> Function(String) submit;
  @override
  State<_UnlockDialog> createState() => _UnlockState();
}

class _UnlockState extends State<_UnlockDialog> {
  final _password = TextEditingController();
  bool _busy = false, _visible = false, _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    bool success;
    try {
      success = await widget.submit(_password.text);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    if (success) {
      _password.clear();
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(t('解锁分享', 'Unlock share')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_visible,
              decoration: InputDecoration(
                labelText: t(
                  '输入作者设置的密码',
                  'Enter the password set by the author',
                ),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (_failed)
              Text(
                t(
                  '无法解锁，请核对密码和连接。',
                  'Unable to unlock. Check the password and connection.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(t('解锁', 'Unlock')),
        ),
      ],
    ),
  );
}
