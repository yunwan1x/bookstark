import '../../core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';
import '../../core/public_shares_repository.dart';

List<PublicShareNode> flattenPublicChapters(List<PublicShareNode> nodes) => [
  for (final node in nodes) ...[node, ...flattenPublicChapters(node.children)],
];

class ShareBookPage extends StatefulWidget {
  const ShareBookPage({
    super.key,
    required this.reference,
    required this.repository,
    required this.onOpen,
    this.english = false,
  });
  final PublicShareReference reference;
  final PublicSharesRepository repository;
  final Future<void> Function(PublicShareDetail, PublicShareNode) onOpen;
  final bool english;
  @override
  State<ShareBookPage> createState() => _ShareBookPageState();
}

class _ShareBookPageState extends State<ShareBookPage> {
  PublicShareDetail? _book;
  Completer<void>? _abort;
  final _expanded = <int>{};
  int _generation = 0;
  bool _loading = true, _opening = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShareBookPage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference ||
        old.repository != widget.repository) {
      _load();
    }
  }

  @override
  void dispose() {
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    super.dispose();
  }

  Future<void> _load() async {
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    final abort = _abort = Completer<void>(), generation = ++_generation;
    setState(() {
      _loading = true;
      _book = null;
      _error = null;
      _expanded.clear();
    });
    try {
      final book = await widget.repository.load(
        widget.reference,
        abortTrigger: abort.future,
      );
      if (book.kind != PublicShareKind.book || book.locked) {
        throw StateError('Share is not an accessible book');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _book = book;
        _loading = false;
        if (book.nodes.isNotEmpty) _expanded.add(book.nodes.first.id);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = t(
          '无法读取共享目录，请检查分享是否仍然可用。',
          'Unable to load contents. Check that this share is still available.',
        );
      });
    }
  }

  Future<void> _open(PublicShareNode node) async {
    if (_opening || _book == null) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen(_book!, node);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开此章节，请重试。', 'Unable to open this chapter. Please retry.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  List<Widget> _rows(List<PublicShareNode> nodes, int depth) => [
    for (final node in nodes) ...[
      Padding(
        padding: EdgeInsets.only(left: (depth * 16.0).clamp(0, 64)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (node.children.isNotEmpty)
              IconButton(
                tooltip: _expanded.contains(node.id)
                    ? t('折叠', 'Collapse')
                    : t('展开', 'Expand'),
                onPressed: () => setState(() {
                  if (!_expanded.remove(node.id)) _expanded.add(node.id);
                }),
                icon: Icon(
                  _expanded.contains(node.id)
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  color: const Color(0xff155af5),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.description_outlined,
                  color: Color(0xff155af5),
                ),
              ),
            Expanded(
              child: TextButton(
                onPressed: _opening ? null : () => _open(node),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                ),
                child: Text(
                  node.name,
                  style: TextStyle(
                    fontWeight: node.children.isNotEmpty
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: Color(0xff98a2b3)),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      if (_expanded.contains(node.id)) ..._rows(node.children, depth + 1),
    ],
  ];
  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Scaffold(
      backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
      appBar: AppBar(
        title: Text(t('共享目录', 'Shared contents')),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: t('重新加载', 'Reload'),
            icon: const Icon(Icons.refresh),
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
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: Text(t('重试', 'Retry')),
                      ),
                    ],
                  ),
                ),
              )
            : book == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffe3edff),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Text(
                                    t('公开分享 · 书籍', 'Public share · Book'),
                                    style: const TextStyle(
                                      color: Color(0xff155af5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  book.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (book.author.isNotEmpty) book.author,
                                    t('公开只读', 'Public read-only'),
                                  ].join(' · '),
                                ),
                                if (book.description.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(book.description),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.white,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t('章节目录', 'Chapters'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      t(
                                        '已载入 ${flattenPublicChapters(book.nodes).length} 个章节',
                                        '${flattenPublicChapters(book.nodes).length} chapters loaded',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              if (book.nodes.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    t(
                                      '此共享目录暂无章节。',
                                      'No chapters in this shared book.',
                                    ),
                                  ),
                                )
                              else
                                ..._rows(book.nodes, 0),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xffe3edff),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Color(0xff155af5),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  t(
                                    '此目录来自公开分享，阅读不会修改原书。',
                                    'This is public shared content. Reading does not modify the original book.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
