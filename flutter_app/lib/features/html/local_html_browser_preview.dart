import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:url_launcher/url_launcher.dart';
import '../../core/local_html_preview_document.dart';
import '../../core/owned_preview_controller.dart';
import 'html_browser_session.dart';

/// Flutter owns navigation and confirmation. Native renders only local HTML.
class LocalHtmlBrowserPreview extends StatefulWidget {
  const LocalHtmlBrowserPreview({
    super.key,
    required this.document,
    this.english = false,
    this.rasterLoader,
    this.attachmentRasterLoader,
    this.beforeLocalResourceRetire,
    this.attachmentScopeKey = '',
    this.isAttachmentCurrent,
    this.rasterScopeKey = '',
    this.isRasterCurrent,
    this.retirementController,
    this.onExternalLink,
    this.onLocalAttachmentLink,
    this.onReloadRequested,
  });
  final LocalHtmlPreviewDocument document;
  final bool english;
  final Future<LocalHtmlRasterResponse?> Function(String url)? rasterLoader;
  final String rasterScopeKey;
  final Future<LocalHtmlRasterResponse?> Function(Uri uri)? attachmentRasterLoader;
  final String attachmentScopeKey;
  final Future<void> Function()? beforeLocalResourceRetire;
  final bool Function()? isAttachmentCurrent;
  final bool Function()? isRasterCurrent;
  final OwnedPreviewController? retirementController;
  final Future<void> Function(Uri)? onExternalLink;
  final Future<void> Function(Uri)? onLocalAttachmentLink;
  final Future<void> Function()? onReloadRequested;
  @override
  State<LocalHtmlBrowserPreview> createState() =>
      _LocalHtmlBrowserPreviewState();
}

class _LocalHtmlBrowserPreviewState extends State<LocalHtmlBrowserPreview>
    with WidgetsBindingObserver {
  HtmlBrowserSession? _session;
  Future<void>? _opening, _retiring;
  MethodChannel? _view;
  Future<void> Function()? _resourceDrain;
  bool _failed = false,
      _retired = false,
      _disposed = false,
      _confirming = false;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindController(widget.retirementController);
    unawaited(_startOpen());
  }

  void _bindController(OwnedPreviewController? controller) {
    controller?.bind(this, () => _closeOwned(controller));
  }

  Future<void> _startOpen() {
    if (widget.retirementController?.retired == true) {
      if (mounted && !_disposed) setState(() => _retired = true);
      return Future<void>.value();
    }
    return _opening = _open();
  }

  Future<void> _closeOwned(OwnedPreviewController? controller) async {
    _generation++;
    _retired = true;
    final opening = _opening, session = _session;
    if (mounted && !_disposed) setState(() {});
    if (session != null) {
      await session.close();
    } else {
      await _retire(controller);
    }
    await opening;
  }

  Future<void> _retire([OwnedPreviewController? controller]) async {
    final pending = _retiring;
    if (pending != null) return pending;
    final work = _retireNow();
    _retiring = work;
    controller?.ownerRetiring(this, _session?.closed ?? work);
    try {
      await work;
    } finally {
      if (identical(_retiring, work)) _retiring = null;
    }
  }

  Future<void> _retireNow() async {
    _retired = true;
    final drain = _resourceDrain;
    await drain?.call();
    try {
      await _view?.invokeMethod<void>('retire');
    } on MissingPluginException {
      // Native session close also destroys its owned registry.
    }
    if (mounted && !_disposed) setState(() {});
  }

  bool get _rasterCurrent {
    if (widget.retirementController?.retired == true) return false;
    if (widget.attachmentRasterLoader != null) {
      try {
        if (widget.attachmentScopeKey.isEmpty ||
            widget.isAttachmentCurrent?.call() != true || widget.rasterLoader != null) {
          return false;
        }
      } catch (_) { return false; }
    }
    if (widget.rasterLoader == null) {
      return true;
    }
    try {
      return widget.rasterScopeKey.isNotEmpty &&
          widget.isRasterCurrent?.call() == true &&
          !widget.document.scriptsEnabled &&
          widget.document.resources.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    if (!_rasterCurrent) {
      await _session?.close();
      if (mounted && !_disposed) {
        setState(() => _failed = true);
      }
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final old = _session;
      if (old != null) await old.close();
      if (!mounted ||
          _disposed ||
          generation != _generation ||
          !_rasterCurrent) {
        return;
      }
      _resourceDrain = widget.beforeLocalResourceRetire;
      final controller = widget.retirementController;
      final session = await HtmlBrowserSession.openLocal(
        retire: () => _retire(controller),
      );
      if (!mounted ||
          _disposed ||
          generation != _generation ||
          !_rasterCurrent) {
        await session.close();
        return;
      }
      _view?.setMethodCallHandler(null);
      _view = null;
      setState(() {
        _session = session;
        _retired = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted && !_disposed && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  void _created(int id) {
    if (_disposed || !mounted || _retired) return;
    if (!_rasterCurrent) {
      unawaited(_session?.close());
      return;
    }
    final channel = MethodChannel('bookstark/local_html_preview/$id');
    _view?.setMethodCallHandler(null);
    _view = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'localAttachmentRaster') {
        final loader = widget.attachmentRasterLoader;
        final session = _session;
        final scope = widget.attachmentScopeKey;
        final generation = _generation;
        if (loader == null || session == null || !mounted || _disposed ||
            _retired || !_rasterCurrent || call.arguments is! Map ||
            call.arguments['lease'] != session.lease ||
            call.arguments['url'] is! String) {
          return null;
        }
        final raw = call.arguments['url'] as String;
        final uri = Uri.tryParse(raw);
        if (raw.length > 2048 || uri == null ||
            uri.scheme != 'bookstark-attachment') {
          return null;
        }
        try {
          final result = await loader(uri);
          if (!mounted || _disposed || _retired || !_rasterCurrent ||
              _session != session || _generation != generation ||
              widget.attachmentRasterLoader != loader ||
              widget.attachmentScopeKey != scope) {
            return null;
          }
          return result?.toNative();
        } catch (_) { return null; }
      }
      if (call.method == 'raster') {
        final loader = widget.rasterLoader,
            session = _session,
            scope = widget.rasterScopeKey,
            generation = _generation;
        if (loader == null ||
            session == null ||
            !mounted ||
            _disposed ||
            _retired ||
            !_rasterCurrent ||
            call.arguments is! Map ||
            call.arguments['lease'] != session.lease ||
            call.arguments['url'] is! String) {
          return null;
        }
        final url = call.arguments['url'] as String;
        if (url.length > 8192 || !url.startsWith('/upload-files/')) {
          return null;
        }
        try {
          final result = await loader(url);
          if (!mounted ||
              _disposed ||
              _retired ||
              !_rasterCurrent ||
              _session != session ||
              _generation != generation ||
              widget.rasterLoader != loader ||
              widget.rasterScopeKey != scope) {
            return null;
          }
          return result?.toNative();
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'localAttachmentLink') {
        final open = widget.onLocalAttachmentLink;
        final session = _session;
        if (open == null || widget.attachmentRasterLoader == null ||
            session == null || _confirming || !mounted || _disposed ||
            _retired || !_rasterCurrent || call.arguments is! Map ||
            call.arguments['lease'] != session.lease ||
            call.arguments['url'] is! String) {
          return null;
        }
        final raw = call.arguments['url'] as String;
        final uri = Uri.tryParse(raw);
        if (raw.length > 2048 || uri == null ||
            uri.scheme != 'bookstark-attachment') {
          return null;
        }
        _confirming = true;
        try { await open(uri); }
        finally { _confirming = false; }
        return null;
      }
      if (call.method != 'externalLink' ||
          _disposed ||
          !mounted ||
          _retired ||
          call.arguments is! Map ||
          call.arguments['lease'] != _session?.lease ||
          _confirming) {
        return null;
      }
      final uri = Uri.tryParse(call.arguments['url'] as String? ?? '');
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.host.endsWith('.bookstark-local.invalid')) {
        return null;
      }
      if (widget.onExternalLink != null) {
        await widget.onExternalLink!(uri);
        return null;
      }
      _confirming = true;
      try {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('打开外部链接？', 'Open external link?')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(
                      '将在浏览器中打开此地址。',
                      'This address will open in your browser.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(uri.toString()),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('打开浏览器', 'Open browser')),
              ),
            ],
          ),
        );
        if (yes == true && mounted && !_disposed && !_retired) {
          // Retire before handoff: a browser can return before Flutter receives
          // a paused lifecycle event. Returning must never resume this runtime.
          _generation++;
          final session = _session;
          if (session != null) {
            await session.close();
          } else {
            await HtmlBrowserSession.closeActive();
          }
          if (!mounted || _disposed) return null;
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t('无法打开浏览器。', 'Unable to open browser.'))),
            );
          }
        }
      } finally {
        _confirming = false;
      }
      return null;
    });
  }

  @override
  void didUpdateWidget(covariant LocalHtmlBrowserPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.document.fingerprint != widget.document.fingerprint ||
        oldWidget.rasterScopeKey != widget.rasterScopeKey ||
        oldWidget.rasterLoader != widget.rasterLoader ||
        oldWidget.attachmentRasterLoader != widget.attachmentRasterLoader ||
        oldWidget.attachmentScopeKey != widget.attachmentScopeKey;
    final controllerChanged = !identical(
      oldWidget.retirementController,
      widget.retirementController,
    );
    if (controllerChanged) {
      oldWidget.retirementController?.unbind(this);
      _bindController(widget.retirementController);
    } else if (changed && widget.retirementController != null) {
      unawaited(widget.retirementController!.retire());
      return;
    }
    if (changed || controllerChanged) unawaited(_startOpen());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (widget.retirementController != null) {
        unawaited(
          widget.retirementController!.retire().catchError((Object _) {}),
        );
        return;
      }
      _generation++;
      _retired = true;
      if (mounted && !_disposed) setState(() {});
      final session = _session;
      if (session != null) {
        unawaited(session.close().catchError((Object _) {}));
      } else {
        // An opening lease may not have been assigned yet. Queue a close barrier
        // so it cannot start automatically after the app returns to foreground.
        unawaited(HtmlBrowserSession.closeActive().catchError((Object _) {}));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.retirementController?.unbind(this);
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
    _view?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _retired) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t('交互预览已关闭或暂不可用。', 'Interactive preview is closed or unavailable.'),
          ),
          if (widget.retirementController?.retired != true || widget.onReloadRequested != null)
            OutlinedButton.icon(
              onPressed: widget.onReloadRequested ?? _startOpen,
              icon: const Icon(Icons.refresh),
              label: Text(t('重新加载', 'Reload')),
            ),
        ],
      );
    }
    final session = _session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox(
      height: 560,
      child: PlatformViewLink(
        key: ValueKey(session.lease),
        viewType: 'bookstark/local_html_preview',
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        ),
        onCreatePlatformView: (params) {
          // Keep the WebView in the Android view hierarchy so its DOM
          // accessibility nodes remain available to TalkBack and automation.
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'bookstark/local_html_preview',
            layoutDirection: Directionality.of(context),
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: {
              ...widget.document.toNative(
                session.lease,
                english: widget.english,
              ),
              'dynamicRaster': widget.rasterLoader != null,
              if (widget.attachmentRasterLoader != null) 'localAttachmentRaster': true,
            },
            onFocus: () => params.onFocusChanged(true),
          );
          controller.addOnPlatformViewCreatedListener(
            params.onPlatformViewCreated,
          );
          controller.addOnPlatformViewCreatedListener((id) {
            if (_session?.lease == session.lease) _created(id);
          });
          unawaited(controller.create());
          return controller;
        },
      ),
    );
  }
}
