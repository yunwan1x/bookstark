import 'package:flutter/material.dart';
import '../../core/draft_vault.dart';
import '../../core/label_management_repository.dart';
import 'label_editor_page.dart';
import 'label_merge_page.dart';

class LabelDetailPage extends StatefulWidget {
  const LabelDetailPage({
    super.key,
    required this.repository,
    required this.labelId,
    required this.onOpenResource,
    this.drafts,
    this.english = false,
    this.local = false,
  });
  final LabelManagementRepository repository;
  final int labelId;
  final Future<void> Function(LabelResource resource) onOpenResource;
  final DraftVault? drafts;
  final bool english, local;
  @override
  State<LabelDetailPage> createState() => _LabelDetailPageState();
}

class _LabelDetailPageState extends State<LabelDetailPage> {
  final _search = TextEditingController();
  ManagedLabelDetail? _detail;
  LabelResourceType? _type;
  bool _loading = true,
      _busy = false,
      _opening = false,
      _refreshRequired = false;
  int _generation = 0;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _canAct =>
      !_loading && !_busy && !_refreshRequired && _detail != null;
  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  void _filter() {
    setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.read(widget.labelId);
      if (mounted && generation == _generation) {
        setState(() {
          _detail = detail;
          _refreshRequired = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(LabelResource item) async {
    if (!_canAct || _opening) return;
    _opening = true;
    try {
      await widget.onOpenResource(item);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _opening = false;
    }
  }

  Future<void> _settings(bool merge) async {
    if (!_canAct || _opening) return;
    _opening = true;
    try {
      await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => merge
              ? LabelMergePage(
                  repository: widget.repository,
                  target: _detail!.label,
                  english: widget.english,
                  local: widget.local,
                )
              : LabelEditorPage(
                  repository: widget.repository,
                  label: _detail!.label,
                  vault: widget.drafts,
                  english: widget.english,
                  local: widget.local,
                ),
        ),
      );
      if (mounted) await _load();
    } finally {
      _opening = false;
    }
  }

  Future<void> _unbind(LabelResource item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('解除此标签关联？', 'Remove this label association?')),
        content: Text(
          t(
            '将从此资源移除“${_detail!.label.name}”标签，保留资源本体。服务器会验证当前账号的操作权限。',
            'Removes “${_detail!.label.name}” from this resource. The resource remains; the server checks your permission.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('解除关联', 'Remove association')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_canAct) return;
    setState(() => _busy = true);
    try {
      await widget.repository.unbind(widget.labelId, item);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kind(LabelResourceType value) => switch (value) {
    LabelResourceType.book => t('书籍', 'Book'),
    LabelResourceType.blog => t('笔记/文章', 'Note/article'),
    LabelResourceType.bookmark => t('书签', 'Bookmark'),
    LabelResourceType.document => t('文档', 'Document'),
  };
  IconData _icon(LabelResourceType value) => switch (value) {
    LabelResourceType.book => Icons.menu_book_outlined,
    LabelResourceType.blog => Icons.edit_note,
    LabelResourceType.bookmark => Icons.bookmark_outline,
    LabelResourceType.document => Icons.description_outlined,
  };
  String _title(LabelResource item) =>
      item.title.isEmpty ? '${_kind(item.type)} #${item.id}' : item.title;
  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final keyword = _search.text.toLowerCase();
    final items =
        detail?.items
            .where(
              (item) =>
                  (_type == null || item.type == _type) &&
                  '${_title(item)} ${item.id}'.toLowerCase().contains(keyword),
            )
            .toList() ??
        <LabelResource>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.label.name ?? t('标签详情', 'Label details')),
        actions: [
          if (widget.repository.canManage && detail != null)
            PopupMenuButton<String>(
              tooltip: t('标签操作', 'Label actions'),
              enabled: _canAct,
              onSelected: (value) => _settings(value == 'merge'),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('重命名', 'Rename'))),
                PopupMenuItem(
                  value: 'merge',
                  child: Text(t('合并到此标签', 'Merge into this label')),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: Text(t('刷新核对', 'Reload to verify')),
                ),
              ],
              if (detail != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.sell_outlined,
                              color: Color(0xff2563eb),
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                detail.label.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.local
                              ? t('本地空间标签', 'Local space label')
                              : t('共享标签', 'Shared label'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t(
                            '书籍${detail.label.bookCount} · 笔记/文章${detail.label.blogCount} · 书签${detail.label.bookmarkCount}',
                            'Books ${detail.label.bookCount} · Notes/articles ${detail.label.blogCount} · Bookmarks ${detail.label.bookmarkCount}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!widget.local)
                  Text(
                    t(
                      '最多返回500项${detail.possiblyTruncated ? '，当前列表可能未包含全部关联' : ''}',
                      'Returns up to 500 items${detail.possiblyTruncated ? '; more associations may exist' : ''}',
                    ),
                  ),
                if (detail.verifiedUnused)
                  Text(
                    t('此标签尚未关联资源', 'This label has no associated resources'),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: t('搜索已加载关联', 'Search loaded associations'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(t('全部', 'All')),
                      selected: _type == null,
                      onSelected: (_) => setState(() => _type = null),
                    ),
                    for (final type in LabelResourceType.values)
                      ChoiceChip(
                        label: Text(_kind(type)),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  t(
                    '关联资源 · 显示${items.length}项 / 已加载${detail.items.length}项',
                    'Associations · ${items.length} shown / ${detail.items.length} loaded',
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                for (final item in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _icon(item.type),
                            color: const Color(0xff2563eb),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _canAct ? () => _open(item) : null,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title(item),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text('${_kind(item.type)} · ID ${item.id}'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: t('解除关联', 'Remove association'),
                            onPressed: _canAct ? () => _unbind(item) : null,
                            icon: const Icon(Icons.link_off),
                          ),
                          IconButton(
                            tooltip: t('打开资源', 'Open resource'),
                            onPressed: _canAct ? () => _open(item) : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (items.isEmpty && detail.items.isNotEmpty)
                  Text(t('没有匹配关联', 'No matching associations')),
                const SizedBox(height: 16),
                Text(
                  t(
                    '关联由当前账号权限控制。',
                    'Associations are subject to account permissions.',
                  ),
                ),
              ],
              if (_loading || _busy)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
