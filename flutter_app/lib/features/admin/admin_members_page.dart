import 'package:flutter/material.dart';
import 'admin_members_controller.dart';
import 'admin_members_models.dart';
import 'admin_members_strings.dart';
import 'admin_members_widgets.dart';
import 'admin_settings_widgets.dart';

class AdminMembersPage extends StatelessWidget {
  const AdminMembersPage({
    super.key,
    required this.controller,
    required this.strings,
    required this.onReturn,
    required this.onSelect,
  });
  final AdminMembersController controller;
  final AdminMembersStrings strings;
  final VoidCallback onReturn;
  final ValueChanged<int> onSelect;
  Widget _member(AdminMemberRecord member) {
    final self = member.id == controller.owner.memberId;
    final trimmed = member.account.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Padding(
      key: ValueKey('member-card-${member.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xffedf5ff), Color(0xffe4f0ff)],
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: controller.ready ? () => onSelect(member.id) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xff1555ef),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.account,
                              softWrap: true,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Color(0xff0e1b3d),
                              ),
                            ),
                            if (self) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xff1555ef),
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  strings.t('当前账户', 'Current account'),
                                  style: const TextStyle(
                                    color: Color(0xff1555ef),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 5),
                            Text(
                              'ID ${member.id} · ${strings.role(member.role)}',
                              style: const TextStyle(color: Color(0xff586882)),
                            ),
                            const SizedBox(height: 8),
                            AdminMemberStatusBadge(
                              status: member.status,
                              strings: strings,
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 28, left: 4),
                        child: Icon(
                          Icons.chevron_right,
                          color: Color(0xff586882),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  Text(
                    strings.t(
                      '注册于 ${strings.date(member.created)}',
                      'Registered ${strings.date(member.created)}',
                    ),
                    style: const TextStyle(color: Color(0xff586882)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager(BuildContext context, AdminMemberPage page) {
    final previous = OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      onPressed: controller.ready && page.hasPrevious
          ? () => controller.load(page.page - 1)
          : null,
      child: Text(strings.t('上一页', 'Previous')),
    );
    final next = OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      onPressed: controller.ready && page.hasNext
          ? () => controller.load(page.page + 1)
          : null,
      child: Text(strings.t('下一页', 'Next')),
    );
    final label = Text(
      strings.page(page.page, page.totalPages),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: MediaQuery.textScalerOf(context).scale(16) > 24
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                const SizedBox(height: 8),
                previous,
                const SizedBox(height: 8),
                next,
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [previous, label, next],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final page = controller.page;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: adminSettingsAppBar(
          context,
          title: strings.t('用户管理', 'User management'),
          subtitle: strings.t('管理员 · 服务器空间', 'Administrator · Server space'),
          dirty: false,
          onReturn: onReturn,
          backLabel: strings.t('返回', 'Back'),
          dirtyLabel: strings.t('未保存', 'Unsaved'),
          actions: [
            IconButton(
              tooltip: strings.t('刷新用户列表', 'Refresh members'),
              onPressed: controller.ready ? () => controller.load() : null,
              icon: const Icon(Icons.refresh, color: Color(0xff1555ef)),
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
                    if (controller.phase == AdminMembersPhase.loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    AdminMemberNoticeCard(
                      controller: controller,
                      strings: strings,
                    ),
                    if (controller.phase == AdminMembersPhase.needsReload)
                      OutlinedButton.icon(
                        onPressed: () => controller.load(),
                        icon: const Icon(Icons.refresh),
                        label: Text(strings.t('重新读取列表', 'Reload members')),
                      ),
                    if (page != null) ...[
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text(
                            strings.count(page.total),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(strings.t('每页 20 人', '20 per page')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (page.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            strings.t(
                              '当前页没有用户。',
                              'There are no members on this page.',
                            ),
                          ),
                        ),
                      for (final member in page.items) _member(member),
                      const SizedBox(height: 4),
                      AdminMemberInfo(
                        text: strings.t(
                          '点击用户查看审批与权限操作',
                          'Select a member to review approval and permissions',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (page != null) _pager(context, page),
            ],
          ),
        ),
      );
    },
  );
}

class AdminMemberDetailPage extends StatelessWidget {
  const AdminMemberDetailPage({
    super.key,
    required this.controller,
    required this.member,
    required this.strings,
    required this.onReturn,
    required this.onApproval,
    required this.onRole,
    required this.onPassword,
    required this.onReviewed,
    this.confirming = false,
  });
  final AdminMembersController controller;
  final AdminMemberRecord member;
  final AdminMembersStrings strings;
  final VoidCallback onReturn, onApproval, onRole, onPassword, onReviewed;
  final bool confirming;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final operation = {
        AdminMembersPhase.unknown,
        AdminMembersPhase.reviewingUnknown,
        AdminMembersPhase.readingCurrent,
        AdminMembersPhase.knownNeedsRead,
      }.contains(controller.phase);
      return Scaffold(
        backgroundColor: const Color(0xfff8faff),
        appBar: adminSettingsAppBar(
          context,
          title: strings.t('用户详情', 'Member details'),
          dirty: false,
          onReturn: onReturn,
          backLabel: strings.t('返回', 'Back'),
          dirtyLabel: strings.t('未保存', 'Unsaved'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (operation)
                AdminMemberOperationPanel(
                  controller: controller,
                  strings: strings,
                  onReviewed: onReviewed,
                )
              else ...[
                Text(
                  strings.t(
                    '当前列表可用资料。',
                    'Details available from the current list.',
                  ),
                  style: const TextStyle(color: Color(0xff586882)),
                ),
                const SizedBox(height: 16),
                AdminMemberNoticeCard(controller: controller, strings: strings),
                AdminMemberIdentityCard(
                  member: member,
                  strings: strings,
                  current: member.id == controller.owner.memberId,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed:
                      controller.ready &&
                          !confirming &&
                          member.status == AdminMemberStatus.pending
                      ? onApproval
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(strings.t('审批处理', 'Review approval')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.ready && !confirming ? onRole : null,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: Text(strings.t('修改角色', 'Change role')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      controller.ready &&
                          !confirming &&
                          member.status == AdminMemberStatus.approved
                      ? onPassword
                      : null,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(strings.t('重置密码', 'Reset password')),
                ),
                if (controller.phase == AdminMembersPhase.submitting)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 24),
                Text(
                  strings.t(
                    '资料来自当前列表，操作前重新核对。时间使用当前设备时区。',
                    'Details come from the current list and are checked again before an operation. Times use this device’s time zone.',
                  ),
                  style: const TextStyle(color: Color(0xff586882)),
                ),
                if (member.status != AdminMemberStatus.pending) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.t(
                      '仅待审批用户提供审批处理。',
                      'Approval actions are available for pending members.',
                    ),
                  ),
                ],
                if (member.status != AdminMemberStatus.approved) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.t(
                      '未通过审批的用户不能重置密码。',
                      'Password reset requires an approved member.',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
