import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../core/api_client.dart';
import 'html_browser_session.dart';
import 'html_preview_document.dart';

/// Browser body only; editing and navigation remain native Flutter widgets.
class HtmlBrowserPreview extends StatefulWidget {
  const HtmlBrowserPreview({
    super.key,
    required this.client,
    required this.source,
    this.english = false,
  });
  final BookstarkClient client;
  final String source;
  final bool english;
  @override
  State<HtmlBrowserPreview> createState() => _HtmlBrowserPreviewState();
}

class _HtmlBrowserPreviewState extends State<HtmlBrowserPreview> {
  WebViewController? _browser;
  HtmlBrowserSession? _session;
  bool _ready = false, _failed = false, _retired = false;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _retire() async {
    _retired = true;
    final browser = _browser;
    if (browser != null) {
      await browser.setJavaScriptMode(JavaScriptMode.disabled);
      await browser.loadHtmlString('<!doctype html><html></html>');
      await browser.clearCache();
      await browser.clearLocalStorage();
    }
    if (mounted) setState(() => _ready = false);
  }

  Future<void> _open() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _failed = true);
      return;
    }
    try {
      final browser = WebViewController();
      _browser = browser;
      await browser.setJavaScriptMode(JavaScriptMode.disabled);
      final session = await HtmlBrowserSession.open(
        widget.client,
        retire: _retire,
      );
      _session = session;
      if (!mounted || _retired) {
        await session.close();
        return;
      }
      await browser.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_retired) return NavigationDecision.prevent;
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            // Keep document navigation inside the authenticated server. Embedded
            // script/CSS/media still use normal browser subresource semantics.
            return {'http', 'https'}.contains(uri.scheme) &&
                    uri.origin == widget.client.baseUri.origin
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await browser.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _load();
      if (mounted && !_retired) setState(() => _ready = true);
    } catch (_) {
      final session = _session;
      if (session != null) {
        try {
          await session.close();
        } catch (_) {
          /* fail closed below */
        }
      }
      if (mounted) {
        setState(() {
          _failed = true;
          _ready = false;
        });
      }
    }
  }

  Future<void> _load() async {
    await _browser!.loadHtmlString(
      buildHtmlPreviewDocument(widget.source, server: widget.client.baseUri),
      baseUrl: '${widget.client.baseUri}/',
    );
  }

  @override
  void didUpdateWidget(covariant HtmlBrowserPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && !_retired && widget.source != oldWidget.source) {
      unawaited(
        _load().catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        }),
      );
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _retired) {
      return Center(
        child: Text(
          widget.english
              ? 'Full preview unavailable. Open source or lightweight preview.'
              : '完整预览暂不可用，可切换源码或轻量预览。',
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return SizedBox(
      height: 560,
      child: WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _browser!.platform,
          layoutDirection: Directionality.of(context),
          displayWithHybridComposition: true,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        ),
      ),
    );
  }
}
