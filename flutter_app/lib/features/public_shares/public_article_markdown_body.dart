import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/owned_preview_controller.dart';
import '../../core/public_html_resources.dart';
import '../../core/public_share_models.dart';
import '../complex_editors/complex_editor_browser.dart';

/// A missing legacy classification is a neutral read-only share, never a guessed
/// note/article ID. Explicit notes retain their existing native renderer.
bool publicShareUsesMarkdownWebView(PublicShareDetail detail) =>
    detail.kind == PublicShareKind.blog &&
    detail.markdown &&
    detail.blogType != 'note';

typedef PublicArticleMarkdownBuilder =
    Widget Function(
      BuildContext context, {
      required Key key,
      required PublicShareDetail detail,
      required OwnedPreviewController retirementController,
      required Future<void> Function() onReload,
      required Future<void> Function(Uri) onExternalLink,
      required bool english,
    });

Widget defaultPublicArticleMarkdownBody(
  BuildContext context, {
  required Key key,
  required PublicShareDetail detail,
  required OwnedPreviewController retirementController,
  required Future<void> Function() onReload,
  required Future<void> Function(Uri) onExternalLink,
  required bool english,
}) => PublicArticleMarkdownBody(
  key: key,
  detail: detail,
  retirementController: retirementController,
  onReload: onReload,
  onExternalLink: onExternalLink,
  english: english,
);

class PublicArticleMarkdownBody extends StatefulWidget {
  const PublicArticleMarkdownBody({
    super.key,
    required this.detail,
    required this.onReload,
    required this.onExternalLink,
    this.english = false,
    this.resourceFactory,
    this.retirementController,
  });
  final PublicShareDetail detail;
  final OwnedPreviewController? retirementController;
  final Future<void> Function() onReload;
  final Future<void> Function(Uri) onExternalLink;
  final PublicHtmlResources Function(Uri)? resourceFactory;
  final bool english;
  @override
  State<PublicArticleMarkdownBody> createState() =>
      _PublicArticleMarkdownBodyState();
}

class _PublicArticleMarkdownBodyState extends State<PublicArticleMarkdownBody> {
  late final _lease = widget.retirementController ?? OwnedPreviewController();
  late final ComplexEditorDocument _document;
  int _failed = 0;
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    if (!publicShareUsesMarkdownWebView(widget.detail) ||
        widget.detail.locked) {
      throw ArgumentError('Accessible typed Markdown share required');
    }
    _document = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      widget.detail.content,
    );
  }

  @override
  void didUpdateWidget(covariant PublicArticleMarkdownBody old) {
    super.didUpdateWidget(old);
    if (old.detail.reference != widget.detail.reference ||
        old.detail.content != widget.detail.content ||
        old.detail.locked != widget.detail.locked) {
      // The caller must retire and replace this owned generation before reload.
      unawaited(_lease.retire());
    }
  }

  Future<void> _reload() async {
    await _lease.retire();
    if (mounted) await widget.onReload();
  }

  Future<void> _external(Uri uri) async {
    if (_confirming || _lease.retired) return;
    _confirming = true;
    final reference = widget.detail.reference;
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(widget.english ? 'Open external link?' : '打开外部链接？'),
          content: Text(uri.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.english ? 'Cancel' : '取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.english ? 'Open' : '打开'),
            ),
          ],
        ),
      );
      if (yes != true ||
          !mounted ||
          reference != widget.detail.reference ||
          _lease.retired) {
        return;
      }
      await _lease.retire();
      if (mounted && reference == widget.detail.reference) {
        await widget.onExternalLink(uri);
      }
    } finally {
      _confirming = false;
    }
  }

  @override
  void dispose() {
    if (widget.retirementController == null) {
      _lease.dispose();
    } else {
      unawaited(_lease.retire());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        key: const ValueKey('public-article-browser-boundary'),
        height: (MediaQuery.sizeOf(context).height * .52).clamp(320.0, 720.0),
        child: ComplexEditorBrowser(
          key: const ValueKey('public-article-owned-view'),
          document: _document,
          title: widget.detail.title,
          publicServer: widget.detail.reference.server,
          publicResourceFactory: widget.resourceFactory,
          readOnly: true,
          english: widget.english,
          retirementController: _lease,
          onReloadRequested: _reload,
          onExternalLink: _external,
          onPublicResourceStatus: (_, failed) {
            if (mounted && failed != _failed) setState(() => _failed = failed);
          },
          onReady: (transport) async {
            final snapshot = await transport.capture();
            try {
              if (!snapshot.document.same(_document)) {
                throw StateError('Public Markdown source mismatch');
              }
            } finally {
              await transport.release(snapshot);
            }
          },
        ),
      ),
      if (_failed > 0)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xfffff1d5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(widget.english ? 'Some images could not load' : '部分图片未加载'),
                TextButton(
                  onPressed: _reload,
                  child: Text(widget.english ? 'Reload' : '重新加载'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
