import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:url_launcher/url_launcher.dart';
import '../../core/public_html_resources.dart';
import 'public_html_preview_document.dart';
import '../html/html_browser_session.dart';

/// Flutter owns navigation and confirmation. Native renders only local HTML.
class PublicHtmlBrowserPreview extends StatefulWidget {
  const PublicHtmlBrowserPreview({
    super.key,
    required this.source,
    required this.server,
    this.resourceFactory,
    this.english = false,
  });
  final String source;
  final Uri server;
  final PublicHtmlResources Function(Uri)? resourceFactory;
  final bool english;
  @override
  State<PublicHtmlBrowserPreview> createState() =>
      _PublicHtmlBrowserPreviewState();
}

class _PublicHtmlBrowserPreviewState extends State<PublicHtmlBrowserPreview>
    with WidgetsBindingObserver {
  HtmlBrowserSession? _session;
  MethodChannel? _view;
  PublicHtmlResources? _resources;
  String? _document;
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
    unawaited(_open());
  }

  Future<void> _retire() async {
    _retired = true;
    _resources?.close();
    try {
      await _view?.invokeMethod<void>('retire');
    } on MissingPluginException {
      // The view may already be disposed. The session channel also retires the
      // native registry before enabling another document's cookie access.
    }
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _open() async {
    final generation = ++_generation;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    PublicHtmlResources? openedScope;
    HtmlBrowserSession? acquired;
    try {
      final old = _session;
      if (old != null) await old.close();
      if (identical(_session, old)) _session = null;
      if (!mounted || _disposed || generation != _generation) return;
      final document = publicHtmlPreviewDocument(widget.source, widget.server);
      _resources?.close();
      final scope =
          widget.resourceFactory?.call(widget.server) ??
          PublicHtmlResources(widget.server);
      openedScope = scope;
      _resources = scope;
      scope.onChanged = () {
        if (mounted && !_disposed && identical(_resources, scope)) {
          setState(() {});
        }
      };
      acquired = await HtmlBrowserSession.openPublic(retire: _retire);
      if (!mounted || _disposed || generation != _generation) {
        scope.close();
        await acquired.close();
        return;
      }
      _document = document;
      _view?.setMethodCallHandler(null);
      _view = null;
      setState(() {
        _session = acquired;
        _retired = false;
        _failed = false;
      });
    } catch (_) {
      openedScope?.close();
      try {
        await acquired?.close();
      } catch (_) {
        /* Retire the native registry through its session barrier. */
      }
      if (mounted && !_disposed && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  void _created(int id) {
    if (_disposed || !mounted || _retired) return;
    final channel = MethodChannel('bookstark/public_html_preview/$id');
    _view?.setMethodCallHandler(null);
    _view = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'resource') {
        final args = call.arguments;
        if (_disposed ||
            !mounted ||
            _retired ||
            args is! Map ||
            args['lease'] != _session?.lease ||
            args['url'] is! String) {
          return null;
        }
        final uri = Uri.tryParse(args['url'] as String), scope = _resources;
        if (uri == null || scope == null) return null;
        try {
          final resource = await scope.read(uri);
          if (_disposed ||
              !mounted ||
              _retired ||
              !identical(scope, _resources) ||
              args['lease'] != _session?.lease) {
            return null;
          }
          return {'bytes': resource.bytes, 'mime': resource.mime};
        } catch (_) {
          return null;
        }
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
    });
  }

  @override
  void didUpdateWidget(covariant PublicHtmlBrowserPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.server != widget.server ||
        oldWidget.resourceFactory != widget.resourceFactory) {
      unawaited(_open());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
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
    _resources?.close();
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
          OutlinedButton.icon(
            onPressed: _open,
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
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.hasBoundedHeight ? constraints.maxHeight : 600,
        child: Column(
          children: [
            Expanded(
              child: PlatformViewLink(
                key: ValueKey(session.lease),
                viewType: 'bookstark/public_html_preview',
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
                  final controller =
                      PlatformViewsService.initExpensiveAndroidView(
                        id: params.id,
                        viewType: 'bookstark/public_html_preview',
                        layoutDirection: Directionality.of(context),
                        creationParamsCodec: const StandardMessageCodec(),
                        creationParams: {
                          'lease': session.lease,
                          'source': _document!,
                          'server': widget.server.toString(),
                          'english': widget.english,
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
            ),
            if (_resources != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t(
                    '资源 ${_resources!.loaded} · 未能加载 ${_resources!.failed}',
                    'Resources ${_resources!.loaded} · Unavailable ${_resources!.failed}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
