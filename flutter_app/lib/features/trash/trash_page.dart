import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/trash_repository.dart';
import '../../core/trash_controller.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({
    super.key,
    required this.repository,
    this.english = false,
    this.local = false,
  });
  final TrashRepository repository;
  final bool english, local;
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  late final c = TrashController(widget.repository);
  bool _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  String label(String type) => switch (type) {
    'book' => t('书籍', 'Books'),
    'blog' => t('笔记与文章', 'Notes and articles'),
    'bookmark' => t('书签', 'Bookmarks'),
    'document' => t('文档', 'Documents'),
    'task' => t('待办', 'Tasks'),
    'topic' => t('专题', 'Topics'),
    _ => t('全部', 'All'),
  };
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.load();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  Future<bool> _confirm(
    List<TrashEntry> entries,
    TrashOperation operation,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  operation == TrashOperation.delete
                      ? t(
                          '永久删除这${entries.length}项？',
                          'Permanently delete these ${entries.length} items?',
                        )
                      : t(
                          '还原这${entries.length}项？',
                          'Restore these ${entries.length} items?',
                        ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${entry.name}\n${label(entry.type)} · #${entry.id}',
                    ),
                  ),
                Text(
                  operation == TrashOperation.delete
                      ? t(
                          '无法撤销，请核对所选项目。',
                          'This cannot be undone. Check the selected items.',
                        )
                      : t(
                          '项目可能因名称冲突或依赖缺失而无法还原。',
                          'Name conflicts or missing dependencies may prevent restoration.',
                        ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('取消', 'Cancel')),
                    ),
                    TextButton(
                      style: operation == TrashOperation.delete
                          ? TextButton.styleFrom(foregroundColor: Colors.red)
                          : null,
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        operation == TrashOperation.delete
                            ? t('确认永久删除', 'Confirm permanent deletion')
                            : t('确认还原', 'Confirm restoration'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
  Future<void> _apply(
    List<TrashEntry> entries,
    TrashOperation operation,
  ) async {
    if (entries.isEmpty || c.busy || c.unresolved) {
      return;
    }
    final exact = List<TrashEntry>.unmodifiable(entries);
    if (await _confirm(exact, operation) && mounted) {
      await c.apply(exact, operation);
    }
  }

  Future<void> _leave() async {
    if (c.busy || _leaving) {
      return;
    }
    if (c.unresolved) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('离开回收站？', 'Leave trash?')),
          content: Text(
            t(
              '仍有未确认的操作。离开不会撤销服务器修改；再次进入后请刷新核对。',
              'Some results are unverified. Leaving does not undo server changes. Refresh when returning.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('离开', 'Leave')),
            ),
          ],
        ),
      );
      if (accepted != true) {
        return;
      }
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  String resultText(TrashItemResult result) => switch (result.phase) {
    TrashItemPhase.acknowledgedRemoved =>
      result.operation == TrashOperation.restore
          ? t(
              '还原回执已收到，回收站记录已移出。',
              'Restore acknowledged; the trash record is absent.',
            )
          : t(
              '删除回执已收到，回收站记录已移出。',
              'Deletion acknowledged; the trash record is absent.',
            ),
    TrashItemPhase.absentWithoutReceipt => t(
      '记录已移出；上次操作回执仍未知。',
      'The record is absent; the earlier receipt remains unknown.',
    ),
    TrashItemPhase.failed => t(
      '操作未完成，保留选择，请核对依赖与权限。',
      'Operation incomplete. Selection retained; check dependencies and permissions.',
    ),
    TrashItemPhase.unverified => t(
      '已收到回执，实际记录尚未核对。',
      'Receipt received; actual record is unverified.',
    ),
    TrashItemPhase.unknown => t(
      '结果未知，不会自动重发。',
      'Result unknown. It will not be resent.',
    ),
  };
  Widget card(List<Widget> children) => Card(
    semanticContainer: false,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  String deletedTime(String raw) {
    final value = DateTime.tryParse(raw)?.toLocal();
    if (value == null) {
      return raw;
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  IconData typeIcon(String type) => switch (type) {
    'book' => Icons.menu_book_outlined,
    'blog' => Icons.edit_note_outlined,
    'bookmark' => Icons.bookmark_outline,
    'document' => Icons.description_outlined,
    'task' => Icons.check_box_outlined,
    'topic' => Icons.hub_outlined,
    _ => Icons.delete_outline,
  };
  bool get largeText =>
      MediaQuery.textScalerOf(context).scale(14) > 21 ||
      MediaQuery.sizeOf(context).width < 360;
  List<Widget> metadata(TrashEntry entry) => [
    Text('${label(entry.type)} · #${entry.id}'),
    Text(
      entry.deletedAt.isEmpty
          ? t('删除时间未记录', 'Deletion time was not recorded')
          : '${t('删除时间（本机）', 'Deleted (local)')}: ${deletedTime(entry.deletedAt)}',
    ),
    if (entry.resourceUrl.isNotEmpty) Text(entry.resourceUrl),
  ];
  Widget row(TrashEntry entry) => card([
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          semanticLabel: t('选择${entry.name}', 'Select ${entry.name}'),
          value: c.selected.containsKey(entry.id),
          onChanged: c.busy || c.unresolved ? null : (_) => c.toggle(entry),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xffe7efff),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                typeIcon(entry.type),
                color: const Color(0xff0b4eff),
                size: 22,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (!largeText) ...metadata(entry),
            ],
          ),
        ),
      ],
    ),
    if (largeText) ...[const SizedBox(height: 8), ...metadata(entry)],
    const SizedBox(height: 12),
    Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: c.busy || c.unresolved
              ? null
              : () => _apply([entry], TrashOperation.restore),
          child: Text(t('还原', 'Restore')),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: c.busy || c.unresolved
              ? null
              : () => _apply([entry], TrashOperation.delete),
          child: Text(t('永久删除', 'Delete permanently')),
        ),
      ],
    ),
  ]);
  @override
  Widget build(BuildContext context) {
    final data = c.data;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('回收站', 'Trash')),
          actions: [
            IconButton(
              tooltip: t('刷新', 'Refresh'),
              onPressed: c.busy ? null : () => c.load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.local
                      ? t('本机数据', 'On this device')
                      : t(
                          '当前服务器账户 · 仅显示自己的项目',
                          'Current server account · Your items only',
                        ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in ['', ...trashTypes])
                      ChoiceChip(
                        label: Text(label(type)),
                        selected: c.type == type,
                        showCheckmark: false,
                        selectedColor: const Color(0xff0b4eff),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: c.type == type
                              ? Colors.white
                              : const Color(0xff334155),
                        ),
                        onSelected:
                            c.busy || c.selected.isNotEmpty || c.unresolved
                            ? null
                            : (_) => c.load(filter: type),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (c.busy) const LinearProgressIndicator(),
                if (c.readFailed)
                  card([
                    Text(
                      t(
                        '未能读取回收站，请刷新重试。',
                        'Could not read trash. Refresh to retry.',
                      ),
                    ),
                  ]),
                if (c.results.isNotEmpty)
                  card([
                    for (final result in c.results.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${result.entry.name}\n${resultText(result)}',
                        ),
                      ),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.busy ? null : c.verify,
                        child: Text(
                          t(
                            '只读核对未确认结果',
                            'Verify unconfirmed results without writing',
                          ),
                        ),
                      ),
                  ]),
                if (c.selected.isNotEmpty)
                  card([
                    Text(
                      t(
                        '已选${c.selected.length}项',
                        '${c.selected.length} selected',
                      ),
                    ),
                    for (final entry in c.selected.values.where(
                      (v) =>
                          !(data?.entries.any((row) => row.id == v.id) ??
                              false),
                    ))
                      Text(
                        '${entry.name} · ${t('不在当前页，仍保留选择', 'Off this page; selection retained')}',
                      ),
                    TextButton(
                      onPressed: c.busy || c.unresolved
                          ? null
                          : c.clearSelection,
                      child: Text(t('清空选择', 'Clear selection')),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: c.busy || c.unresolved
                              ? null
                              : () => _apply(
                                  c.selected.values.toList(),
                                  TrashOperation.restore,
                                ),
                          child: Text(t('还原所选', 'Restore selected')),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: c.busy || c.unresolved
                              ? null
                              : () => _apply(
                                  c.selected.values.toList(),
                                  TrashOperation.delete,
                                ),
                          child: Text(
                            t('永久删除所选', 'Delete selected permanently'),
                          ),
                        ),
                      ],
                    ),
                  ]),
                if (data != null) ...[
                  Text(t('共${data.total}条', '${data.total} items')),
                  const SizedBox(height: 12),
                  if (data.entries.isEmpty)
                    card([
                      Text(t('当前页没有回收站项目。', 'No trash items on this page.')),
                    ]),
                  for (final entry in data.entries) row(entry),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: c.busy || data.page <= 1
                            ? null
                            : () => c.load(page: data.page - 1),
                        child: Text(t('上一页', 'Previous page')),
                      ),
                      Text(
                        t(
                          '第${data.page}页 / 共${data.pages}页',
                          'Page ${data.page} of ${data.pages}',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: c.busy || data.page >= data.pages
                            ? null
                            : () => c.load(page: data.page + 1),
                        child: Text(t('下一页', 'Next page')),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: c.busy || c.unresolved || data.entries.isEmpty
                        ? null
                        : c.selectPage,
                    child: Text(t('选择当前页', 'Select current page')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
