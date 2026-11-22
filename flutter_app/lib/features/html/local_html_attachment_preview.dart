import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/local_attachments.dart';
import '../../core/attachments.dart';
import '../../widgets/bookstark_markdown.dart' show shareBookstarkAttachment;
import '../../core/local_html_attachment_resources.dart';
import '../../core/local_html_preview_document.dart';
import '../../core/owned_preview_controller.dart';
import '../../core/local_html_preview_owner.dart';
import 'local_html_browser_preview.dart';

/// Local ordinary-space preview. Its owner can await both native close and the
/// actual attachment IO drain. This widget never uploads or saves the body.
class LocalHtmlAttachmentPreview extends StatefulWidget {
  const LocalHtmlAttachmentPreview({
    super.key,
    required this.attachments,
    required this.rawSource,
    required this.document,
    required this.scopeIdentity,
    required this.isCurrentScope,
    required this.previewOwner,
    this.english = false,
    this.onExternalLink,
  });
  final LocalAttachments attachments;
  final String rawSource, scopeIdentity;
  final LocalHtmlPreviewDocument document;
  final bool Function() isCurrentScope;
  final LocalHtmlPreviewOwner previewOwner;
  final bool english;
  final Future<void> Function(Uri)? onExternalLink;
  @override
  State<LocalHtmlAttachmentPreview> createState() => _LocalHtmlAttachmentPreviewState();
}

class _LocalHtmlAttachmentPreviewState extends State<LocalHtmlAttachmentPreview> {
  LocalHtmlAttachmentResources? _resources;
  OwnedPreviewController? _preview;
  Future<LocalHtmlRasterResponse?> Function(Uri)? _loader;
  int _epoch = 0;
  bool _failed = false, _disposed = false, _reloading = false, _openingFile = false;
  Future<void> _transition = Future<void>.value();
  LocalHtmlPreviewOwner? _bodyOwner;

  @override
  void initState() {
    super.initState();
    unawaited(_openBody());
  }
  Future<void> _openBody() async {
    final owner = widget.previewOwner;
    final epoch = _epoch;
    final scope = widget.scopeIdentity;
    final current = widget.isCurrentScope;
    try {
      if (_disposed || !owner.current || !current()) return;
      final body = await owner.nextPreview();
      if (!mounted || _disposed || epoch != _epoch ||
          !identical(owner, widget.previewOwner) || !owner.current ||
          !current() || body.retired) {
        await owner.release(body);
        return;
      }
      final resources = LocalHtmlAttachmentResources(
        attachments: widget.attachments, source: widget.rawSource,
        scopeIdentity: scope,
        isCurrentScope: () => !_disposed && epoch == _epoch &&
            owner.current && current(),
      );
      _bodyOwner = owner;
      _resources = resources;
      _preview = body;
      _failed = false;
      _loader = (uri) async {
        final raster = await resources.read(uri);
        return raster == null ? null : LocalHtmlRasterResponse(
          mime: raster.mime, bytes: raster.bytes);
      };
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && !_disposed && epoch == _epoch) {
        setState(() => _failed = true);
      }
    }
  }
  Future<void> _retire() {
    _epoch++;
    final body = _preview;
    final owner = _bodyOwner;
    final resources = _resources;
    _loader = null;
    final drain = resources?.retireAndDrain();
    if (mounted && !_disposed) setState(() {});
    return _transition = _transition.catchError((Object _) {}).then((_) async {
      if (body != null && owner != null) await owner.release(body);
      await drain;
    });
  }
  Future<void> _reload() async {
    if (_disposed || _reloading || _openingFile ||
        !widget.previewOwner.current || !widget.isCurrentScope()) {
      return;
    }
    setState(() => _reloading = true);
    try {
      await _retire();
      if (!mounted || _disposed || !widget.previewOwner.current ||
          !widget.isCurrentScope()) {
        return;
      }
      await _openBody();
    } catch (_) { _failed = true; }
    finally {
      if (mounted && !_disposed) setState(() => _reloading = false);
    }
  }

  Future<void> _openFile(Uri uri) async {
    final resources = _resources;
    final preview = _preview;
    final owner = widget.previewOwner;
    final current = widget.isCurrentScope;
    final epoch = _epoch;
    bool owned() => mounted && !_disposed && epoch == _epoch &&
        owner.current && current();
    if (_openingFile || _reloading || resources == null || preview == null ||
        !owned() || !resources.current) {
      return;
    }
    _openingFile = true;
    try {
      final file = await resources.readReferencedFile(uri);
      if (!mounted || !owned()) return;
      final confirmed = await showModalBottomSheet<bool>(
        context: context, isScrollControlled: true, useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20,
              20 + MediaQuery.viewInsetsOf(sheet).bottom),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(file.name, style: Theme.of(sheet).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(widget.english
                  ? 'Local file · ${file.bytes.length} bytes'
                  : '本地文件 · ${file.bytes.length} 字节'),
                const SizedBox(height: 12),
                Text(widget.english
                  ? 'The preview closes before opening the system share sheet. Reload explicitly when you return.'
                  : '打开系统分享面板前将关闭预览，返回后需明确重新载入。'),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(sheet, true),
                  child: Text(widget.english ? 'Open or share' : '打开或分享')),
                TextButton(onPressed: () => Navigator.pop(sheet, false),
                  child: Text(widget.english ? 'Cancel' : '取消')),
              ]),
          ),
        ),
      );
      if (!owned() || confirmed != true) return;
      final fresh = await resources.readReferencedFile(uri);
      if (!owned() || fresh.sha256Hex != file.sha256Hex) {
        throw StateError('Local file changed before handoff');
      }
      await owner.release(preview);
      // Reader retirement is intentional here. The captured root owner, exact
      // source epoch and immutable confirmed bytes still authorize this one
      // user-requested handoff; they never authorize another read after close.
      if (!mounted || !owned()) return;
      await shareBookstarkAttachment(
        context, widget.attachments,
        Attachment(uri: uri, name: file.name, image: false,
          size: file.bytes.length),
        bytes: file.bytes,
      );
    } catch (_) {
      if (mounted && owned()) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          widget.english ? 'Local file unavailable or changed. Select it again.'
            : '本地附件不可用或已变化，请重新选择。')));
      }
    } finally {
      _openingFile = false;
      if (owned()) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant LocalHtmlAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawSource == widget.rawSource &&
        oldWidget.document.fingerprint == widget.document.fingerprint &&
        oldWidget.scopeIdentity == widget.scopeIdentity &&
        identical(oldWidget.attachments, widget.attachments) &&
        identical(oldWidget.previewOwner, widget.previewOwner)) {
      return;
    }
    // A reused widget cannot revive a closed old body or publish new authority.
    // Only explicit Reload obtains another irreversible preview.
    unawaited(_retire().catchError((Object _) {}));
  }
  @override
  void dispose() {
    _disposed = true;
    unawaited(_retire().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resources = _resources;
    final preview = _preview;
    if (_failed || resources == null || preview == null || _loader == null ||
        !resources.current || !widget.previewOwner.current) {
      return Center(child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Text(widget.english ? 'Local preview closed. Reload to continue.'
            : '本地预览已关闭，请重新载入。'),
          if (widget.previewOwner.current && widget.isCurrentScope())
            OutlinedButton(onPressed: _reloading || _openingFile ? null : _reload,
              child: Text(widget.english ? 'Reload' : '重新载入')),
        ])));
    }
    return LocalHtmlBrowserPreview(
      key: ValueKey((widget.scopeIdentity, resources.sourceDigest, _epoch)),
      document: widget.document,
      english: widget.english,
      attachmentRasterLoader: _loader,
      beforeLocalResourceRetire: resources.retireAndDrain,
      attachmentScopeKey: widget.scopeIdentity,
      isAttachmentCurrent: () => resources.current,
      retirementController: preview,
      onExternalLink: widget.onExternalLink,
      onLocalAttachmentLink: _openFile,
      onReloadRequested: _reload,
    );
  }
}
