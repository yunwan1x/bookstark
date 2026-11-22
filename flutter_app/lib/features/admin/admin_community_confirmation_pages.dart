import 'package:flutter/material.dart';
import 'admin_comment_models.dart';
import 'admin_community_strings.dart';
import 'admin_community_widgets.dart';
import 'admin_friend_links_models.dart';
import 'admin_share_comments_page.dart';
import 'admin_settings_widgets.dart';

class AdminFriendLinksSavePage extends StatelessWidget {
  const AdminFriendLinksSavePage({
    super.key,
    required this.draft,
    required this.strings,
    required this.onReturn,
    required this.onConfirm,
    required this.enabled,
    required this.busy,
  });
  final AdminFriendLinksSnapshot draft;
  final AdminCommunityStrings strings;
  final VoidCallback onReturn, onConfirm;
  final bool enabled, busy;
  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: adminSettingsAppBar(
        context,
        title: s.t('保存全部友情链接', 'Save all friend links'),
        dirty: false,
        onReturn: onReturn,
        backLabel: s.t('返回', 'Back'),
        dirtyLabel: s.t('未保存', 'Unsaved'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminCommunityInfo(
              text: s.t(
                '将整体替换服务器当前链接，其他管理员的并发修改可能被覆盖。',
                'This replaces the entire server list. Concurrent changes by other administrators may be overwritten.',
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xffd6deeb)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    s.t('当前草稿', 'Current draft'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    s.linksCount(draft.items.length),
                    style: const TextStyle(
                      color: Color(0xff1555ef),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (draft.items.isEmpty) ...[
              AdminCommunityInfo(
                tone: AdminCommunityTone.warning,
                text: s.t(
                  '将清空全部友情链接。确认后无法在本页恢复原列表。',
                  'This clears all friend links. The earlier list cannot be restored from this page after confirmation.',
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (!enabled && !busy) ...[
              AdminCommunityInfo(
                tone: AdminCommunityTone.warning,
                text: s.t(
                  '草稿已变化，请返回重新核对。',
                  'The draft changed. Return and review it again.',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (busy) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: enabled && !busy ? onConfirm : null,
              child: Text(
                busy
                    ? s.t('正在保存…', 'Saving…')
                    : s.t('确认保存全部', 'Confirm save all'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : onReturn,
              child: Text(s.t('返回核对', 'Return to review')),
            ),
            const SizedBox(height: 24),
            AdminCommunityInfo(
              tone: AdminCommunityTone.warning,
              text: s.t(
                '清空列表也必须明确确认。',
                'Clearing the list also requires explicit confirmation.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminCommentDeletePage extends StatelessWidget {
  const AdminCommentDeletePage({
    super.key,
    required this.targets,
    required this.strings,
    required this.onReturn,
    required this.onConfirm,
    required this.enabled,
    required this.busy,
  });
  final List<AdminCommentRecord> targets;
  final AdminCommunityStrings strings;
  final VoidCallback onReturn, onConfirm;
  final bool enabled, busy;
  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: adminSettingsAppBar(
        context,
        title: s.t('永久删除评论', 'Permanently delete comments'),
        dirty: false,
        onReturn: onReturn,
        backLabel: s.t('返回', 'Back'),
        dirtyLabel: s.t('未保存', 'Unsaved'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminCommunityInfo(
              tone: AdminCommunityTone.danger,
              text: s.t(
                '已选择 ${targets.length} 条评论。删除主评论会同时删除关联回复，实际删除数量可能更多，删除后无法恢复。',
                '${targets.length} comments selected. Deleting a root comment also deletes its replies, so more rows may be affected. This cannot be undone.',
              ),
            ),
            const SizedBox(height: 20),
            for (final row in targets)
              AdminShareCommentCard(comment: row, strings: s),
            if (!enabled && !busy) ...[
              AdminCommunityInfo(
                tone: AdminCommunityTone.warning,
                text: s.t(
                  '选择或列表已变化，请返回重新核对。',
                  'The selection or list changed. Return and review again.',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (busy) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: enabled && !busy ? onConfirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffd72837),
              ),
              child: Text(
                busy
                    ? s.t('正在删除…', 'Deleting…')
                    : s.t('确认永久删除', 'Confirm permanent deletion'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : onReturn,
              child: Text(s.t('取消', 'Cancel')),
            ),
            const SizedBox(height: 24),
            AdminCommunityInfo(
              text: s.t(
                '请求结果未知时，先重新读取列表，不自动重复删除。',
                'If the result is unknown, read the list first. The deletion will not be replayed automatically.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
