import 'home_dashboard_controller.dart';
import '../core/home_dashboard_models.dart';
import '../core/home_dashboard_repository.dart';
import 'home_dashboard_page.dart';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/strings.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.strings,
    required this.load,
    required this.onLanguage,
    required this.onNavigate,
    required this.local,
    this.canNavigate,
    this.dashboard,
    this.onDashboardItem,
    this.onDashboardAll,
    this.onResetLocalPreferences,
    this.onDashboardCustomize,
  }) : assert(
         dashboard == null ||
             (onDashboardItem != null && onDashboardAll != null),
       );
  final AppStrings strings;
  final Future<Map<String, Object?>> Function() load;
  final VoidCallback onLanguage;
  final void Function(String route) onNavigate;
  final bool local;
  final HomeDashboardRepository? dashboard;
  final void Function(String, HomeContentItem)? onDashboardItem;
  final void Function(String)? onDashboardAll;
  final Future<void> Function()? onResetLocalPreferences;
  final Future<void> Function(HomeDashboardController)? onDashboardCustomize;
  final bool Function(String)? canNavigate;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<Map<String, Object?>> _summary;
  String t(String key) => widget.strings.text(key);
  @override
  void initState() {
    super.initState();
    _summary = widget.dashboard == null
        ? widget.load()
        : Future.value(<String, Object?>{});
  }

  VoidCallback? action(String route) => widget.canNavigate?.call(route) == false
      ? null
      : () => widget.onNavigate(route);
  Future<void> _refresh() async {
    final future = widget.load();
    setState(() {
      _summary = future;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder renders the failure. */
    }
  }

  Widget _recent(AsyncSnapshot<Map<String, Object?>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snapshot.hasError) {
      return Column(
        children: [
          Text(t('connectionFailed')),
          TextButton(onPressed: _refresh, child: Text(t('retry'))),
        ],
      );
    }
    final raw = snapshot.data?['recent'];
    final items = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .where(
                (item) =>
                    [
                      'blog',
                      'note',
                      'article',
                      'book',
                      'document',
                    ].contains(item['type']) &&
                    item['id'] is int &&
                    (item['id'] as int) > 0,
              )
              .toList()
        : <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          t('nothingRecent'),
          style: const TextStyle(color: AppColors.secondary),
        ),
      );
    }
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: Icon(
                item['type'] == 'book'
                    ? Icons.menu_book_outlined
                    : Icons.description_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                item['title'] is String ? item['title'] as String : '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle:
                  item['context'] is String &&
                      (item['context'] as String).isNotEmpty
                  ? Text(
                      item['context'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right),
              // Go returns note/article; older and local summaries use blog.
              // URL is only a server hint, never a navigation capability.
              onTap: action(
                '${['note', 'article'].contains(item['type']) ? 'blog' : item['type']}/${item['id']}',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.dashboard == null
      ? _legacyBuild(context)
      : HomeDashboardPage(
          repository: widget.dashboard!,
          strings: widget.strings,
          local: widget.local,
          onLanguage: widget.onLanguage,
          onNavigate: widget.onNavigate,
          canNavigate: widget.canNavigate,
          onOpenItem: widget.onDashboardItem!,
          onOpenAll: widget.onDashboardAll!,
          onResetLocalPreferences: widget.onResetLocalPreferences,
          onCustomize: widget.onDashboardCustomize,
        );
  Widget _legacyBuild(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: accountCanvas(context, AppColors.background),
      title: const Text(
        'BookStark',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      ),
      actions: [
        if (widget.local)
          IconButton(
            tooltip: widget.strings.english
                ? 'Local backup and migration'
                : '本地备份与迁移',
            onPressed: action('local-backup'),
            icon: const Icon(Icons.backup_outlined),
          ),
        IconButton(
          tooltip: widget.strings.english ? 'Language' : '语言',
          onPressed: widget.onLanguage,
          icon: const Icon(Icons.translate),
        ),
        IconButton(
          tooltip: t('me'),
          onPressed: action('profile'),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  leading: Icon(
                    widget.local ? Icons.folder_outlined : Icons.cloud_outlined,
                  ),
                  title: Text(t(widget.local ? 'localSpace' : 'serverSpace')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: action('space'),
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(widget.strings.english ? 'Settings' : '设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: action('settings'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t('journey'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t('journeyHint'),
                style: const TextStyle(color: AppColors.secondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: action('search'),
                icon: const Icon(Icons.search),
                label: Text(t('search')),
              ),
              const SizedBox(height: 24),
              Text(t('recent'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              FutureBuilder(
                future: _summary,
                builder: (context, snapshot) => _recent(snapshot),
              ),
              const SizedBox(height: 24),
              Text(
                t('shortcuts'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scaled = MediaQuery.textScalerOf(context).scale(14);
                  final scale = scaled < 14 ? 1.0 : scaled / 14;
                  final columns = (constraints.maxWidth / (140 * scale))
                      .floor()
                      .clamp(1, 2);
                  final extent = ((scaled * 3 + 24) / 4).ceil() * 4.0;
                  return GridView(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: extent < 56 ? 56.0 : extent,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    shrinkWrap: true,
                    primary: false,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final entry in <String, IconData>{
                        'notes': Icons.note_outlined,
                        'articles': Icons.article_outlined,
                        'books': Icons.menu_book_outlined,
                        'tasks': Icons.check_box_outlined,
                        'bookmarks': Icons.bookmark_outline,
                        'nav': Icons.explore_outlined,
                        'topics': Icons.hub_outlined,
                        'labels': Icons.sell_outlined,
                        'images': Icons.photo_library_outlined,
                        'files': Icons.folder_outlined,
                        'trash': Icons.delete_outline,
                        'create-resource': Icons.add_circle_outline,
                        if (!widget.local) 'public-feed': Icons.public_outlined,
                        if (!widget.local) 'public-notes': Icons.notes_outlined,
                      }.entries)
                        FilledButton.tonalIcon(
                          onPressed: action(entry.key),
                          icon: Icon(entry.value),
                          label: Text(t(entry.key)),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: action('assistant'),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(t('assistant')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        final route = ['home', 'notes', 'bookmarks', 'files', 'profile'][index];
        action(route)?.call();
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: t('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.menu_book_outlined),
          label: t('knowledge'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.star_outline),
          label: t('favorites'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.folder_outlined),
          label: t('files'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          label: t('me'),
        ),
      ],
    ),
  );
}
