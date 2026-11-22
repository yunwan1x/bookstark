import '../speech/local_speech_provider_page.dart';
import '../../core/public_complex_source.dart';
import 'public_complex_source_body.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bookstark_flutter/features/public_shares/public_article_markdown_body.dart';
import 'package:bookstark_flutter/features/public_shares/public_article_reader_pane.dart';
import 'package:bookstark_flutter/features/public_shares/share_article_unlock_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'package:bookstark_flutter/features/public_shares/share_unlock_page.dart';
import 'package:bookstark_flutter/features/public_shares/public_html_body.dart';
import 'package:bookstark_flutter/features/public_shares/share_html_unlock_dialog.dart';

class ShareReaderPage extends StatefulWidget {
  const ShareReaderPage({
    super.key,
    required this.reference,
    required this.repository,
    required this.attachments,
    this.english = false,
    this.onSpeak,
    this.onSpeakSelection,
    this.dispatchSourceFactory,
    this.onComments,
    this.onBook,
    this.onEditLink,
    this.isCurrentScope,
    this.articleBodyBuilder = defaultPublicArticleMarkdownBody,
  });
  final PublicArticleMarkdownBuilder articleBodyBuilder;
  final AnonymousPublicComplexSource Function(bool Function())?
  dispatchSourceFactory;
  final PublicShareReference reference;
  final PublicSharesRepository repository;
  final AttachmentRepository attachments;
  final bool english;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final bool Function()? isCurrentScope;
  final Future<void> Function()? onEditLink;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  final Future<void> Function(PublicShareDetail)? onComments, onBook;
  @override
  State<ShareReaderPage> createState() => _ShareReaderPageState();
}

class _ShareReaderPageState extends State<ShareReaderPage> {
  PublicShareDetail? _detail;
  OwnedPreviewController? _articleLease;
  bool _articleMode = false, _knownArticle = false;
  Completer<void>? _abort;
  AnonymousPublicComplexSource? _dispatchSource;
  int _generation = 0;
  bool _complexReadable = false;
  bool _loading = true, _unlocking = false, _action = false;
  String? _error;
  bool get _scopeCurrent {
    try {
      return widget.isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShareReaderPage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference ||
        old.repository != widget.repository) {
      _load();
    }
  }

  @override
  void dispose() {
    _cancel();
    _articleLease?.dispose();
    _articleLease = null;
    _detail = null;
    super.dispose();
  }

  void _cancel() {
    _dispatchSource?.close();
    _dispatchSource = null;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
  }

  Future<void> _load() async {
    _cancel();
    final abort = _abort = Completer<void>();
    final generation = ++_generation;
    final previousLease = _articleLease;
    _articleLease = null;
    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
      _complexReadable = false;
    });
    try {
      try {
        await previousLease?.retire();
      } finally {
        previousLease?.dispose();
      }
      if (!mounted || generation != _generation || !_scopeCurrent) return;
      PublicShareDetail detail;
      if (widget.repository is RemotePublicSharesRepository) {
        bool current() =>
            mounted && generation == _generation && !abort.isCompleted;
        final source = _dispatchSource =
            widget.dispatchSourceFactory?.call(current) ??
            AnonymousPublicComplexSource(isCurrent: current);
        try {
          final identity = await source.inspect(widget.reference);
          if ({
            'spreadsheet',
            'drawing',
            'mindmap',
            'richdoc',
            'presentation',
          }.contains(identity.format)) {
            detail = identity;
          } else {
            detail = await widget.repository.load(
              widget.reference,
              abortTrigger: abort.future,
            );
          }
        } finally {
          source.close();
          if (identical(_dispatchSource, source)) _dispatchSource = null;
        }
      } else {
        // Preserve explicit repository overrides used by existing callers/tests.
        detail = await widget.repository.load(
          widget.reference,
          abortTrigger: abort.future,
        );
      }
      if (!mounted || generation != _generation || !_scopeCurrent) return;
      setState(() {
        _detail = detail;
        _articleMode = publicShareUsesMarkdownWebView(detail);
        _knownArticle = detail.blogType == 'article';
        _articleLease = _articleMode && !detail.locked
            ? OwnedPreviewController()
            : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation || !_scopeCurrent) return;
      setState(() {
        _loading = false;
        _error = t(
          '分享不存在、已撤销，或暂时无法连接。',
          'The share is unavailable, revoked, or the connection failed.',
        );
      });
    }
  }

  Future<void> _unlock() async {
    final current = _detail;
    if (current == null || !current.locked || _unlocking) return;
    final generation = _generation;
    setState(() => _unlocking = true);
    var returnToFeed = false;
    final result = publicShareUsesMarkdownWebView(current)
        ? await showDialog<PublicShareDetail>(
            context: context,
            builder: (_) => ShareArticleUnlockDialog(
              detail: current,
              repository: widget.repository,
              english: widget.english,
            ),
          )
        : current.html
        ? await showDialog<PublicShareDetail>(
            context: context,
            builder: (_) => ShareHtmlUnlockDialog(
              detail: current,
              repository: widget.repository,
              english: widget.english,
            ),
          )
        : await Navigator.push<PublicShareDetail>(
            context,
            MaterialPageRoute(
              builder: (unlockContext) => ShareUnlockPage(
                onReturnToFeed: () {
                  returnToFeed = true;
                  Navigator.pop(unlockContext);
                },
                detail: current,
                repository: widget.repository,
                english: widget.english,
              ),
            ),
          );
    if (!mounted || generation != _generation || !_scopeCurrent) return;
    if (returnToFeed) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _unlocking = false;
      if (result != null &&
          result.reference == widget.reference &&
          !result.locked) {
        _detail = result;
        if (publicShareUsesMarkdownWebView(result)) {
          _articleLease = OwnedPreviewController();
        }
      }
    });
  }

  Future<void> _run(Future<void> Function() callback) async {
    if (_action) return;
    setState(() => _action = true);
    try {
      await callback();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('操作未完成，请重试。', 'The action failed. Please retry.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: widget.reference.canonicalUri.toString()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('已复制公开链接', 'Public link copied'))),
      );
    }
  }

  Widget _articleReader(PublicShareDetail detail) => PublicArticleReaderPane(
    detail: detail,
    english: widget.english,
    busy: _action,
    unlocking: _unlocking,
    onUnlock: _unlock,
    onSpeak: detail.locked || detail.content.isEmpty || widget.onSpeak == null
        ? null
        : () => _run(
            () => widget.onSpeak!(
              detail.content,
              detail.title,
              detail.reference.canonicalUri.toString(),
            ),
          ),
    onComments: detail.locked || widget.onComments == null
        ? null
        : () => _run(() => widget.onComments!(detail)),
    body: detail.locked || _articleLease == null
        ? null
        : widget.articleBodyBuilder(
            context,
            key: ValueKey('public-markdown-$_generation'),
            detail: detail,
            retirementController: _articleLease!,
            english: widget.english,
            onReload: _load,
            onExternalLink: (uri) async {
              final opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!opened) throw StateError('External browser unavailable');
            },
          ),
  );

  Widget _complexReader(PublicShareDetail detail) {
    final generation = _generation;
    final body = PublicComplexSourceBody(
      onSpeakSelection: widget.onSpeakSelection,
      key: ValueKey(('public-complex', generation, detail.reference)),
      reference: detail.reference,
      expectedKind: ComplexEditorKind.parse(detail.format),
      scopeKey: generation,
      isCurrent: () =>
          mounted &&
          generation == _generation &&
          _scopeCurrent &&
          widget.reference == detail.reference,
      english: widget.english,
      onReload: _load,
      onReadabilityChanged: (content) {
        if (!mounted ||
            generation != _generation ||
            !_scopeCurrent ||
            widget.reference != detail.reference) {
          return;
        }
        if (content == null) {
          if (_complexReadable) setState(() => _complexReadable = false);
          return;
        }
        final actual = content.identity;
        if (actual == null ||
            actual.reference != detail.reference ||
            actual.shareId != detail.shareId ||
            actual.targetId != detail.targetId ||
            actual.kind != detail.kind ||
            actual.format != detail.format ||
            actual.protected != detail.protected) {
          unawaited(_load());
          return;
        }
        setState(() {
          _detail = actual.withVerifiedComplexReadability();
          _complexReadable = true;
        });
      },
      markdownBody: (_, _) =>
          throw StateError('Reload using the existing Markdown route'),
      onExternalLink: (uri) async {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) throw StateError('External browser unavailable');
      },
    );
    return Column(
      children: [
        Expanded(child: body),
        if (_complexReadable && !detail.locked && widget.onComments != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _action
                    ? null
                    : () => _run(() => widget.onComments!(_detail!)),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(t('查看评论', 'View comments')),
              ),
            ),
          ),
      ],
    );
  }

  Widget _htmlReader(PublicShareDetail detail) {
    final metadata = [
      if (detail.author.isNotEmpty) detail.author,
      if (detail.sharedAt != null)
        MaterialLocalizations.of(
          context,
        ).formatMediumDate(detail.sharedAt!.toLocal()),
    ].join(' · ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    detail.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Chip(
                    avatar: detail.protected
                        ? Icon(
                            detail.locked
                                ? Icons.lock_outline
                                : Icons.lock_open,
                            size: 18,
                          )
                        : null,
                    label: Text(
                      detail.protected
                          ? detail.locked
                                ? t('需要密码', 'Password required')
                                : t('已解锁', 'Unlocked')
                          : t('公开分享', 'Public share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (metadata.isNotEmpty) Text(metadata),
                  const Chip(label: Text('HTML')),
                ],
              ),
              const SizedBox(height: 16),
              if (detail.locked)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 48,
                        color: Color(0xff3d5bd9),
                      ),
                      const SizedBox(height: 16),
                      Text(t('输入密码后阅读', 'Enter the password to read')),
                      const SizedBox(height: 20),
                      if (detail.kind == PublicShareKind.blog)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _unlocking ? null : _unlock,
                            child: Text(t('解锁阅读', 'Unlock and read')),
                          ),
                        ),
                    ],
                  ),
                )
              else ...[
                PublicHtmlBody(
                  source: detail.content,
                  server: detail.reference.server,
                  english: widget.english,
                ),
                if (widget.onComments != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _action
                        ? null
                        : () => _run(() => widget.onComments!(detail)),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(t('查看评论', 'View comments')),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_scopeCurrent) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(t("空间已切换，请返回", "Space changed; please return")),
        ),
      );
    }
    final detail = _detail;
    return Scaffold(
      backgroundColor: _articleMode
          ? Colors.white
          : accountCanvas(context, const Color(0xfff1f5ff)),
      appBar: AppBar(
        backgroundColor: _articleMode ? const Color(0xff6530ad) : null,
        foregroundColor: _articleMode ? Colors.white : null,
        title: Text(
          _articleMode && _knownArticle
              ? t('文章阅读', 'Article reader')
              : t('分享阅读', 'Shared reading'),
          style: _articleMode ? const TextStyle(color: Colors.white) : null,
        ),
        actions: [
          if (_articleMode)
            IconButton(
              onPressed: _loading ? null : () => _run(_copy),
              tooltip: t('复制公开链接', 'Copy public link'),
              icon: const Icon(Icons.copy_outlined),
            ),
          if (!_articleMode)
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: t('刷新', 'Refresh'),
              icon: const Icon(Icons.refresh),
            ),
          if (!_articleMode || widget.onEditLink != null)
            PopupMenuButton<String>(
              tooltip: t('更多', 'More'),
              onSelected: (value) {
                if (value == 'reload') {
                  _load();
                } else if (value == 'edit' && widget.onEditLink != null) {
                  unawaited(_run(widget.onEditLink!));
                } else if (value == 'copy') {
                  unawaited(_run(_copy));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'reload',
                  child: Text(t('重新加载', 'Reload')),
                ),
                if (widget.onEditLink != null)
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(t('使用编辑链接', 'Use editing link')),
                  ),
                PopupMenuItem(
                  value: 'copy',
                  child: Text(t('复制公开链接', 'Copy public link')),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, size: 64),
                      const SizedBox(height: 24),
                      Text(
                        t('分享暂不可用', 'Share unavailable'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          '链接可能已撤回，或暂时无法连接。',
                          'The link may have been revoked, or the connection is temporarily unavailable.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _load,
                        child: Text(t('重试', 'Retry')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: Text(t('返回', 'Back')),
                      ),
                    ],
                  ),
                ),
              )
            : detail == null
            ? const SizedBox.shrink()
            : publicShareUsesMarkdownWebView(detail)
            ? _articleReader(detail)
            : {
                'spreadsheet',
                'drawing',
                'mindmap',
                'richdoc',
                'presentation',
              }.contains(detail.format)
            ? _complexReader(detail)
            : detail.html
            ? _htmlReader(detail)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xffe3edff),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  '${t('公开分享', 'Public share')} · ${detail.format.isEmpty ? detail.kind.name : detail.format}',
                                  style: const TextStyle(
                                    color: Color(0xff155af5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              detail.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (detail.author.isNotEmpty ||
                                detail.sharedAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (detail.author.isNotEmpty) detail.author,
                                  if (detail.sharedAt != null)
                                    MaterialLocalizations.of(
                                      context,
                                    ).formatMediumDate(
                                      detail.sharedAt!.toLocal(),
                                    ),
                                ].join(' · '),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                if (!detail.locked &&
                                    detail.markdown &&
                                    detail.content.isNotEmpty &&
                                    widget.onSpeak != null)
                                  OutlinedButton.icon(
                                    onPressed: _action
                                        ? null
                                        : () => _run(
                                            () => widget.onSpeak!(
                                              detail.content,
                                              detail.title,
                                              detail.reference.canonicalUri
                                                  .toString(),
                                            ),
                                          ),
                                    icon: const Icon(Icons.headphones_outlined),
                                    label: Text(t('听书', 'Listen')),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _action ? null : () => _run(_copy),
                                  icon: const Icon(Icons.link),
                                  label: Text(t('复制链接', 'Copy link')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 12),
                            if (detail.locked) ...[
                              const Icon(
                                Icons.lock_outline,
                                size: 48,
                                color: Color(0xff155af5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                t(
                                  '分享内容需要密码才能阅读。',
                                  'A password is required to read this share.',
                                ),
                              ),
                              const SizedBox(height: 16),
                              if ((detail.markdown || detail.html) &&
                                  detail.kind == PublicShareKind.blog)
                                FilledButton(
                                  onPressed: _unlocking ? null : _unlock,
                                  child: Text(t('解锁阅读', 'Unlock and read')),
                                )
                              else
                                Text(
                                  t(
                                    '此格式的解锁阅读尚未接入。',
                                    'Password reading for this format is not available yet.',
                                  ),
                                ),
                            ] else if (detail.kind == PublicShareKind.book) ...[
                              Text(detail.description),
                              if (widget.onBook != null)
                                FilledButton.icon(
                                  onPressed: _action
                                      ? null
                                      : () =>
                                            _run(() => widget.onBook!(detail)),
                                  icon: const Icon(Icons.menu_book),
                                  label: Text(
                                    t('查看共享目录', 'Open shared contents'),
                                  ),
                                )
                              else
                                Text(
                                  t(
                                    '共享书籍目录正在改造中。',
                                    'Shared book contents are being migrated.',
                                  ),
                                ),
                            ] else if (detail.markdown)
                              BookstarkMarkdown(
                                data: detail.content,
                                attachments: widget.attachments,
                                english: widget.english,
                              )
                            else
                              Text(
                                '${t('此格式的原生阅读正在接入', 'Native reading is being added for this format')}: ${detail.format}',
                              ),
                            if (!detail.locked &&
                                widget.onComments != null) ...[
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 12),
                              Text(
                                t('评论', 'Comments'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _action
                                      ? null
                                      : () => _run(
                                          () => widget.onComments!(detail),
                                        ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(t('查看评论', 'View comments')),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
