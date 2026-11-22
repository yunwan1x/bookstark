import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/article_web_scope.dart';
import '../../core/article_web_export.dart';
import '../../core/file_export.dart';
import '../admin/admin_asset_secure_window.dart';
import 'article_web_session.dart';

/// Allows the app shell to ask the actual Go editor before changing modules.
final class ArticleWebPageController {
  Object? _owner;
  Future<bool> Function()? _leave;
  Future<bool> prepareLeave() async => await _leave?.call() ?? true;
  void _bind(Object owner, Future<bool> Function() leave) {
    _owner = owner;
    _leave = leave;
  }

  void _unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _leave = null;
  }
}

class ArticleWebPage extends StatefulWidget {
  const ArticleWebPage({
    super.key,
    required this.client,
    required this.memberId,
    required this.isCurrentScope,
    required this.onNavigate,
    required this.onConnection,
    this.controller,
    this.articleId,
    this.onBack,
    this.english = false,
  });
  final BookstarkClient client;
  final int memberId;
  final bool Function() isCurrentScope;
  final Future<void> Function(String) onNavigate;
  final Future<void> Function() onConnection;
  final ArticleWebPageController? controller;
  final int? articleId;
  final Future<void> Function()? onBack;
  final bool english;
  @override
  State<ArticleWebPage> createState() => _ArticleWebPageState();
}

class _ArticleWebPageState extends State<ArticleWebPage>
    with WidgetsBindingObserver {
  final _guard = AdminAssetSecureWindow();
  ArticleWebSession? _session;
  MethodChannel? _events;
  Future<void>? _opening;
  Completer<void>? _metadataAbort;
  bool _disposed = false,
      _failed = false,
      _loading = true,
      _retired = false,
      _busy = false,
      _exporting = false;
  bool _backgrounded = false;
  int _epoch = 0;
  String _reason = '';
  Uri? _currentUrl;
  bool get _current {
    if (_disposed || !mounted) return false;
    try {
      return widget.isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgrounded =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused;
    widget.controller?._bind(this, _prepareLeave);
    _opening = _open();
    unawaited(_opening);
  }

  Future<void> _retireUI() async {
    _retired = true;
    if (!_disposed && mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _open() async {
    final epoch = ++_epoch;
    final client = widget.client, revision = widget.client.sessionRevision;
    final token = client.exportSession()['token'];
    bool openingCurrent() =>
        _current &&
        epoch == _epoch &&
        identical(widget.client, client) &&
        client.sessionRevision == revision &&
        client.exportSession()['token'] == token;
    _cancelMetadata();
    final abort = Completer<void>();
    _metadataAbort = abort;
    try {
      await _session?.close();
      if (!openingCurrent()) return;
      setState(() {
        _session = null;
        _failed = false;
        _retired = false;
        _loading = true;
      });
      await _guard.acquire();
      if (!openingCurrent()) return;
      final scope = ArticleWebScope(widget.client.baseUri, widget.memberId);
      var entry = scope.listUri;
      final id = widget.articleId;
      if (id != null) {
        final metadata = await widget.client.articleMetadata(
          id,
          abortTrigger: abort.future,
        );
        if (!openingCurrent()) return;
        entry = scope.editorEntry(metadata, id: id);
      }
      if (widget.client.exportSession()['token'] != token) {
        throw StateError('Article identity session changed');
      }
      final session = await ArticleWebSession.open(
        client: client,
        scope: scope,
        entry: entry,
        isCurrentScope: () => openingCurrent(),
        retire: _retireUI,
      );
      if (!openingCurrent()) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _failed = false;
        _retired = false;
        _loading = true;
        _currentUrl = session.entryUri;
      });
    } catch (error) {
      if (openingCurrent()) {
        setState(() {
          _failed = true;
          _loading = false;
          _reason =
              error is PlatformException &&
                  error.code == 'article_profile_unsupported'
              ? 'unsupported'
              : 'connection';
        });
      }
    }
  }

  Future<bool> _prepareLeave() async {
    final session = _session;
    if (session == null || !session.isCurrent || _retired) return true;
    if (_exporting) return false;
    try {
      return await session.command<bool>('prepareLeave') == true;
    } catch (_) {
      return _failed;
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _prepareLeave() || !_current) return;
      final session = _session;
      if (session != null &&
          session.isCurrent &&
          !_retired &&
          await session.command<bool>('back') == true) {
        return;
      }
      _cancelMetadata();
      _epoch++;
      await session?.close();
      if (_current) {
        if (widget.onBack != null) {
          await widget.onBack!();
        } else {
          await widget.onNavigate('home');
        }
      }
    } catch (_) {
      _notice(t('暂时无法返回。', 'Unable to go back.'));
    } finally {
      _busy = false;
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _prepareLeave() || !_current) return;
      final session = _session;
      if (session == null ||
          !session.isCurrent ||
          _retired ||
          (_failed && {'renderer', 'webview'}.contains(_reason))) {
        _opening = _open();
        await _opening;
      } else {
        setState(() {
          _failed = false;
          _loading = true;
        });
        await session.command<void>('reload');
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _notice(String message) {
    if (_current) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _download(
    ArticleWebSession session,
    Map<Object?, Object?> receipt,
  ) async {
    final id = receipt['id'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    if (_exporting) {
      await session.releaseDownload(id);
      return;
    }
    _exporting = true;
    try {
      final verified = await ArticleWebExport.verify(
        privateCache: await getTemporaryDirectory(),
        lease: session.lease,
        receipt: Map<Object?, Object?>.of(receipt)..remove('lease'),
        isCurrent: () =>
            _current && identical(_session, session) && session.isCurrent,
      );
      if (!_current || !session.isCurrent) return;
      final outcome = await const SystemFileExporter().saveFile(
        file: verified.file,
        name: verified.name,
        mime: verified.mime,
        size: verified.bytes,
        hash: verified.sha256Hex,
      );
      if (outcome == FileExportOutcome.saved) {
        _notice(t('文件已保存。', 'File saved.'));
      }
    } catch (_) {
      _notice(t('文件导出未完成，请重试。', 'File export did not complete. Please retry.'));
    } finally {
      try {
        await session.releaseDownload(id);
      } catch (_) {
        _notice(t('导出临时文件清理未完成。', 'Export cleanup did not complete.'));
      }
      _exporting = false;
    }
  }

  Future<void> _navigation(String value) async {
    if (_busy || !_current) return;
    final session = _session;
    if (session == null || !session.isCurrent) return;
    final navigation = session.scope.navigation(value, current: _currentUrl);
    if (navigation.destination == ArticleWebDestination.blocked) {
      _notice(t('无法打开此链接。', 'This link cannot be opened.'));
      return;
    }
    _busy = true;
    try {
      switch (navigation.destination) {
        case ArticleWebDestination.sessionEnded:
          if (await _prepareLeave() && _current) {
            await session.close();
            if (_current) await widget.onConnection();
          }
        case ArticleWebDestination.appRoute:
          if (await _prepareLeave() && _current) {
            await session.close();
            if (_current) await widget.onNavigate(navigation.appRoute!);
          }
        case ArticleWebDestination.external:
          final uri = navigation.uri!;
          final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t('打开外部链接？', 'Open external link?')),
              content: SingleChildScrollView(
                child: SelectableText(uri.toString()),
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
          if (accepted == true && _current && await _prepareLeave()) {
            await session.close();
            if (_current) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        case ArticleWebDestination.list:
        case ArticleWebDestination.editor:
        case ArticleWebDestination.blocked:
          break;
      }
    } catch (_) {
      _notice(t('无法打开此链接。', 'Unable to open this link.'));
    } finally {
      _busy = false;
    }
  }

  void _listen(int id, ArticleWebSession session) {
    _events?.setMethodCallHandler(null);
    final channel = MethodChannel('bookstark/article_web_view/$id');
    _events = channel;
    channel.setMethodCallHandler((call) async {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!_current ||
          !identical(_session, session) ||
          !session.isCurrent ||
          call.arguments is! Map ||
          call.arguments['lease'] != session.lease) {
        return;
      }
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      switch (call.method) {
        case 'loading':
          setState(() {
            _loading = true;
          });
        case 'ready':
          setState(() {
            _loading = false;
          });
        case 'history':
          final uri = Uri.tryParse(args['url'] as String? ?? '');
          if (uri != null && session.scope.sameServer(uri)) _currentUrl = uri;
        case 'error':
          setState(() {
            _failed = true;
            _loading = false;
            _reason = args['reason'] as String? ?? '';
          });
        case 'operationError':
          _notice(t('操作未完成，请重试。', 'Operation did not complete. Please retry.'));
        case 'navigation':
          await _navigation(args['url'] as String? ?? '');
        case 'downloadReady':
          await _download(session, args);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
    }
    if (state == AppLifecycleState.resumed) _backgrounded = false;
    final session = _session;
    if (session == null || !session.isCurrent || _retired) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(session.command<void>('pause').catchError((Object _) {}));
    } else if (state == AppLifecycleState.resumed && _current) {
      unawaited(session.command<void>('resume').catchError((Object _) {}));
    }
  }

  @override
  void didUpdateWidget(covariant ArticleWebPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind(this);
      widget.controller?._bind(this, _prepareLeave);
    }
    if (oldWidget.client != widget.client ||
        oldWidget.memberId != widget.memberId ||
        oldWidget.articleId != widget.articleId) {
      _opening = _open();
      unawaited(_opening);
    }
  }

  void _cancelMetadata() {
    final abort = _metadataAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _metadataAbort = null;
  }

  Future<void> _close() async {
    await _session?.close();
    await _opening;
    await _session?.close();
    // Keep FLAG_SECURE if native destruction/cookie cleanup failed.
    await _guard.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cancelMetadata();
    widget.controller?._unbind(this);
    WidgetsBinding.instance.removeObserver(this);
    _events?.setMethodCallHandler(null);
    unawaited(_close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Column(
        children: [
          if (widget.articleId != null)
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _back,
                        tooltip: t('返回', 'Back'),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Color(0xff6530ad),
                        ),
                      ),
                      Text(
                        t('返回', 'Return'),
                        style: const TextStyle(
                          color: Color(0xff6530ad),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      t('文章', 'Article'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xffe4dcec)),
                ],
              ),
            ),
          if (widget.articleId == null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    tooltip: t('返回', 'Back'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      t('文章', 'Articles'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: t('刷新', 'Refresh'),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          if (_loading && !_failed && !_retired)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (session != null && !_retired)
                  PlatformViewLink(
                    key: ValueKey(session.lease),
                    viewType: 'bookstark/article_web_view',
                    surfaceFactory: (context, controller) => AndroidViewSurface(
                      controller: controller as AndroidViewController,
                      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                      gestureRecognizers:
                          <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                    ),
                    onCreatePlatformView: (params) {
                      // Install events before create: native construction can fail synchronously.
                      _listen(params.id, session);
                      final controller =
                          PlatformViewsService.initExpensiveAndroidView(
                            id: params.id,
                            viewType: 'bookstark/article_web_view',
                            layoutDirection: Directionality.of(context),
                            creationParamsCodec: const StandardMessageCodec(),
                            creationParams: {
                              'lease': session.lease,
                              'paused': _backgrounded,
                            },
                            onFocus: () => params.onFocusChanged(true),
                          );
                      controller.addOnPlatformViewCreatedListener(
                        params.onPlatformViewCreated,
                      );
                      unawaited(controller.create());
                      return controller;
                    },
                  ),
                if (session == null && !_failed && !_retired)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (widget.articleId != null) ...[
                          const SizedBox(height: 16),
                          Text(t('正在打开文章…', 'Opening article…')),
                        ],
                      ],
                    ),
                  ),
                if (_failed || _retired)
                  ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.articleId != null)
                              const CircleAvatar(
                                radius: 36,
                                backgroundColor: Color(0xffeee2ff),
                                child: Icon(
                                  Icons.priority_high,
                                  size: 40,
                                  color: Color(0xff6530ad),
                                ),
                              )
                            else
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 40,
                                color: Color(0xff64748b),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _reason == 'unsupported'
                                  ? t(
                                      '请更新 Android System WebView',
                                      'Please update Android System WebView',
                                    )
                                  : _retired
                                  ? t('文章页面已关闭', 'Article page closed')
                                  : t(
                                      widget.articleId != null
                                          ? '文章暂时无法打开'
                                          : '暂时无法连接文章服务',
                                      widget.articleId != null
                                          ? 'Unable to open article'
                                          : 'Unable to connect to articles',
                                    ),
                            ),
                            if (widget.articleId != null) ...[
                              const SizedBox(height: 12),
                              Text(t('请重试或返回。', 'Please retry or return.')),
                            ],
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                widget.articleId != null
                                    ? t('重试', 'Retry')
                                    : t('重新加载', 'Reload'),
                              ),
                            ),
                            TextButton(
                              onPressed: widget.articleId != null
                                  ? _back
                                  : () async {
                                      if (await _prepareLeave() && _current) {
                                        await _session?.close();
                                        if (_current) {
                                          await widget.onConnection();
                                        }
                                      }
                                    },
                              child: Text(
                                widget.articleId != null
                                    ? t('返回', 'Return')
                                    : t('连接设置', 'Connection settings'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
