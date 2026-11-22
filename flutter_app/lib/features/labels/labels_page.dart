import 'package:flutter/material.dart';
import '../../core/draft_vault.dart';
import '../../core/label_management_repository.dart';
import 'label_editor_page.dart';

class LabelsPage extends StatefulWidget {
  const LabelsPage({
    super.key,
    required this.repository,
    required this.onOpenLabel,
    required this.onRecommendations,
    required this.onMerge,
    this.drafts,
    this.onRecoverCreation,
    this.english = false,
    this.local = false,
  });
  final LabelManagementRepository repository;
  final Future<void> Function(ManagedLabel label) onOpenLabel, onMerge;
  final Future<void> Function() onRecommendations;
  final DraftVault? drafts;
  final Future<void> Function()? onRecoverCreation;
  final bool english, local;
  @override
  State<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<LabelsPage> {
  final _search = TextEditingController();
  LabelSort _sort = LabelSort.name;
  bool _descending = false,
      _loading = true,
      _busy = false,
      _more = false,
      _refreshRequired = false,
      _opening = false;
  int _page = 0, _total = 0, _used = 0, _unused = 0, _generation = 0;
  int _ownerEpoch = 0;
  bool _owns(int epoch, LabelManagementRepository repository) =>
      mounted &&
      epoch == _ownerEpoch &&
      identical(repository, widget.repository);
  String _keyword = '';
  String? _error;
  List<ManagedLabel> _rows = [];
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _canAct => mounted && !_loading && !_busy && !_refreshRequired;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LabelsPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository) ||
        !identical(old.drafts, widget.drafts) ||
        old.local != widget.local) {
      _ownerEpoch++;
      _generation++;
      _loading = true;
      _busy = false;
      _more = false;
      _refreshRequired = false;
      _opening = false;
      _page = 0;
      _total = 0;
      _used = 0;
      _unused = 0;
      _rows = [];
      _error = null;
      _keyword = '';
      _search.clear();
      _sort = LabelSort.name;
      _descending = false;
      _load();
    }
  }

  @override
  void dispose() {
    _ownerEpoch++;
    _generation++;
    _search.dispose();
    super.dispose();
  }

  LabelManagementQuery _query(int page) => LabelManagementQuery(
    keyword: _keyword,
    sort: _sort,
    descending: _descending,
    page: page,
  );
  Future<void> _load({bool more = false, bool reset = false}) async {
    final generation = ++_generation;
    final last = reset ? 1 : (_page < 1 ? 1 : _page);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = await widget.repository.list(_query(more ? _page + 1 : 1));
      final rows = more
          ? [..._rows, ...result.items]
          : List<ManagedLabel>.of(result.items);
      if (!more) {
        for (var page = 2; page <= last && result.hasMore; page++) {
          result = await widget.repository.list(_query(page));
          if (result.page != page || (result.hasMore && result.items.isEmpty)) {
            throw const FormatException('Label pagination changed');
          }
          rows.addAll(result.items);
        }
      }
      if (rows.map((row) => row.id).toSet().length != rows.length) {
        throw StateError(
          t('标签列表已变化，请刷新核对', 'Label list changed; reload to verify'),
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = rows;
        _page = result.page;
        _total = result.total;
        _used = result.used;
        _unused = result.unused;
        _more = result.hasMore;
        _refreshRequired = false;
      });
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

  Future<void> _open(Future<void> Function() operation) async {
    if (!_canAct || _opening) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    _opening = true;
    try {
      await operation();
      if (_owns(epoch, repository)) await _load();
    } catch (error) {
      if (_owns(epoch, repository)) setState(() => _error = error.toString());
    } finally {
      if (_owns(epoch, repository)) _opening = false;
    }
  }

  Future<void> _recoverCreation() async {
    final callback = widget.onRecoverCreation;
    if (!mounted || _busy || _opening || callback == null) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    _opening = true;
    try {
      await callback();
      if (_owns(epoch, repository)) await _load();
    } catch (error) {
      if (_owns(epoch, repository)) setState(() => _error = error.toString());
    } finally {
      if (_owns(epoch, repository)) _opening = false;
    }
  }

  Future<void> _edit([ManagedLabel? label]) {
    final repository = widget.repository, drafts = widget.drafts;
    final english = widget.english, local = widget.local;
    return _open(() async {
      await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => LabelEditorPage(
            repository: repository,
            label: label,
            vault: drafts,
            english: english,
            local: local,
          ),
        ),
      );
    });
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认', 'Confirm')),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _mutate(Future<void> Function() operation) async {
    if (!_canAct) return;
    final epoch = _ownerEpoch, repository = widget.repository;
    setState(() => _busy = true);
    try {
      await operation();
      if (_owns(epoch, repository)) await _load();
    } catch (error) {
      if (_owns(epoch, repository)) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (_owns(epoch, repository)) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ManagedLabel item) async {
    final epoch = _ownerEpoch, repository = widget.repository;
    final yes = await _confirm(
      t('永久删除标签？', 'Permanently delete label?'),
      '${item.name}\n${widget.local ? t('永久删除当前本地空间此标签及全部关联，源资源保留，不能从回收站恢复。', 'Permanently deletes this label and all associations in this space. Source resources remain; no trash recovery.') : t('永久删除全服务器此标签及全部关联，源资源保留，不能从回收站恢复。', 'Permanently deletes this label and all associations across this server. Source resources remain; no trash recovery.')}',
    );
    if (!yes || !_owns(epoch, repository)) return;
    await _mutate(() => repository.remove(item.id));
  }

  Future<void> _clearUnused() async {
    final epoch = _ownerEpoch, repository = widget.repository;
    final yes = await _confirm(
      t('清除全部未使用标签？', 'Clear all unused labels?'),
      widget.local
          ? t(
              '永久清除当前本地空间全部未使用标签，不限当前搜索；不能从回收站恢复。',
              'Permanently clears all unused labels in this space, including outside the current search. No trash recovery.',
            )
          : t(
              '永久清除全服务器全部未使用标签，不限当前搜索；不能从回收站恢复。',
              'Permanently clears all unused labels on this server, including outside the current search. No trash recovery.',
            ),
    );
    if (!yes || !_owns(epoch, repository)) return;
    await _mutate(() async {
      final count = await repository.removeUnused();
      if (mounted && _owns(epoch, repository)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('已清除标签：', 'Cleared labels: ') + count.toString()),
          ),
        );
      }
    });
  }

  String _sortName(LabelSort sort) => switch (sort) {
    LabelSort.name => t('名称', 'Name'),
    LabelSort.book => t('书籍数量', 'Books'),
    LabelSort.blog => t('笔记/文章数量', 'Notes/articles'),
    LabelSort.bookmark => t('书签数量', 'Bookmarks'),
    LabelSort.total => t('三类关联总数', 'Three-type total'),
    LabelSort.recent => t('最近90天关联', 'Last 90 days'),
  };
  Widget _stat(String label, int value) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text(
              '$value',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _card(ManagedLabel item) {
    final epoch = _ownerEpoch, repository = widget.repository;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _canAct
            ? () {
                if (_owns(epoch, repository)) {
                  _open(() => widget.onOpenLabel(item));
                }
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.sell_outlined, color: Color(0xff2563eb)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.repository.canManage)
                    PopupMenuButton<String>(
                      tooltip: t('标签操作', 'Label actions'),
                      enabled: _canAct,
                      onSelected: (value) {
                        if (!_owns(epoch, repository)) return;
                        switch (value) {
                          case 'edit':
                            _edit(item);
                          case 'merge':
                            _open(() => widget.onMerge(item));
                          case 'delete':
                            _remove(item);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(t('重命名', 'Rename')),
                        ),
                        PopupMenuItem(
                          value: 'merge',
                          child: Text(t('合并到此标签', 'Merge into this label')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(t('删除', 'Delete')),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '书籍${item.bookCount} · 笔记/文章${item.blogCount} · 书签${item.bookmarkCount}',
                  'Books ${item.bookCount} · Notes/articles ${item.blogCount} · Bookmarks ${item.bookmarkCount}',
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final epoch = _ownerEpoch, repository = widget.repository;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('标签管理', 'Labels')),
        actions: [
          if (widget.onRecoverCreation != null)
            IconButton(
              tooltip: t('创建恢复记录', 'Creation recovery'),
              onPressed: _busy || _opening ? null : _recoverCreation,
              icon: const Icon(Icons.history),
            ),
          if (widget.repository.canManage)
            PopupMenuButton<String>(
              tooltip: t('管理操作', 'Management actions'),
              enabled: _canAct,
              onSelected: (_) {
                if (_owns(epoch, repository)) _clearUnused();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Text(t('清除未使用标签', 'Clear unused labels')),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        tooltip: t('新建标签', 'New label'),
        onPressed: _canAct
            ? () {
                if (_owns(epoch, repository)) _edit();
              }
            : null,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  _keyword = _search.text;
                  _load(reset: true);
                },
                decoration: InputDecoration(
                  labelText: t('搜索标签', 'Search labels'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: t('搜索', 'Search'),
                    onPressed: _busy
                        ? null
                        : () {
                            _keyword = _search.text;
                            _load(reset: true);
                          },
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stat(t('全部', 'Total'), _total),
                  _stat(t('使用中', 'Used'), _used),
                  _stat(t('未使用', 'Unused'), _unused),
                ],
              ),
              if (_keyword.isNotEmpty)
                Text(
                  t(
                    '统计仅含当前搜索匹配标签',
                    'Counts reflect labels matching this search',
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  PopupMenuButton<LabelSort>(
                    enabled: !_busy,
                    tooltip: t('排序', 'Sort'),
                    onSelected: (value) {
                      setState(() => _sort = value);
                      _load(reset: true);
                    },
                    itemBuilder: (_) => [
                      for (final value in LabelSort.values)
                        PopupMenuItem(
                          value: value,
                          child: Text(_sortName(value)),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${_sortName(_sort)} ${_descending ? '↓' : '↑'}',
                        style: const TextStyle(color: Color(0xff2563eb)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('切换排序方向', 'Reverse order'),
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _descending = !_descending);
                            _load(reset: true);
                          },
                    icon: Icon(_descending ? Icons.south : Icons.north),
                  ),
                  TextButton(
                    onPressed: _canAct
                        ? () => _open(widget.onRecommendations)
                        : null,
                    child: Text(t('推荐设置', 'Recommendations')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                t('全部标签', 'All labels'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _load(),
                  child: Text(t('刷新核对', 'Reload to verify')),
                ),
              ],
              for (final row in _rows) _card(row),
              if (_rows.isEmpty && !_loading)
                Text(t('没有匹配标签', 'No matching labels')),
              if (_more)
                OutlinedButton(
                  onPressed: _canAct ? () => _load(more: true) : null,
                  child: Text(t('加载更多', 'Load more')),
                ),
              if (_loading || _busy)
                const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 24),
              Text(
                widget.local
                    ? t('标签保存在当前本地空间', 'Labels belong to this local space')
                    : t('标签在服务器内共享', 'Labels are shared across this server'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
