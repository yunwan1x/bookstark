import 'package:flutter/material.dart';
import 'admin_comment_models.dart';
import 'admin_community_controller.dart';
import 'admin_community_strings.dart';
import 'admin_community_widgets.dart';
import 'admin_settings_widgets.dart';

class AdminShareCommentCard extends StatelessWidget {
  const AdminShareCommentCard({
    super.key,
    required this.comment,
    required this.strings,
    this.selected = false,
    this.onSelected,
  });
  final AdminCommentRecord comment;
  final AdminCommunityStrings strings;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) {
    final s = strings, row = comment;
    final visible = row.status == AdminCommentStatus.visible;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffd6deeb)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onSelected != null) ...[
            Semantics(
              label: s.t('选择评论 ID ${row.id}', 'Select comment ID ${row.id}'),
              child: Checkbox(
                value: selected,
                onChanged: (value) => onSelected!(value ?? false),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      row.author.isEmpty
                          ? s.t('未提供作者', 'Author not provided')
                          : row.author,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: visible
                            ? const Color(0xffddf8e7)
                            : const Color(0xffffe7e9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.status(row.status),
                        style: TextStyle(
                          color: visible
                              ? const Color(0xff1a683e)
                              : const Color(0xffb3293b),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${s.target(row.target)} · ${row.shareIdentify.isEmpty ? 'ID ${row.targetId}' : row.shareIdentify}',
                  style: const TextStyle(color: Color(0xff64748b)),
                ),
                const SizedBox(height: 14),
                SelectableText(row.content),
                if (row.parentId > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    row.replyToAuthor.isEmpty
                        ? s.t(
                            '回复评论 ID ${row.replyToId}',
                            'Reply to comment ID ${row.replyToId}',
                          )
                        : s.t(
                            '回复 ${row.replyToAuthor}',
                            'Reply to ${row.replyToAuthor}',
                          ),
                    style: const TextStyle(color: Color(0xff64748b)),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  s.t(
                    '创建时间：${s.date(row.created)}',
                    'Created: ${s.date(row.created)}',
                  ),
                  style: const TextStyle(color: Color(0xff64748b)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminShareCommentsPage extends StatefulWidget {
  const AdminShareCommentsPage({
    super.key,
    required this.controller,
    required this.strings,
    required this.onReturn,
    required this.onDelete,
    required this.onReadCurrent,
    required this.onFinishReview,
  });
  final AdminCommentsController controller;
  final AdminCommunityStrings strings;
  final VoidCallback onReturn, onDelete, onReadCurrent, onFinishReview;
  @override
  State<AdminShareCommentsPage> createState() => _AdminShareCommentsPageState();
}

class _AdminShareCommentsPageState extends State<AdminShareCommentsPage> {
  final _query = TextEditingController();
  AdminCommentsController get c => widget.controller;
  AdminCommunityStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    _query.text = c.filter.keyword;
    c.addListener(_changed);
  }

  void _changed() {
    if (c.phase == AdminCommunityPhase.permissionLost) {
      _query.clear();
    }
  }

  @override
  void didUpdateWidget(covariant AdminShareCommentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      _query.clear();
      _query.text = c.filter.keyword;
      c.addListener(_changed);
    }
  }

  void _search() {
    if (!c.ready) return;
    FocusScope.of(context).unfocus();
    c.load(
      filter: AdminCommentFilter(
        keyword: _query.text,
        status: c.filter.status,
        target: c.filter.target,
      ),
    );
  }

  Widget _choice(
    String id,
    String value,
    Map<String, String> options,
    ValueChanged<String> changed,
  ) {
    final fieldLabel = id == 'status'
        ? s.t('评论状态', 'Comment status')
        : s.t('评论类型', 'Comment target type');
    return DropdownButtonFormField<String>(
      key: ValueKey(('comment-filter', id, value)),
      initialValue: value,
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xfff8faff),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      selectedItemBuilder: (context) => [
        for (final item in options.entries)
          Text(item.value, semanticsLabel: '$fieldLabel\n${item.value}'),
      ],
      items: [
        for (final item in options.entries)
          DropdownMenuItem(value: item.key, child: Text(item.value)),
      ],
      onChanged: c.ready
          ? (value) {
              if (value != null) {
                changed(value);
              }
            }
          : null,
    );
  }

  Widget _filters() => LayoutBuilder(
    builder: (context, box) {
      final status = _choice(
        'status',
        c.filter.status?.value ?? '',
        {
          '': s.t('全部状态', 'All statuses'),
          'visible': s.t('可见', 'Visible'),
          'deleted': s.t('已删除', 'Deleted'),
        },
        (value) => c.load(
          filter: AdminCommentFilter(
            keyword: c.filter.keyword,
            status: value.isEmpty ? null : AdminCommentStatus.parse(value),
            target: c.filter.target,
          ),
        ),
      );
      final target = _choice(
        'target',
        c.filter.target?.value ?? '',
        {
          '': s.t('全部类型', 'All types'),
          'blog': s.t('博客', 'Blog'),
          'book': s.t('书籍', 'Book'),
          'document': s.t('文档', 'Document'),
        },
        (value) => c.load(
          filter: AdminCommentFilter(
            keyword: c.filter.keyword,
            status: c.filter.status,
            target: value.isEmpty ? null : AdminCommentTarget.parse(value),
          ),
        ),
      );
      if (box.maxWidth < 330 ||
          MediaQuery.textScalerOf(context).scale(16) > 24) {
        return Column(children: [status, const SizedBox(height: 12), target]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: status),
          const SizedBox(width: 12),
          Expanded(child: target),
        ],
      );
    },
  );
  @override
  void dispose() {
    c.removeListener(_changed);
    _query.clear();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final data = c.reviewing ? c.currentReview : c.page;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: s.t('评论管理', 'Comment management'),
          dirty: false,
          onReturn: widget.onReturn,
          backLabel: s.t('返回', 'Back'),
          dirtyLabel: s.t('未保存', 'Unsaved'),
          actions: [
            IconButton(
              tooltip: s.t('刷新评论', 'Refresh comments'),
              onPressed: c.ready ? () => c.load(page: c.page?.page ?? 1) : null,
              icon: const Icon(Icons.refresh, color: Color(0xff132b52)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  key: ValueKey((
                    'comment-list',
                    data?.page,
                    c.filter.keyword,
                    c.filter.status,
                    c.filter.target,
                    c.pendingKind,
                    c.reviewing,
                  )),
                  children: [
                    if (c.busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    AdminCommunityNoticeCard(controller: c, strings: s),
                    TextField(
                      key: const ValueKey('comment-keyword'),
                      controller: _query,
                      enabled: c.ready,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: s.t(
                          '搜索内容、作者或分享标识',
                          'Search content, author or share ID',
                        ),
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0xfff3f5f9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_query.text.isNotEmpty)
                              IconButton(
                                tooltip: s.t('清空搜索', 'Clear search'),
                                onPressed: c.ready
                                    ? () {
                                        _query.clear();
                                        _search();
                                      }
                                    : null,
                                icon: const Icon(Icons.clear),
                              ),
                            IconButton(
                              tooltip: s.t('搜索评论', 'Search comments'),
                              onPressed: c.ready ? _search : null,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_query.text != c.filter.keyword)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          s.t(
                            '关键词尚未应用，点击搜索。',
                            'The keyword is not applied yet. Submit the search.',
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _filters(),
                    const SizedBox(height: 16),
                    if (c.pending) ...[
                      if (c.pendingKind == AdminCommunityPendingKind.known &&
                          c.actualDeleted != null) ...[
                        AdminCommunityInfo(
                          text: s.t(
                            '服务器确认实际删除 ${c.actualDeleted} 条，列表回读尚未完成。',
                            'The server reported ${c.actualDeleted} deletions. List readback has not finished.',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        s.t('本次操作目标（只读）', 'Operation targets (read only)'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      for (final target in c.pendingTargets)
                        AdminShareCommentCard(comment: target, strings: s),
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : widget.onReadCurrent,
                        icon: const Icon(Icons.refresh),
                        label: Text(s.t('只读取当前列表', 'Read current list only')),
                      ),
                      if (c.reviewing) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: widget.onFinishReview,
                          child: Text(s.t('已核对，结束本次核对', 'Finish this review')),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.t('当前列表（只读）', 'Current list (read only)'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ] else if (c.phase == AdminCommunityPhase.needsReload) ...[
                      OutlinedButton.icon(
                        onPressed: () => c.load(),
                        icon: const Icon(Icons.refresh),
                        label: Text(s.t('重新读取', 'Reload')),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (c.pageAdjusted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AdminCommunityInfo(
                          text: s.t(
                            '列表页数已变化，已重新读取有效页。',
                            'The page count changed. A valid page was reloaded.',
                          ),
                        ),
                      ),
                    if (data != null) ...[
                      Text(
                        s.t('共 ${data.total} 条评论', '${data.total} comments'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      for (final row in data.items)
                        AdminShareCommentCard(
                          key: ValueKey('comment-${row.id}'),
                          comment: row,
                          strings: s,
                          selected: c.selected.contains(row.id),
                          onSelected: c.ready
                              ? (value) => c.select(row.id, value)
                              : null,
                        ),
                    ],
                    AdminCommunityInfo(
                      tone: AdminCommunityTone.warning,
                      text: s.t(
                        '删除主评论会同时删除其回复。',
                        'Deleting a root comment also deletes its replies.',
                      ),
                    ),
                  ],
                ),
              ),
              if (c.ready && c.page != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final count = Text(
                            s.selectedCount(c.selected.length),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                          final remove = FilledButton(
                            onPressed: c.selected.isEmpty
                                ? null
                                : widget.onDelete,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xffd72837),
                            ),
                            child: Text(s.t('永久删除', 'Delete permanently')),
                          );
                          if (box.maxWidth < 330 ||
                              MediaQuery.textScalerOf(context).scale(16) > 24) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                count,
                                const SizedBox(height: 8),
                                remove,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: count),
                              const SizedBox(width: 12),
                              remove,
                            ],
                          );
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(),
                      ),
                      AdminCommunityPager(
                        page: c.page!.page,
                        totalPages: c.page!.totalPages,
                        strings: s,
                        onPrevious: c.page!.page > 1
                            ? () => c.load(page: c.page!.page - 1)
                            : null,
                        onNext: c.page!.page < c.page!.totalPages
                            ? () => c.load(page: c.page!.page + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
