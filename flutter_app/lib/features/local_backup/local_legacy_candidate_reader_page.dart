import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/attachments.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/local_html_preview_document.dart';
import '../../core/local_legacy_candidate_review.dart';
import '../../core/local_legacy_format_selection.dart';
import '../../core/native_local_content_crypto.dart';
import '../../core/owned_preview_controller.dart';
import '../../widgets/bookstark_markdown.dart';
import '../../widgets/native_image.dart';
import '../admin/admin_asset_secure_window.dart';
import '../complex_editors/complex_editor_browser.dart';
import '../complex_editors/source_chunks.dart';
import '../html/local_html_browser_preview.dart';
import 'local_legacy_candidate_review_page.dart';

class LocalLegacyCandidateReaderPage extends StatefulWidget {
  const LocalLegacyCandidateReaderPage({
    super.key,
    required this.session,
    required this.metadata,
    required this.routeController,
    required this.onReturnToChecks,
    this.english = false,
    this.windowGuardFactory,
  });
  final LegacyCandidateReviewSession session;
  final GenerationContentMetadata metadata;
  final OwnedPreviewController routeController;
  final Future<void> Function() onReturnToChecks;
  final bool english;
  final AdminAssetWindowGuard Function()? windowGuardFactory;
  @override
  State<LocalLegacyCandidateReaderPage> createState() =>
      _LocalLegacyCandidateReaderPageState();
}

class _LocalLegacyCandidateReaderPageState
    extends State<LocalLegacyCandidateReaderPage>
    with WidgetsBindingObserver {
  late final LegacyCandidateReviewSession _session;
  late final GenerationContentMetadata _metadata;
  late final OwnedPreviewController _routeController;
  final _password = TextEditingController();
  final _retiringBodies = <OwnedPreviewController>{};
  AdminAssetWindowGuard? _window;
  GenerationContentHandle? _handle;
  LegacyReviewHtmlView? _html;
  LocalHtmlPreviewDocument? _htmlDocument;
  ComplexEditorDocument? _complex;
  SourceChunks? _chunks;
  String? _source;
  OwnedPreviewController? _bodyController;
  AttachmentCancellation? _request;
  Route<dynamic>? _dialog;
  Future<void>? _locking;
  var _epoch = 0;
  bool _passwordReleased = false, _promptOpen = false;
  bool _active = true,
      _busy = false,
      _secureReady = false,
      _failed = false,
      _leaving = false,
      _disposed = false,
      _wasBackground = false,
      _lockingNow = false;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _current =>
      mounted &&
      !_disposed &&
      !_leaving &&
      _active &&
      !_routeController.retired &&
      _session.isCurrent;
  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _metadata = widget.metadata;
    _routeController = widget.routeController;
    _routeController.bind(this, _closeAll);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (_metadata.isProtected) {
      unawaited(_enableSecure());
    } else {
      _secureReady = true;
      if (_active) unawaited(_open().catchError((Object _) {}));
    }
  }

  void _clearPassword() {
    if (!_passwordReleased) _password.clear();
  }

  void _refresh() {
    if (!mounted || _disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) setState(() {});
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      setState(() {});
    }
  }

  Future<void> _enableSecure() async {
    if (!_current || _window != null) return;
    final guard = widget.windowGuardFactory?.call() ?? AdminAssetSecureWindow();
    _window = guard;
    try {
      await guard.acquire();
      if (_current) setState(() => _secureReady = true);
    } catch (_) {
      if (_current) setState(() => _failed = true);
    }
  }

  Future<void> _dismissDialog() async {
    final route = _dialog;
    _dialog = null;
    if (route == null) return;
    void remove() {
      final nav = route.navigator;
      if (nav != null && nav.mounted && route.isActive) nav.removeRoute(route);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        remove();
        done.complete();
      });
      WidgetsBinding.instance.scheduleFrame();
      await done.future;
    } else {
      remove();
    }
  }

  void _runtimeRetired() {
    if (_bodyController?.retired == true && !_lockingNow && !_leaving) {
      unawaited(_lockBody().catchError((Object _) {}));
    }
  }

  Future<void> _lockBody() {
    final previous = _locking;
    if (previous != null) return previous;
    final work = _lockNow();
    _locking = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_locking, work)) _locking = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_locking, work)) _locking = null;
        },
      ),
    );
    return work;
  }

  Future<void> _lockNow() async {
    _lockingNow = true;
    _epoch++;
    _request?.cancel();
    _clearPassword();
    final body = _bodyController;
    if (body != null) {
      body.removeListener(_runtimeRetired);
      _retiringBodies.add(body);
    }
    _bodyController = null;
    _html?.dispose();
    _html = null;
    _htmlDocument = null;
    _complex = null;
    _source = null;
    _chunks = null;
    _busy = false;
    _refresh();
    try {
      // Start closing native views immediately, even if a background dialog waits for a frame.
      await Future.wait<void>([
        for (final controller in _retiringBodies) controller.retire(),
        _dismissDialog(),
      ]);
      _session.lockContent();
      _handle?.close();
      _handle = null;
      for (final controller in _retiringBodies) {
        controller.dispose();
      }
      _retiringBodies.clear();
    } catch (_) {
      if (mounted && !_disposed) setState(() => _failed = true);
      rethrow;
    } finally {
      _lockingNow = false;
    }
  }

  Future<void> _closeAll() async {
    _leaving = true;
    await _lockBody();
  }

  Future<void> _leave() async {
    try {
      await _routeController.retire();
      if (mounted && !_disposed) Navigator.of(context).pop();
    } catch (_) {
      if (mounted && !_disposed) setState(() => _failed = true);
    }
  }

  void _install(GenerationContentHandle handle) {
    if (handle.metadata.id != _metadata.id ||
        handle.metadata.collection != _metadata.collection ||
        handle.metadata.revision != _metadata.revision ||
        handle.metadata.format != _metadata.format ||
        handle.metadata.isProtected != _metadata.isProtected) {
      handle.close();
      throw const GenerationContentFailure(GenerationContentReason.conflict);
    }
    final source = handle.source;
    LegacyReviewHtmlView? html;
    try {
      if (_metadata.format == LegacyContentFormat.html ||
          _metadata.collection == 'article' &&
              _metadata.format == LegacyContentFormat.markdown) {
        html = _session.html(handle);
        _htmlDocument = html.document;
        _html = html;
      } else if (_metadata.format != LegacyContentFormat.markdown) {
        _complex = ComplexEditorDocument.parse(
          ComplexEditorKind.parse(_metadata.format.name),
          source,
        );
      } else {
        _source = source;
        if (SourceChunks.utf8ByteLength(source) > 500000) {
          _chunks = SourceChunks(source);
        }
      }
      if (_html != null || _complex != null) {
        _bodyController = OwnedPreviewController()
          ..addListener(_runtimeRetired);
      }
      _handle = handle;
      _failed = false;
    } catch (_) {
      html?.dispose();
      handle.close();
      _html = null;
      _htmlDocument = null;
      _complex = null;
      _source = null;
      _chunks = null;
      rethrow;
    }
  }

  Future<void> _open({String? password}) async {
    if (!_current || _busy || !_secureReady) return;
    final epoch = _epoch, request = AttachmentCancellation();
    _request = request;
    setState(() => _busy = true);
    try {
      final handle = await _session.open(
        _metadata.id,
        collection: _metadata.collection,
        password: password,
        cancellation: request,
      );
      if (!_current || epoch != _epoch) {
        handle.close();
        return;
      }
      _install(handle);
      setState(() => _busy = false);
    } catch (error) {
      if (_current && epoch == _epoch) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      rethrow;
    } finally {
      if (identical(_request, request)) _request = null;
    }
  }

  Future<void> _unlock() async {
    if (!_current || !_secureReady || _busy || _dialog != null || _promptOpen) {
      return;
    }
    _promptOpen = true;
    var submitting = false, obscure = true;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          _dialog = ModalRoute.of(context);
          return StatefulBuilder(
            builder: (context, update) => AlertDialog(
              scrollable: true,
              title: Text(t('解锁内容', 'Unlock content')),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _password,
                      enabled: !submitting,
                      obscureText: obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: t('原密码', 'Original password'),
                        errorText: error,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: t('显示或隐藏密码', 'Show or hide password'),
                          onPressed: submitting
                              ? null
                              : () => update(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('不会保存密码', 'Password is not saved'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xff536079),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          _clearPassword();
                          Navigator.of(context).pop();
                        },
                  child: Text(t('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (_password.text.isEmpty) {
                            update(
                              () => error = t(
                                '请输入原密码',
                                'Enter the original password',
                              ),
                            );
                            return;
                          }
                          String? secret = _password.text;
                          _clearPassword();
                          update(() {
                            submitting = true;
                            error = null;
                          });
                          final epoch = _epoch;
                          try {
                            await _open(password: secret);
                            secret = null;
                            if (_current &&
                                epoch == _epoch &&
                                _handle != null &&
                                context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } on LocalContentCryptoFailure catch (failure) {
                            secret = null;
                            if (_current &&
                                epoch == _epoch &&
                                context.mounted) {
                              setState(() => _failed = false);
                              update(() {
                                submitting = false;
                                error =
                                    failure.reason ==
                                        LocalContentCryptoReason.wrongPassword
                                    ? t(
                                        '密码不正确，请重试。',
                                        'Incorrect password. Try again.',
                                      )
                                    : t(
                                        '暂时无法解锁，请重试。',
                                        'Cannot unlock now. Try again.',
                                      );
                              });
                            }
                          } catch (_) {
                            secret = null;
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                  child: Text(
                    submitting ? t('正在解锁', 'Unlocking') : t('解锁', 'Unlock'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _dialog = null;
      _promptOpen = false;
      _clearPassword();
    }
  }

  Future<void> _external(Uri uri) async {
    if (!_current ||
        _dialog != null ||
        _promptOpen ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    _promptOpen = true;
    final epoch = _epoch;
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
        context: context,
        builder: (context) {
          _dialog = ModalRoute.of(context);
          return AlertDialog(
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
          );
        },
      );
    } finally {
      _dialog = null;
      _promptOpen = false;
    }
    if (accepted != true || !_current || epoch != _epoch) return;
    await _lockBody();
    if (mounted && !_disposed) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      if (mounted && !_disposed) {
        setState(() {});
        if (_metadata.isProtected && !_secureReady) unawaited(_enableSecure());
      }
    } else {
      _active = false;
      _wasBackground = true;
      unawaited(_lockBody().catchError((Object _) {}));
    }
  }

  @override
  void didUpdateWidget(covariant LocalLegacyCandidateReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, _session) ||
        !identical(widget.metadata, _metadata) ||
        !identical(widget.routeController, _routeController)) {
      unawaited(_routeController.retire().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _routeController.unbind(this);
    final guard = _window;
    _window = null;
    _clearPassword();
    unawaited(() async {
      var confirmed = false;
      for (var attempt = 0; attempt < 3 && !confirmed; attempt++) {
        try {
          await _routeController.retire();
          confirmed = true;
        } catch (_) {}
      }
      // Do not release a screenshot lease while an owned native close is uncertain.
      await WidgetsBinding.instance.endOfFrame;
      if (!_passwordReleased) {
        _passwordReleased = true;
        _password.dispose();
      }
      if (confirmed) {
        try {
          await guard?.close();
        } catch (_) {}
      }
    }());
    super.dispose();
  }

  Widget _locked() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CandidateReviewCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, color: reviewBlue, size: 64),
                const SizedBox(height: 24),
                Text(
                  _metadata.isProtected
                      ? t('内容已锁定', 'Content locked')
                      : t('预览已关闭', 'Preview closed'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _metadata.isProtected
                      ? (_wasBackground
                            ? t(
                                '切到后台后已自动锁定。',
                                'Locked after leaving the foreground.',
                              )
                            : t(
                                '使用原密码，临时查看这份副本。',
                                'Use the original password to view this copy temporarily.',
                              ))
                      : t('这份副本保持只读。', 'This copy remains read only.'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: !_current || _busy || !_secureReady || _lockingNow
                      ? null
                      : _metadata.isProtected
                      ? _unlock
                      : () => unawaited(_open().catchError((Object _) {})),
                  child: Text(
                    _metadata.isProtected
                        ? (_wasBackground
                              ? t('重新解锁', 'Unlock again')
                              : t('解锁查看', 'Unlock to view'))
                        : t('重新打开', 'Open again'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t('离开页面后自动锁定', 'Locks when leaving this page'),
            style: const TextStyle(fontSize: 14, color: Color(0xff536079)),
          ),
        ],
      ),
    ),
  );
  Widget _body() {
    final html = _html,
        document = _htmlDocument,
        complex = _complex,
        controller = _bodyController,
        chunks = _chunks;
    if (html != null && document != null && controller != null) {
      return LocalHtmlBrowserPreview(
        key: ValueKey(controller),
        document: document,
        english: widget.english,
        rasterLoader: html.load,
        rasterScopeKey: html.scopeKey,
        isRasterCurrent: () => html.isCurrent,
        retirementController: controller,
        onExternalLink: _external,
      );
    }
    if (complex != null && controller != null) {
      return ComplexEditorBrowser(
        key: ValueKey(controller),
        document: complex,
        title: _metadata.title,
        english: widget.english,
        readOnly: true,
        retirementController: controller,
        onExternalLink: _external,
      );
    }
    if (chunks != null) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: chunks.length,
        itemBuilder: (context, index) => SelectableText(
          chunks.at(index),
          style: const TextStyle(fontSize: 16, height: 1.6),
        ),
      );
    }
    final handle = _handle!;
    return BookstarkMarkdown(
      data: _source ?? '',
      english: widget.english,
      scrollable: true,
      imageBuilder: (uri, title, alt) => _ReviewRaster(
        key: ValueKey((uri.toString(), handle)),
        session: _session,
        handle: handle,
        uri: uri,
        label: alt ?? t('副本图片', 'Copy image'),
      ),
      onLink: (text, href) async {
        final uri = Uri.tryParse(href ?? '');
        if (uri != null) await _external(uri);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _handle?.isCurrent == true && _current;
    final collection = _metadata.collection == 'article'
        ? t('文章', 'Article')
        : t('笔记', 'Note');
    final format = _metadata.format == LegacyContentFormat.html
        ? 'HTML'
        : _metadata.format == LegacyContentFormat.markdown
        ? 'Markdown'
        : _metadata.format.name;
    Widget body;
    if (_failed || !_session.isCurrent) {
      body = CandidateReviewFailure(
        english: widget.english,
        onReturn: widget.onReturnToChecks,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$collection · $format',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xff536079),
                  ),
                ),
                if (_metadata.isProtected)
                  CandidateReviewBadge(
                    unlocked
                        ? t('已解锁 · 只读', 'Unlocked · Read only')
                        : t('已锁定', 'Locked'),
                    locked: !unlocked,
                  ),
                if (unlocked && _html != null)
                  Text(
                    t('静态预览', 'Static preview'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xff536079),
                    ),
                  ),
              ],
            ),
          ),
          if (unlocked && _metadata.isProtected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                t(
                  '离开或切到后台后自动锁定',
                  'Locks when leaving or moving to the background',
                ),
                style: const TextStyle(fontSize: 14, color: Color(0xff536079)),
              ),
            ),
          Expanded(
            child: _busy && _dialog == null
                ? const Center(child: CircularProgressIndicator())
                : unlocked
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(color: Colors.white, child: _body()),
                    ),
                  )
                : _locked(),
          ),
        ],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: CandidateReviewFrame(
        title: _metadata.title,
        onBack: _leaving ? null : _leave,
        actions: unlocked
            ? [
                IconButton(
                  tooltip: t('锁定内容', 'Lock content'),
                  onPressed: () =>
                      unawaited(_lockBody().catchError((Object _) {})),
                  icon: const Icon(Icons.lock_outline),
                ),
              ]
            : [CandidateReviewBadge(t('只读', 'Read only'))],
        body: body,
      ),
    );
  }
}

class _ReviewRaster extends StatefulWidget {
  const _ReviewRaster({
    super.key,
    required this.session,
    required this.handle,
    required this.uri,
    required this.label,
  });
  final LegacyCandidateReviewSession session;
  final GenerationContentHandle handle;
  final Uri uri;
  final String label;
  @override
  State<_ReviewRaster> createState() => _ReviewRasterState();
}

class _ReviewRasterState extends State<_ReviewRaster> {
  late final Future<LocalHtmlRasterResponse?> _bytes;
  @override
  void initState() {
    super.initState();
    _bytes = widget.session.raster(widget.handle, widget.uri.toString());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LocalHtmlRasterResponse?>(
    future: _bytes,
    builder: (context, snapshot) {
      final resource = snapshot.data;
      if (resource == null ||
          !widget.handle.isCurrent ||
          !widget.session.isCurrent) {
        return Text(widget.label);
      }
      return NativeImage(
        bytes: resource.bytes,
        label: widget.label,
        maxDecodeSide: 4096,
      );
    },
  );
}
