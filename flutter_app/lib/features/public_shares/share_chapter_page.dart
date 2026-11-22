import '../speech/local_speech_provider_page.dart';
import '../../core/public_complex_source.dart';
import 'package:url_launcher/url_launcher.dart';
import 'public_complex_source_body.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'package:bookstark_flutter/features/public_shares/share_book_page.dart';
import 'package:bookstark_flutter/features/public_shares/public_html_body.dart';

class ShareChapterPage extends StatefulWidget {
  const ShareChapterPage({
    super.key,
    required this.book,
    required this.identify,
    required this.repository,
    required this.attachments,
    this.english = false,
    this.onSpeak,
    this.onSpeakSelection,
  });
  final PublicShareDetail book;
  final String identify;
  final PublicSharesRepository repository;
  final AttachmentRepository attachments;
  final bool english;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  @override
  State<ShareChapterPage> createState() => _ShareChapterPageState();
}

class _ShareChapterPageState extends State<ShareChapterPage> {
  PublicShareDetail? _book;
  PublicShareChapter? _chapter;
  Completer<void>? _abort;
  AnonymousPublicComplexSource? _dispatchSource;
  late String _identify = widget.identify;
  final _scroll = ScrollController();
  int _generation = 0;
  bool _loading = true, _action = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load(widget.identify);
  }

  @override
  void didUpdateWidget(covariant ShareChapterPage old) {
    super.didUpdateWidget(old);
    if (old.book.reference != widget.book.reference ||
        old.identify != widget.identify ||
        old.repository != widget.repository) {
      _load(widget.identify);
    }
  }

  @override
  void dispose() {
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _dispatchSource?.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(String identify) async {
    _dispatchSource?.close();
    _dispatchSource = null;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    final abort = _abort = Completer<void>();
    final generation = ++_generation;
    setState(() {
      _identify = identify;
      _loading = true;
      _error = null;
      _chapter = null;
      _book = null;
    });
    try {
      PublicShareDetail book;
      if (widget.repository is RemotePublicSharesRepository) {
        final source = _dispatchSource = AnonymousPublicComplexSource(
          isCurrent: () =>
              mounted && generation == _generation && !abort.isCompleted,
        );
        try {
          book = await source.inspect(widget.book.reference);
        } finally {
          source.close();
          if (identical(_dispatchSource, source)) _dispatchSource = null;
        }
      } else {
        book = await widget.repository.load(
          widget.book.reference,
          abortTrigger: abort.future,
        );
      }
      if (book.kind != PublicShareKind.book ||
          book.targetId != widget.book.targetId ||
          book.locked) {
        throw StateError('Shared book changed');
      }
      PublicShareNode? find(List<PublicShareNode> nodes) {
        for (final node in nodes) {
          if (node.identify == identify) return node;
          final child = find(node.children);
          if (child != null) return child;
        }
        return null;
      }

      final node = find(book.nodes);
      if (node == null) throw StateError('Chapter unavailable');
      final isComplex = {
        'spreadsheet',
        'drawing',
        'mindmap',
        'richdoc',
        'presentation',
      }.contains(node.format);
      final chapter =
          widget.repository is RemotePublicSharesRepository && isComplex
          ? PublicShareChapter(
              node: node,
              title: node.name,
              content: '',
              format: node.format,
              rawAvailable: false,
            )
          : await widget.repository.chapter(
              book,
              identify,
              abortTrigger: abort.future,
            );
      // Complex chapter body is fetched only by the new typed source, with fresh membership.

      if (!mounted || generation != _generation) return;
      setState(() {
        _book = book;
        _chapter = chapter;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = t(
          '章节已删除、分享已撤销，或暂时无法连接。',
          'The chapter was removed, the share was revoked, or the connection failed.',
        );
      });
    }
  }

  Widget _complexChapter(PublicShareDetail book, PublicShareChapter chapter) {
    final generation = _generation;
    return PublicComplexSourceBody(
      onSpeakSelection: widget.onSpeakSelection,
      key: ValueKey((
        'public-complex-chapter',
        generation,
        chapter.node.identify,
      )),
      reference: book.reference,
      chapterIdentify: chapter.node.identify,
      expectedKind: ComplexEditorKind.parse(chapter.format),
      scopeKey: generation,
      isCurrent: () =>
          mounted &&
          generation == _generation &&
          _identify == chapter.node.identify,
      english: widget.english,
      onReload: () => _load(chapter.node.identify),
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
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_action) return;
    setState(() => _action = true);
    try {
      await operation();
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

  String _path(PublicShareDetail book, PublicShareNode node) {
    final all = flattenPublicChapters(book.nodes);
    final names = <String>[];
    var parent = node.parentId;
    while (parent != 0) {
      final value = all.where((n) => n.id == parent).single;
      names.insert(0, value.name);
      parent = value.parentId;
    }
    return names.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapter, book = _book;
    final nodes = book == null
        ? <PublicShareNode>[]
        : flattenPublicChapters(book.nodes);
    final index = nodes.indexWhere((node) => node.identify == _identify);
    return Scaffold(
      backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
      appBar: AppBar(
        title: Text(t('共享章节', 'Shared chapter')),
        actions: [
          IconButton(
            tooltip: t('返回目录', 'Back to contents'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.format_list_bulleted),
          ),
        ],
      ),
      bottomNavigationBar: chapter == null || book == null
          ? null
          : SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: index > 0
                            ? () => _load(nodes[index - 1].identify)
                            : null,
                        child: Text(t('上一章', 'Previous')),
                      ),
                      Text('${index + 1} / ${nodes.length}'),
                      FilledButton(
                        onPressed: index >= 0 && index + 1 < nodes.length
                            ? () => _load(nodes[index + 1].identify)
                            : null,
                        child: Text(t('下一章', 'Next')),
                      ),
                    ],
                  ),
                ),
              ),
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
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _load(_identify),
                        child: Text(t('重试', 'Retry')),
                      ),
                    ],
                  ),
                ),
              )
            : chapter == null || book == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                controller: _scroll,
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
                                  '${book.title} · ${t('公开只读', 'Public read-only')}',
                                  style: const TextStyle(
                                    color: Color(0xff155af5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              chapter.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (_path(book, chapter.node).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_path(book, chapter.node)),
                            ],
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                if (chapter.format == 'markdown' &&
                                    chapter.content.isNotEmpty &&
                                    widget.onSpeak != null)
                                  OutlinedButton.icon(
                                    onPressed: _action
                                        ? null
                                        : () => _run(
                                            () => widget.onSpeak!(
                                              chapter.content,
                                              chapter.title,
                                              book.reference.canonicalUri
                                                  .toString(),
                                            ),
                                          ),
                                    icon: const Icon(Icons.headphones_outlined),
                                    label: Text(t('听书', 'Listen')),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _action
                                      ? null
                                      : () => _run(() async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: book.reference.canonicalUri
                                                  .toString(),
                                            ),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  t(
                                                    '已复制此书公开链接',
                                                    'Public book link copied',
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        }),
                                  icon: const Icon(Icons.link),
                                  label: Text(t('复制链接', 'Copy link')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 12),
                            if (chapter.format == 'markdown')
                              BookstarkMarkdown(
                                data: chapter.content,
                                attachments: widget.attachments,
                                english: widget.english,
                              )
                            else if (chapter.format == 'html')
                              PublicHtmlBody(
                                server: book.reference.server,
                                source: chapter.content,
                                english: widget.english,
                              )
                            else if ({
                              'spreadsheet',
                              'drawing',
                              'mindmap',
                              'richdoc',
                              'presentation',
                            }.contains(chapter.format))
                              _complexChapter(book, chapter)
                            else
                              Text(
                                '${t('此格式的原生阅读正在接入', 'Native reading is being added for this format')}: ${chapter.format}',
                              ),
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
