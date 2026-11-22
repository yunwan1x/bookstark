import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/home_dashboard_models.dart';
import '../core/home_dashboard_repository.dart';
import '../core/strings.dart';
import 'home_dashboard_controller.dart';
import 'home_layout_page.dart';

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({
    super.key,
    required this.repository,
    required this.strings,
    required this.local,
    required this.onLanguage,
    required this.onNavigate,
    required this.onOpenItem,
    required this.onOpenAll,
    this.canNavigate,
    this.initialQuery,
    this.onResetLocalPreferences,
    this.onCustomize,
  });
  final HomeDashboardRepository repository;
  final HomeQuery? initialQuery;
  final Future<void> Function()? onResetLocalPreferences;
  final Future<void> Function(HomeDashboardController)? onCustomize;
  final AppStrings strings;
  final bool local;
  final VoidCallback onLanguage;
  final void Function(String) onNavigate, onOpenAll;
  final void Function(String, HomeContentItem) onOpenItem;
  final bool Function(String)? canNavigate;
  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  late HomeDashboardController state;
  bool _confirming = false;
  String t(String zh, String en) => widget.strings.english ? en : zh;
  VoidCallback? action(String route) => widget.canNavigate?.call(route) == false
      ? null
      : () => widget.onNavigate(route);
  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    state = HomeDashboardController(
      widget.repository,
      query: widget.initialQuery,
    )..addListener(_changed);
    unawaited(state.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant HomeDashboardPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository)) {
      state.removeListener(_changed);
      state.dispose();
      _open();
    }
  }

  @override
  void dispose() {
    state.removeListener(_changed);
    state.dispose();
    super.dispose();
  }

  bool get ready =>
      !state.loading && state.problem == null && state.snapshot != null;
  bool get locked => state.loading || state.writing || state.needsReadback;
  String moduleName(String key) => {
    'notes': t('笔记', 'Notes'),
    'articles': t('文章', 'Articles'),
    'tasks': t('待办', 'Tasks'),
    'books': t('书籍', 'Books'),
    'bookmarks': t('书签', 'Bookmarks'),
    'topics': t('专题', 'Topics'),
    'nav': t('导航', 'Navigation'),
    'shares': t('我的分享', 'My shares'),
    'assets': t('资产', 'Assets'),
  }[key]!;
  IconData moduleIcon(String key) => switch (key) {
    'notes' => Icons.note_outlined,
    'articles' => Icons.article_outlined,
    'tasks' => Icons.check_box_outlined,
    'books' => Icons.menu_book_outlined,
    'bookmarks' => Icons.bookmark_outline,
    'topics' => Icons.hub_outlined,
    'nav' => Icons.explore_outlined,
    'shares' => Icons.share_outlined,
    _ => Icons.dns_outlined,
  };
  Future<void> _clearVisits() async {
    if (_confirming || locked || state.snapshot!.recent.isEmpty) return;
    setState(() => _confirming = true);
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('清空最近访问？', 'Clear recent visits?')),
          content: Text(
            widget.local
                ? t(
                    '只清空当前设备此本地空间的访问记录，不会删除笔记、文章或书籍。',
                    'Clear visits for this local space on this device. Notes, articles and books will not be deleted.',
                  )
                : t(
                    '只清空当前账号所有设备上的访问记录，不会删除笔记、文章或书籍。',
                    'Clear visits for this account on all devices. Notes, articles and books will not be deleted.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: Text(t('清空记录', 'Clear visits')),
            ),
          ],
        ),
      );
      if (yes == true && mounted && !state.retired) await state.clearVisits();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _customize() async {
    if (locked || state.snapshot == null) return;
    final custom = widget.onCustomize;
    if (custom != null) {
      await custom(state);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HomeLayoutPage(
          controller: state,
          english: widget.strings.english,
          local: widget.local,
          scopeLabel: widget.local
              ? t('当前设备 · 当前本地空间', 'This device · Current local space')
              : t('当前服务器 · 当前账号', 'Current server · Current account'),
        ),
      ),
    );
  }

  Future<void> _resetPreferences() async {
    final reset = widget.onResetLocalPreferences;
    if (reset == null || state.loading || state.writing) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('重置首页偏好？', 'Reset home preferences?')),
        content: Text(
          t(
            '仅重置当前本地空间的首页布局、筛选和访问记录，不会删除任何笔记、文章、书籍或附件。',
            'Only the home layout, filters and visits for this local space will be reset. Notes, articles, books and attachments will not be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('重置首页偏好', 'Reset home preferences')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await reset();
      if (mounted) await state.load(HomeQuery());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '偏好重置未完成，请重试。',
                'Preferences could not be reset. Please retry.',
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _notice() {
    final error = state.problem;
    final expired = error is ApiFailure && error.status == 401;
    final message = state.needsReadback
        ? t(
            '操作结果尚未确认。请先重新读取核对，不要重复提交。',
            'The result is unknown. Read back the current state before another submission.',
          )
        : expired
        ? t('登录已失效，请重新登录。', 'Your session expired. Sign in again.')
        : error is HomeQueryPreferenceFailure
        ? t(
            '首页筛选偏好未确认保存，请重试。',
            'Home filter preferences could not be confirmed. Please retry.',
          )
        : t('首页暂时无法读取，请重试。', 'Home could not be loaded. Please retry.');
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: state.writing
                ? null
                : expired
                ? action('space')
                : () => state.load(),
            child: Text(
              expired
                  ? t('重新登录', 'Sign in again')
                  : state.needsReadback
                  ? t('重新读取核对', 'Read back current state')
                  : t('重试读取', 'Retry loading'),
            ),
          ),
          if (widget.local &&
              error is HomePreferencesCorrupt &&
              widget.onResetLocalPreferences != null)
            TextButton(
              onPressed: _resetPreferences,
              child: Text(t('重置首页偏好', 'Reset home preferences')),
            ),
        ],
      ),
    );
  }

  Widget _filters() {
    final query = state.query;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final previous = query.view == HomeCalendarView.month
        ? query.month.year > 1
        : query.month.year > 1 || query.month.month > 1;
    final next = query.view == HomeCalendarView.month
        ? query.month.year < 9999
        : query.month.year < 9999 || query.month.month < 12;
    final order = DropdownButtonFormField<String>(
      key: ValueKey('home-order-${query.order}'),
      initialValue: query.order,
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: t('内容排序', 'Content order'),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: 'updated',
          child: Text(t('最近更新', 'Last updated')),
        ),
        DropdownMenuItem(
          value: 'created',
          child: Text(t('最近创建', 'Created recently')),
        ),
      ],
      onChanged: state.writing
          ? null
          : (value) {
              if (value != null) {
                unawaited(state.load(query.copyWith(order: value)));
              }
            },
    );
    final limit = DropdownButtonFormField<int>(
      key: ValueKey('home-limit-${query.limit}'),
      initialValue: query.limit,
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: t('每类显示', 'Items per module'),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final value in [5, 10, 20, 50])
          DropdownMenuItem(
            value: value,
            child: Text(t('每类$value条', '$value per module')),
          ),
      ],
      onChanged: state.writing
          ? null
          : (value) {
              if (value != null) {
                unawaited(state.load(query.copyWith(limit: value)));
              }
            },
    );
    return _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: SegmentedButton<HomeCalendarView>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: HomeCalendarView.day,
                      label: Text(t('日', 'Day')),
                    ),
                    ButtonSegment(
                      value: HomeCalendarView.week,
                      label: Text(t('周', 'Week')),
                    ),
                    ButtonSegment(
                      value: HomeCalendarView.month,
                      label: Text(t('月', 'Month')),
                    ),
                  ],
                  selected: {query.view},
                  onSelectionChanged: state.writing
                      ? null
                      : (value) =>
                            state.load(query.copyWith(view: value.single)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: t('上一周期', 'Previous period'),
                onPressed: state.writing || !previous
                    ? null
                    : () => state.load(query.movePeriod(-1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  query.view == HomeCalendarView.month
                      ? '${query.month.year}'
                      : t(
                          '${query.month.year}年${query.month.month}月',
                          '${query.month.year} / ${query.month.month}',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: t('下一周期', 'Next period'),
                onPressed: state.writing || !next
                    ? null
                    : () => state.load(query.movePeriod(1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: state.writing
                  ? null
                  : () => state.load(query.copyWith(month: DateTime.now())),
              child: Text(t('当前周期', 'Current period')),
            ),
          ),
          _calendar(),
          const SizedBox(height: 12),
          if (scale > 1.25) ...[
            order,
            const SizedBox(height: 12),
            limit,
          ] else
            Row(
              children: [
                Expanded(child: order),
                const SizedBox(width: 12),
                Expanded(child: limit),
              ],
            ),
          if (query.end != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(t('截至 ${query.end}', 'Through ${query.end}')),
                onDeleted: state.writing
                    ? null
                    : () => state.load(query.copyWith(clearEnd: true)),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            t(
              '颜色表示所选周期的内容数量；点击后查看截至周期末的内容。最近访问不受此筛选影响。',
              'Colors show activity in each period. Select a period to view content through its end. Recent visits are independent.',
            ),
            style: const TextStyle(color: AppColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _calendar() {
    final query = state.query, periods = homeCalendarPeriods(state.query);
    final largest = state.snapshot?.activity.values.fold<int>(0, math.max) ?? 0;
    int? count(HomeCalendarPeriod p) {
      if (!ready) return null;
      final from = homeDayKey(p.start), to = homeDayKey(p.end);
      return state.snapshot!.activity.entries
          .where((e) => e.key.compareTo(from) >= 0 && e.key.compareTo(to) <= 0)
          .fold<int>(0, (a, b) => a + b.value);
    }

    Widget tile(HomeCalendarPeriod p) {
      final value = count(p), selected = query.end == p.cutoff;
      final label = query.view == HomeCalendarView.day
          ? '${p.start.day}'
          : query.view == HomeCalendarView.month
          ? t('${p.start.month}月', '${p.start.month}')
          : '${p.start.month}/${p.start.day} – ${p.end.month}/${p.end.day}';
      final text =
          '${homeDayKey(p.start)} – ${p.cutoff} · ${value == null ? t('加载中', 'Loading') : t('$value条', '$value items')}';
      return Tooltip(
        message: text,
        child: Semantics(
          button: true,
          selected: selected,
          label: text,
          excludeSemantics: true,
          child: Material(
            color: selected
                ? AppColors.primary
                : value == null || value == 0
                ? const Color(0xfff1f5f9)
                : AppColors.primary.withValues(
                    alpha: 0.08 + 0.22 * value / math.max(largest, value),
                  ),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: state.writing
                  ? null
                  : () => state.load(query.copyWith(end: p.cutoff)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: selected ? Colors.white : null),
                    ),
                    Text(
                      value == null ? '…' : '$value',
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final scaled = MediaQuery.textScalerOf(context).scale(12),
            day = query.view == HomeCalendarView.day;
        final columns = day
            ? 7
            : (c.maxWidth / (110 * (scaled / 12))).floor().clamp(
                1,
                query.view == HomeCalendarView.week ? 2 : 3,
              );
        final width = day
            ? math
                  .max(c.maxWidth, 7 * math.max(48.0, scaled * 3) + 24)
                  .toDouble()
            : c.maxWidth;
        final grid = SizedBox(
          width: width,
          child: Column(
            children: [
              if (day)
                Row(
                  children: [
                    for (final weekday
                        in widget.strings.english
                            ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                            : ['周一', '周二', '周三', '周四', '周五', '周六', '周日'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            weekday,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: math.max(48, scaled * 4.0),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: periods.length,
                itemBuilder: (_, index) => tile(periods[index]),
              ),
            ],
          ),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: grid,
        );
      },
    );
  }

  Widget _box(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffe2e8f0)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
  Widget _recent() {
    final visits = state.snapshot?.recent ?? const <HomeRecentVisit>[];
    return _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                t('最近访问', 'Recent visits'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (visits.isNotEmpty)
                TextButton(
                  key: const Key('home-clear-visits'),
                  onPressed: locked || _confirming ? null : _clearVisits,
                  child: Text(t('清空', 'Clear')),
                ),
            ],
          ),
          if (!ready)
            Text(t('最近访问尚未读取成功。', 'Recent visits have not been loaded.'))
          else if (visits.isEmpty)
            Text(
              t(
                '还没有访问记录，打开笔记、文章或书籍后会显示在这里。',
                'No visits yet. Open a note, article or book to get started.',
              ),
            )
          else
            for (final visit in visits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  visit.kind == 'book'
                      ? Icons.menu_book_outlined
                      : Icons.description_outlined,
                ),
                title: Text(
                  visit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (visit.context.isNotEmpty) visit.context,
                    if (visit.visitedAt != null)
                      visit.visitedAt!.toLocal().toString().substring(0, 16),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: action(visit.route),
              ),
        ],
      ),
    );
  }

  Widget _section(HomeContentSection section) {
    final large = MediaQuery.textScalerOf(context).scale(14) > 18;
    final title = Row(
      children: [
        Icon(moduleIcon(section.key)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${moduleName(section.key)} · ${section.total}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
    final all = TextButton(
      onPressed: () => widget.onOpenAll(section.key),
      child: Text(
        section.key == 'shares'
            ? t('打开广场', 'Open community')
            : t('查看全部', 'View all'),
      ),
    );
    final unknown = state.snapshot!.unknownDates[section.key] ?? 0;
    return _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (large) ...[
            title,
            Align(alignment: Alignment.centerRight, child: all),
          ] else
            Row(
              children: [
                Expanded(child: title),
                all,
              ],
            ),
          if (unknown > 0)
            Text(
              t(
                '$unknown条记录的所选日期未知，未计入活动或日期筛选。',
                '$unknown items have an unknown selected date and are excluded from activity and date filtering.',
              ),
              style: const TextStyle(color: AppColors.secondary),
            ),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('没有符合筛选的内容', 'No matching content')),
            ),
          for (final item in section.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  item.date.isEmpty ? t('日期未知', 'Date unknown') : item.date,
                  if (item.badge.isNotEmpty) item.badge,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onOpenItem(section.key, item),
            ),
        ],
      ),
    );
  }

  Widget _sections() => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14,
          columns = (c.maxWidth / (280 * scale)).floor().clamp(1, 3);
      final sections = {
        for (final section in state.snapshot!.sections) section.key: section,
      };
      return Wrap(
        spacing: 12,
        runSpacing: 0,
        children: [
          for (final item in state.snapshot!.layout)
            if (!item.hidden && sections.containsKey(item.key))
              SizedBox(
                width:
                    (c.maxWidth - (columns - 1) * 12) /
                        columns *
                        math.min(item.width, columns) +
                    12 * (math.min(item.width, columns) - 1),
                child: _section(sections[item.key]!),
              ),
        ],
      );
    },
  );
  Widget _shortcuts() => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14,
          columns = (c.maxWidth / (140 * scale)).floor().clamp(1, 2);
      return GridView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: math.max(
            56,
            MediaQuery.textScalerOf(context).scale(14) * 3 + 24,
          ),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        children: [
          for (final key in [
            'notes',
            'articles',
            'books',
            'tasks',
            'bookmarks',
            'nav',
            'topics',
            'labels',
            'images',
            'files',
            'trash',
            'create-resource',
            if (!widget.local) 'public-feed',
            if (!widget.local) 'public-notes',
          ])
            FilledButton.tonalIcon(
              onPressed: action(key),
              icon: Icon(
                homeModuleKeys.contains(key)
                    ? moduleIcon(key)
                    : Icons.folder_outlined,
              ),
              label: Text(widget.strings.text(key)),
            ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 28 ? 112 : 56,
      backgroundColor: accountCanvas(context, AppColors.background),
      title: const Text(
        'BookStark',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      ),
      actions: [
        if (widget.local)
          IconButton(
            tooltip: t('本地备份与迁移', 'Local backup and migration'),
            onPressed: action('local-backup'),
            icon: const Icon(Icons.backup_outlined),
          ),
        IconButton(
          tooltip: t('语言', 'Language'),
          onPressed: widget.onLanguage,
          icon: const Icon(Icons.translate),
        ),
        IconButton(
          tooltip: widget.strings.text('me'),
          onPressed: action('profile'),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async {
        await state.load();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              _box(
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    widget.local ? Icons.folder_outlined : Icons.cloud_outlined,
                  ),
                  title: Text(
                    widget.strings.text(
                      widget.local ? 'localSpace' : 'serverSpace',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: action('space'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: action('settings'),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(t('设置', 'Settings')),
                ),
              ),
              Text(
                t('你的知识首页', 'Your knowledge home'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t('最近内容与访问记录', 'Recent content and visits'),
                style: const TextStyle(color: AppColors.secondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: action('search'),
                    icon: const Icon(Icons.search),
                    label: Text(widget.strings.text('search')),
                  ),
                  OutlinedButton.icon(
                    onPressed: locked || state.snapshot == null
                        ? null
                        : _customize,
                    icon: const Icon(Icons.tune),
                    label: Text(t('自定义', 'Customize')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.loading) const LinearProgressIndicator(),
              if (state.problem != null) _notice(),
              const SizedBox(height: 12),
              _filters(),
              _recent(),
              if (ready) _sections(),
              const SizedBox(height: 12),
              Text(
                widget.strings.text('shortcuts'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _shortcuts(),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: action('assistant'),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(widget.strings.text('assistant')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) => action(
        ['home', 'notes', 'bookmarks', 'files', 'profile'][index],
      )?.call(),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: widget.strings.text('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.menu_book_outlined),
          label: widget.strings.text('knowledge'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.star_outline),
          label: widget.strings.text('favorites'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.folder_outlined),
          label: widget.strings.text('files'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          label: widget.strings.text('me'),
        ),
      ],
    ),
  );
}
