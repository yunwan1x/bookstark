import 'package:flutter/material.dart';
import 'admin_community_controller.dart';
import 'admin_community_strings.dart';
import 'admin_community_widgets.dart';
import 'admin_friend_links_models.dart';
import 'admin_settings_widgets.dart';

class AdminFriendLinkCard extends StatelessWidget {
  const AdminFriendLinkCard({
    super.key,
    required this.link,
    required this.strings,
    this.onEdit,
    this.onEnabled,
    this.detailed = true,
  });
  final AdminFriendLink link;
  final bool detailed;
  final AdminCommunityStrings strings;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onEnabled;
  Widget line(String title, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xffeff2f7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(title),
        ),
        SelectableText(value),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffd6deeb)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  link.name,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (onEdit != null)
                  FilledButton.tonalIcon(
                    onPressed: onEdit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffe6f0ff),
                      foregroundColor: const Color(0xff15376b),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      s.t('编辑', 'Edit'),
                      semanticsLabel: s.t(
                        '编辑 ${link.name}',
                        'Edit ${link.name}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (link.url.isNotEmpty)
            SelectableText(
              link.url,
              style: const TextStyle(color: Color(0xff536482)),
            ),
          if (link.qr.isNotEmpty) line(s.t('二维码', 'QR image'), link.qr),
          line(
            s.t('分组', 'Group'),
            link.group.isEmpty ? s.t('未分组', 'Ungrouped') : link.group,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(s.t('启用', 'Enabled')),
                if (onEnabled != null)
                  Semantics(
                    label: s.t('启用 ${link.name}', 'Enable ${link.name}'),
                    child: Switch(value: link.enabled, onChanged: onEnabled),
                  )
                else
                  Text(
                    link.enabled
                        ? s.t('已启用', 'Enabled')
                        : s.t('未启用', 'Disabled'),
                  ),
              ],
            ),
          ),
          if (detailed) line(s.t('分组顺序', 'Group order'), '${link.groupOrder}'),
          line(s.t('排序', 'Order'), '${link.weight}'),
          if (detailed && link.description.isNotEmpty)
            line(s.t('描述', 'Description'), link.description),
        ],
      ),
    );
  }
}

class AdminFriendLinksPage extends StatelessWidget {
  const AdminFriendLinksPage({
    super.key,
    required this.controller,
    required this.strings,
    required this.onReturn,
    required this.onAdd,
    required this.onSave,
    required this.onReload,
    required this.onEdit,
    required this.onReadCurrent,
    required this.onAdoptCurrent,
  });
  final AdminFriendLinksController controller;
  final AdminCommunityStrings strings;
  final VoidCallback onReturn,
      onAdd,
      onSave,
      onReload,
      onReadCurrent,
      onAdoptCurrent;
  final ValueChanged<AdminFriendLinkDraftRow> onEdit;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, s = strings;
      final reviewing = c.reviewing && c.currentReview != null;
      final visible = reviewing ? c.currentReview! : c.draft;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: s.t('友情链接', 'Friend links'),
          subtitle: s.t('页脚配置 · 管理员', 'Footer configuration · Administrator'),
          dirty: c.ready && c.dirty,
          onReturn: onReturn,
          backLabel: s.t('返回', 'Back'),
          dirtyLabel: s.t('未保存', 'Unsaved'),
          actions: [
            IconButton(
              tooltip: s.t('新增友情链接', 'Add friend link'),
              onPressed: c.ready && c.rows.length < 200 ? onAdd : null,
              icon: const Icon(Icons.add, color: Color(0xff132b52)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (c.busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    AdminCommunityNoticeCard(controller: c, strings: s),
                    if (c.pending) ...[
                      if (c.pendingDraft != null)
                        Text(
                          s.t(
                            '本次草稿 ${c.pendingDraft!.items.length} 条（只读）',
                            'Operation draft: ${c.pendingDraft!.items.length} items (read only)',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : onReadCurrent,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          s.t('只读取当前配置', 'Read current configuration only'),
                        ),
                      ),
                      if (reviewing) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: onAdoptCurrent,
                          child: Text(
                            s.t(
                              '采用当前配置并结束核对',
                              'Adopt current configuration and finish review',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (c.pendingDraft != null)
                          ExpansionTile(
                            key: const ValueKey('friend-links-original-draft'),
                            title: Text(
                              s.t(
                                '查看原本地草稿（只读）',
                                'View earlier local draft (read only)',
                              ),
                            ),
                            children: [
                              for (final link in c.pendingDraft!.items)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: AdminFriendLinkCard(
                                    link: link,
                                    strings: s,
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Text(
                          s.t('服务器当前配置', 'Current server configuration'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ] else if (c.phase == AdminCommunityPhase.needsReload) ...[
                      OutlinedButton.icon(
                        onPressed: onReload,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          c.dirty
                              ? s.t(
                                  '重新读取（放弃本地草稿）',
                                  'Reload and discard local draft',
                                )
                              : s.t('重新读取', 'Reload'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (c.baseline != null)
                        Text(
                          s.t('上次本地草稿（只读）', 'Earlier local draft (read only)'),
                        ),
                    ],
                    if (c.baseline != null || reviewing) ...[
                      Container(
                        key: const ValueKey('friend-links-simple-mode'),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xfff1f4f9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.t('简洁模式', 'Simple mode'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Semantics(
                              label: s.t('简洁模式', 'Simple mode'),
                              child: Switch(
                                value: visible.simpleMode,
                                onChanged: c.ready ? c.setSimpleMode : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (c.ready)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xff64748b),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.t(
                                  '本页修改将在保存时整体替换友情链接。',
                                  'Saving replaces the complete friend link list.',
                                ),
                                style: const TextStyle(
                                  color: Color(0xff64748b),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        AdminCommunityInfo(
                          text: s.t(
                            '这里只读展示核对资料，不会自动再次提交。',
                            'These details are read only. No earlier request is replayed.',
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (!c.ready) ...[
                        Text(
                          s.linksCount(visible.items.length),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (c.ready && c.rows.length >= 200) ...[
                        Text(
                          s.t(
                            '已达200条上限，请编辑或移除现有草稿。',
                            'The 200-entry limit is reached. Edit or remove an existing draft entry.',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (c.ready)
                        for (final row in c.rows)
                          AdminFriendLinkCard(
                            key: ValueKey('friend-draft-${row.key}'),
                            link: row.link,
                            strings: s,
                            detailed: false,
                            onEdit: () => onEdit(row),
                            onEnabled: (enabled) => c.applyRow(
                              row.key,
                              row.link.edit(enabled: enabled),
                              expectedRevision: c.revision,
                            ),
                          )
                      else
                        for (final link in visible.items)
                          AdminFriendLinkCard(link: link, strings: s),
                    ],
                  ],
                ),
              ),
              if (c.ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: c.dirty ? onSave : null,
                      child: Text(s.t('保存全部', 'Save all')),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
