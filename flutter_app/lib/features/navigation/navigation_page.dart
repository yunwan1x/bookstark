import 'package:flutter/material.dart';
import '../../core/bookmark_favicon_store.dart';
import '../../widgets/bookmark_favicon.dart';
import '../../core/bookmarks_repository.dart';
import '../../core/bookmark_draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../core/navigation_repository.dart';
import '../../core/navigation_preferences.dart';
import '../../widgets/bookstark_markdown.dart';
import '../bookmarks/bookmarks_page.dart';
import '../bookmarks/bookmark_editor_page.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({
    super.key,
    required this.repository,
    required this.bookmarks,
    required this.labels,
    this.drafts,
    this.preferences,
    this.english = false,
    this.local = false,
    this.faviconStoreFactory,
    this.faviconIsCurrent,
  });
  final NavigationRepository repository;
  final BookmarksRepository bookmarks;
  final LabelsRepository labels;
  final BookmarkDraftVault? drafts;
  final NavigationPreferencesVault? preferences;
  final bool english, local;
  final BookmarkFaviconStore Function()? faviconStoreFactory;
  final bool Function()? faviconIsCurrent;
  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  final _search = TextEditingController();
  late BookmarkFaviconStore _favicons;
  NavigationResult? _data;
  NavigationPreferences _preferences = const NavigationPreferences();
  BookmarkScope _scope = BookmarkScope.mine;
  final Set<String> _collapsed = {};
  bool _loading = true, _busy = false, _refreshRequired = false;
  int _generation = 0, _preferenceGeneration = 0, _ownerEpoch = 0;
  bool _owns(int epoch) => mounted && epoch == _ownerEpoch;
  ValueChanged<T> _ownedSelection<T>(void Function(T) action) {
    final epoch = _ownerEpoch;
    return (value) {
      if (_owns(epoch)) action(value);
    };
  }

  String? _error, _preferenceError;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _favicons = widget.faviconStoreFactory?.call() ?? BookmarkFaviconStore();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant NavigationPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository) ||
        !identical(old.bookmarks, widget.bookmarks) ||
        !identical(old.preferences, widget.preferences) ||
        !identical(old.labels, widget.labels) ||
        !identical(old.drafts, widget.drafts) ||
        old.local != widget.local ||
        old.faviconStoreFactory != widget.faviconStoreFactory) {
      _favicons.retire();
      _favicons = widget.faviconStoreFactory?.call() ?? BookmarkFaviconStore();
      _ownerEpoch++;
      _generation++;
      _preferenceGeneration++;
      _data = null;
      _preferences = const NavigationPreferences();
      _scope = BookmarkScope.mine;
      _collapsed.clear();
      _search.clear();
      _error = null;
      _preferenceError = null;
      _loading = true;
      _busy = false;
      _refreshRequired = false;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final epoch = _ownerEpoch, preferences = widget.preferences;
    try {
      final value = await preferences?.read();
      if (_owns(epoch) && value != null) setState(() => _preferences = value);
    } catch (error) {
      if (_owns(epoch)) setState(() => _preferenceError = error.toString());
    }
    if (_owns(epoch)) await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.load(
        keyword: _search.text,
        scope: _scope,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
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

  Future<void> _setPreferences(NavigationPreferences value) async {
    final generation = ++_preferenceGeneration;
    final epoch = _ownerEpoch, preferences = widget.preferences;
    try {
      await preferences?.write(value);
      if (_owns(epoch) && generation == _preferenceGeneration) {
        setState(() {
          _preferences = value;
          _preferenceError = null;
        });
      }
    } catch (error) {
      if (_owns(epoch) && generation == _preferenceGeneration) {
        setState(() => _preferenceError = error.toString());
      }
    }
  }

  Future<void> _manage() async {
    final epoch = _ownerEpoch;
    final bookmarks = widget.bookmarks,
        labels = widget.labels,
        drafts = widget.drafts;
    final english = widget.english, local = widget.local;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BookmarksPage(
          repository: bookmarks,
          labelsRepository: labels,
          vault: drafts,
          english: english,
          local: local,
        ),
      ),
    );
    if (_owns(epoch)) await _load();
  }

  Future<void> _action(BookmarkItem item, String action) async {
    final epoch = _ownerEpoch, bookmarks = widget.bookmarks;
    final labels = widget.labels, drafts = widget.drafts;
    final english = widget.english, local = widget.local;
    if (_loading || _busy || _refreshRequired || !bookmarks.canEdit(item)) {
      return;
    }
    if (action == 'edit') {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BookmarkEditorPage(
            repository: bookmarks,
            bookmark: item,
            labelsRepository: labels,
            vault: drafts,
            english: english,
            local: local,
          ),
        ),
      );
      if (changed == true && _owns(epoch)) await _load();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        title: Text(
          action == 'hide'
              ? t('从导航隐藏', 'Hide from navigation')
              : t('删除书签', 'Delete bookmark'),
        ),
        content: Text('${item.title}\n${item.url}'),
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
    );
    if (confirmed != true || !_owns(epoch)) return;
    setState(() => _busy = true);
    try {
      if (action == 'hide') {
        await bookmarks.setNavVisible(item.id!, false);
      } else {
        await bookmarks.remove(item.id!);
      }
      if (_owns(epoch)) await _load();
    } catch (error) {
      if (_owns(epoch)) {
        setState(() {
          _error = error.toString();
          _refreshRequired = true;
        });
      }
    } finally {
      if (_owns(epoch)) setState(() => _busy = false);
    }
  }

  Widget _tile(BookmarkItem item) {
    final compact = _preferences.view == NavigationView.compact;
    final ownerEpoch = _ownerEpoch, store = _favicons;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: BookmarkFavicon(
                  key: ValueKey((item.id, item.favicon, ownerEpoch)),
                  explicitUrl: item.favicon,
                  store: store,
                  scopeKey: (widget.repository, ownerEpoch),
                  isCurrent: () =>
                      _owns(ownerEpoch) &&
                      identical(store, _favicons) &&
                      !store.retired &&
                      (widget.faviconIsCurrent?.call() ?? true),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => openBookstarkLink(
                  context,
                  item.title,
                  item.url,
                  english: widget.english,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Uri.tryParse(item.url)?.host ?? item.url,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!compact && item.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.description,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (widget.bookmarks.canEdit(item))
              PopupMenuButton<String>(
                tooltip: t('快捷收藏操作', 'Shortcut actions'),
                enabled: !_loading && !_busy && !_refreshRequired,
                onSelected: _ownedSelection((value) => _action(item, value)),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
                  PopupMenuItem(
                    value: 'hide',
                    child: Text(t('从导航隐藏', 'Hide from navigation')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(t('删除书签', 'Delete bookmark')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    String name,
    List<BookmarkItem> items, {
    required String keyName,
    bool collapsible = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '$name  ${items.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          if (collapsible)
            IconButton(
              tooltip: _collapsed.contains(keyName)
                  ? t('展开', 'Expand')
                  : t('收起', 'Collapse'),
              onPressed: () => setState(() {
                if (!_collapsed.add(keyName)) _collapsed.remove(keyName);
              }),
              icon: Icon(
                _collapsed.contains(keyName)
                    ? Icons.expand_more
                    : Icons.expand_less,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (!_collapsed.contains(keyName))
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns =
                _preferences.view == NavigationView.cards &&
                    constraints.maxWidth >= 640 * scale
                ? 2
                : 1;
            if (columns == 1) {
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _tile(items[i]),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in items)
                  SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    child: _tile(item),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 24),
    ],
  );
  @override
  void dispose() {
    _favicons.retire();
    _ownerEpoch++;
    _generation++;
    _preferenceGeneration++;
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final available =
        data?.groups.map((group) => group.name).toSet() ?? <String>{};
    // Expired selections should never hide every current group.
    final active = _preferences.groups.intersection(available);
    final groups =
        data?.groups
            .where((group) => active.isEmpty || active.contains(group.name))
            .toList() ??
        [];
    final shown =
        (data?.pinned.length ?? 0) +
        groups.fold<int>(0, (count, group) => count + group.items.length) +
        (active.isEmpty ? data?.ungrouped.length ?? 0 : 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('导航', 'Navigation')),
        actions: [
          if (MediaQuery.textScalerOf(context).scale(14) > 20 ||
              (widget.english && MediaQuery.sizeOf(context).width < 400))
            IconButton(
              tooltip: t('管理书签', 'Manage bookmarks'),
              onPressed: _busy ? null : _manage,
              icon: const Icon(Icons.bookmarks_outlined),
            )
          else
            TextButton(
              onPressed: _busy ? null : _manage,
              child: Text(t('管理书签', 'Manage bookmarks')),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: t('搜索快捷收藏', 'Search shortcuts'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: t('搜索', 'Search'),
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: _busy ? null : (_) => _load(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: Text(t('全部', 'All')),
                    selected: active.isEmpty,
                    onSelected: (_) => _setPreferences(
                      NavigationPreferences(view: _preferences.view),
                    ),
                  ),
                  for (final name in available)
                    FilterChip(
                      label: Text(name),
                      selected: active.contains(name),
                      onSelected: (selected) {
                        final groups = Set<String>.of(active);
                        if (selected) {
                          groups.add(name);
                        } else {
                          groups.remove(name);
                        }
                        _setPreferences(
                          NavigationPreferences(
                            view: _preferences.view,
                            groups: groups,
                          ),
                        );
                      },
                    ),
                  PopupMenuButton<NavigationView>(
                    tooltip: t('切换视图', 'Change view'),
                    initialValue: _preferences.view,
                    onSelected: _ownedSelection(
                      (value) => _setPreferences(
                        NavigationPreferences(
                          view: value,
                          groups: _preferences.groups,
                        ),
                      ),
                    ),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: NavigationView.cards,
                        child: Text(t('卡片', 'Cards')),
                      ),
                      PopupMenuItem(
                        value: NavigationView.list,
                        child: Text(t('列表', 'List')),
                      ),
                      PopupMenuItem(
                        value: NavigationView.compact,
                        child: Text(t('紧凑', 'Compact')),
                      ),
                    ],
                    icon: Icon(
                      _preferences.view == NavigationView.cards
                          ? Icons.grid_view_outlined
                          : _preferences.view == NavigationView.list
                          ? Icons.view_list_outlined
                          : Icons.view_compact_outlined,
                    ),
                  ),
                  if (!widget.local)
                    PopupMenuButton<BookmarkScope>(
                      tooltip: t('收藏范围', 'Shortcut scope'),
                      initialValue: _scope,
                      onSelected: _busy
                          ? null
                          : _ownedSelection((value) {
                              _scope = value;
                              _data = null;
                              _load();
                            }),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: BookmarkScope.mine,
                          child: Text(t('我的收藏', 'My shortcuts')),
                        ),
                        PopupMenuItem(
                          value: BookmarkScope.public,
                          child: Text(t('公开收藏', 'Public shortcuts')),
                        ),
                      ],
                      icon: Icon(
                        _scope == BookmarkScope.mine
                            ? Icons.person_outline
                            : Icons.public,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_preferenceError != null) ...[
                Text(
                  _preferenceError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: () async {
                    final epoch = _ownerEpoch, preferences = widget.preferences;
                    try {
                      await preferences?.clear();
                      if (_owns(epoch)) {
                        setState(() {
                          _preferences = const NavigationPreferences();
                          _preferenceError = null;
                        });
                      }
                    } catch (error) {
                      if (_owns(epoch)) {
                        setState(() => _preferenceError = error.toString());
                      }
                    }
                  },
                  child: Text(t('重置显示偏好', 'Reset display preferences')),
                ),
              ],
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
              if (data != null) ...[
                Text(
                  t(
                    '当前显示$shown条 · 已加载${data.total}条',
                    'Showing $shown · ${data.total} loaded',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (data.pinned.isNotEmpty)
                  _section(
                    t('置顶', 'Pinned'),
                    data.pinned,
                    keyName: 'pinned',
                    collapsible: false,
                  ),
                for (final group in groups)
                  _section(
                    group.name,
                    group.items,
                    keyName: 'group:${group.name}',
                  ),
                if (active.isEmpty && data.ungrouped.isNotEmpty)
                  _section(
                    t('未分组', 'Ungrouped'),
                    data.ungrouped,
                    keyName: 'ungrouped',
                  ),
                if (!_loading && shown == 0 && _error == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(t('暂无快捷收藏', 'No shortcuts yet')),
                        Text(
                          t(
                            '在管理书签中设置“显示到导航”。',
                            'Choose “Show in navigation” in Manage bookmarks.',
                          ),
                        ),
                      ],
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
