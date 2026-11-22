import '../../core/complex_editor_transport.dart';
import '../speech/public_reading_speech_capture.dart';
import '../speech/local_speech_provider_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/public_shares/public_html_body.dart';
import '../../core/public_complex_source.dart';
import '../complex_editors/complex_editor_browser.dart';

/// Keep existing Markdown rendering supplied by the caller. No new MD engine.
/// Root uses this ONLY after the anonymous source loader returned a typed full
/// document; do not pass account client, token, password or raw URL to this body.
class PublicComplexReadOnlyBody extends StatefulWidget {
  const PublicComplexReadOnlyBody({
    super.key,
    required this.content,
    required this.scopeKey,
    required this.isCurrent,
    required this.markdownBody,
    required this.onReload,
    required this.onExternalLink,
    this.english = false,
    this.onSpeakSelection,
    this.freshSource,
  });
  final PublicComplexContent content;
  final Object scopeKey;
  final bool Function() isCurrent;
  final Widget Function(BuildContext, PublicComplexContent) markdownBody;
  final Future<void> Function() onReload;
  final Future<void> Function(Uri) onExternalLink;
  final bool english;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final Future<PublicComplexContent> Function()? freshSource;
  @override
  State<PublicComplexReadOnlyBody> createState() => _PublicBodyState();
}

class _PublicBodyState extends State<PublicComplexReadOnlyBody>
    with WidgetsBindingObserver {
  OwnedPreviewController _lease = OwnedPreviewController();
  bool _replacing = false, _askingExternal = false, _speaking = false;
  ComplexEditorTransport? _transport;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _epoch++;
      unawaited(_lease.retire().catchError((Object _) {}));
    }
  }

  int _epoch = 0;
  @override
  void didUpdateWidget(covariant PublicComplexReadOnlyBody old) {
    super.didUpdateWidget(old);
    if (old.scopeKey != widget.scopeKey ||
        old.content.reference != widget.content.reference ||
        old.content.chapterIdentify != widget.content.chapterIdentify ||
        !old.content.document.same(widget.content.document)) {
      _replacing = true;
      final epoch = ++_epoch, previous = _lease;
      unawaited(() async {
        await previous.retire();
        if (!mounted || epoch != _epoch || !widget.isCurrent()) return;
        setState(() {
          _lease = OwnedPreviewController();
          _replacing = false;
        });
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _epoch++;
    _lease.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await _lease.retire();
    if (mounted && widget.isCurrent()) await widget.onReload();
  }

  Future<void> _external(Uri uri) async {
    if (_askingExternal ||
        !mounted ||
        !widget.isCurrent() ||
        _lease.retired ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    _askingExternal = true;
    final epoch = _epoch, lease = _lease, scope = widget.scopeKey;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        scope == widget.scopeKey &&
        widget.isCurrent() &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    try {
      final launch = widget.onExternalLink;
      await openConfirmedPublicComplexExternal(
        confirm: () => confirmPublicComplexExternalLink(
          context,
          uri,
          english: widget.english,
        ),
        isCurrent: current,
        isRetired: () => lease.retired,
        retire: lease.retire,
        launch: () => launch(uri),
      );
    } finally {
      _askingExternal = false;
    }
  }

  Future<void> _speak() async {
    final transport = _transport,
        fresh = widget.freshSource,
        speak = widget.onSpeakSelection;
    if (_speaking ||
        transport == null ||
        fresh == null ||
        speak == null ||
        !widget.isCurrent() ||
        _lease.retired) {
      return;
    }
    final epoch = _epoch, lease = _lease, content = widget.content;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        identical(lease, _lease) &&
        !lease.retired &&
        widget.isCurrent() &&
        identical(content, widget.content);
    setState(() => _speaking = true);
    try {
      final captured = await capturePublicReadingSpeech(
        transport: transport,
        identity: publicSpeechIdentity(content),
        isCurrent: current,
        freshSource: fresh,
      );
      if (current()) {
        await speak(
          captured,
          content.title,
          content.reference.canonicalUri.toString(),
        );
      }
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.english
                  ? 'Select readable content and retry. The source or selection may have changed.'
                  : '请先选择可读内容后重试，原文或选区可能已变化。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent() || _replacing) return const SizedBox.shrink();
    final content = widget.content, document = content.document;
    if (document.kind == ComplexEditorKind.markdown) {
      return widget.markdownBody(context, content);
    }
    if (document.kind == ComplexEditorKind.html) {
      return PublicHtmlBody(
        key: ValueKey((widget.scopeKey, content.reference, document.digest)),
        source: document.source,
        server: content.reference.server,
        english: widget.english,
      );
    }
    final viewEpoch = _epoch, viewLease = _lease;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onSpeakSelection != null && widget.freshSource != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _speaking || _transport == null ? null : _speak,
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(
                widget.english
                    ? (document.kind == ComplexEditorKind.presentation
                          ? 'Read current slide'
                          : 'Read selection')
                    : (document.kind == ComplexEditorKind.presentation
                          ? '朗读当前页'
                          : '朗读选中内容'),
              ),
            ),
          ),
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * .52).clamp(320.0, 720.0),
          child: ComplexEditorBrowser(
            key: ValueKey((
              widget.scopeKey,
              content.reference,
              content.chapterIdentify,
              document.digest,
            )),
            document: document,
            title: content.title,
            english: widget.english,
            readOnly: true,
            publicServer: content.reference.server,
            publicComplexReadOnly: true,
            publicSelectionIdentity: widget.onSpeakSelection == null
                ? null
                : publicSpeechIdentity(content),
            retirementController: viewLease,
            onReloadRequested: () async {
              if (viewEpoch != _epoch || !widget.isCurrent()) return;
              await _reload();
            },
            onExternalLink: (uri) async {
              if (viewEpoch != _epoch || !widget.isCurrent()) return;
              await _external(uri);
            },
            onReady: (transport) async {
              final epoch = viewEpoch;
              if (epoch != _epoch || !widget.isCurrent()) {
                await viewLease.retire();
                return;
              }
              if (mounted) setState(() => _transport = transport);
              final snapshot = await transport.capture();
              try {
                if (!mounted ||
                    epoch != _epoch ||
                    !widget.isCurrent() ||
                    !snapshot.document.same(document)) {
                  throw StateError('Public source changed');
                }
              } finally {
                await transport.release(snapshot);
              }
            },
          ),
        ),
      ],
    );
  }
}

// Separate helper allows real dialog interaction tests without constructing a platform view.
Future<bool> confirmPublicComplexExternalLink(
  BuildContext context,
  Uri uri, {
  bool english = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(english ? 'Open external link?' : '打开外部链接？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              english
                  ? 'This opens another app. Continue?'
                  : '即将使用其他应用打开此链接，是否继续？',
            ),
            const SizedBox(height: 12),
            SelectableText(uri.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(english ? 'Cancel' : '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(english ? 'Open link' : '打开链接'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> openConfirmedPublicComplexExternal({
  required Future<bool> Function() confirm,
  required bool Function() isCurrent,
  required bool Function() isRetired,
  required Future<void> Function() retire,
  required Future<void> Function() launch,
}) async {
  if (!isCurrent() || isRetired()) return;
  if (!await confirm() || !isCurrent() || isRetired()) return;
  await retire();
  if (isCurrent()) await launch();
}
