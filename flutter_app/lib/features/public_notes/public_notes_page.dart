import '../../core/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/public_notes_repository.dart';

class PublicNotesPage extends StatefulWidget {
  const PublicNotesPage({
    super.key,
    required this.repository,
    required this.onOpen,
    this.english = false,
  });
  final PublicNotesRepository repository;
  final Future<void> Function(PublicNotePreview) onOpen;
  final bool english;
  @override
  State<PublicNotesPage> createState() => _PublicNotesPageState();
}

class _PublicNotesPageState extends State<PublicNotesPage> {
  PublicNotesPageData? _data;
  int _page = 1, _generation = 0;
  bool _loading = false, _opening = false;
  String? _error, _label;
  Completer<void>? _abort;
  final _scroll = ScrollController();
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _generation++;
    _abort?.complete();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    _abort?.complete();
    final abort = _abort = Completer<void>(), generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
      _label = null;
      _page = page;
    });
    try {
      final actual = await widget.repository.load(
        page,
        abortTrigger: abort.future,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      if (actual.page != page) {
        throw const FormatException('Public notes page mismatch');
      }
      setState(() => _data = actual);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _error = t(
          '无法加载公开笔记，请检查连接后重试。',
          'Public notes could not load. Check your connection and retry.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(PublicNotePreview item) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      await widget.onOpen(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开这篇公开笔记。', 'This public note could not be opened.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  String _date(DateTime time) {
    final date = time.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _badge(String text, {bool locked = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: locked ? const Color(0xfffff0d9) : const Color(0xffe3edff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: locked ? const Color(0xff9a5700) : const Color(0xff0b4eff),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _note(PublicNotePreview item) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.locked) const Icon(Icons.lock_outline),
              _badge(
                item.locked
                    ? t('正文需密码', 'Body password required')
                    : t('公开', 'Public'),
                locked: item.locked,
              ),
              if (item.pinned) _badge(t('置顶', 'Pinned')),
              Text(
                '${t('更新于', 'Updated')} ${_date(item.modified)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (item.locked)
            Text(t('验证密码后阅读正文。', 'Verify the password to read this body.'))
          else if (item.preview.isNotEmpty)
            Text(item.preview, maxLines: 4, overflow: TextOverflow.ellipsis),
          if (!item.locked && item.labels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final label in item.labels) _badge(label)],
            ),
          ],
          const SizedBox(height: 12),
          if (!item.locked) const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: item.locked
                ? FilledButton(
                    onPressed: _opening ? null : () => _open(item),
                    child: Text(t('解锁阅读', 'Unlock and read')),
                  )
                : TextButton.icon(
                    onPressed: _opening ? null : () => _open(item),
                    icon: const Icon(Icons.arrow_forward),
                    iconAlignment: IconAlignment.end,
                    label: Text(t('打开完整笔记', 'Open full note')),
                  ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final data = _data, labels = data?.labels.toList() ?? <String>[];
    labels.sort();
    final items =
        data?.items
            .where((item) => _label == null || item.labels.contains(_label))
            .toList() ??
        <PublicNotePreview>[];
    return Scaffold(
      backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
      appBar: AppBar(
        title: Text(t('公开笔记', 'Public notes')),
        actions: [
          IconButton(
            tooltip: t('刷新', 'Refresh'),
            onPressed: _loading ? null : () => _load(_page),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('把想法留在这里', 'Leave your thoughts here'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('公开记录，只读浏览。', 'Public records. Read-only browsing.'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      size: 56,
                      color: Color(0xff91b3ff),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(t('本页全部', 'All on this page')),
                    selected: _label == null,
                    onSelected: _loading
                        ? null
                        : (_) => setState(() => _label = null),
                  ),
                  for (final label in labels)
                    ChoiceChip(
                      label: Text(label),
                      selected: _label == label,
                      onSelected: (_) => setState(() => _label = label),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t('标签筛选仅针对本页。', 'Tag filters apply only to this page.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null) ...[
                Text(_error!),
                TextButton(
                  onPressed: () => _load(_page),
                  child: Text(t('重试', 'Retry')),
                ),
              ],
              if (data != null && data.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t('这一页暂无公开笔记。', 'No public notes on this page.')),
                ),
              if (data != null && data.items.isNotEmpty && items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t('本页没有匹配此标签的笔记。', 'No notes with this tag on this page.'),
                  ),
                ),
              for (final item in items) _note(item),
              if (data != null)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _loading || _page == 1
                          ? null
                          : () => _load(_page - 1),
                      child: Text(t('上一页', 'Previous')),
                    ),
                    Text(
                      t(
                        '第$_page页 · 本页${data.items.length}条',
                        'Page $_page · ${data.items.length} loaded',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _loading || !data.canRequestNext
                          ? null
                          : () => _load(_page + 1),
                      child: Text(t('下一页', 'Next')),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
