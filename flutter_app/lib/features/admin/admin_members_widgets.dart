import 'package:flutter/material.dart';
import 'admin_members_controller.dart';
import 'admin_members_models.dart';
import 'admin_members_repository.dart';
import 'admin_members_strings.dart';

class AdminMemberInfo extends StatelessWidget {
  const AdminMemberInfo({super.key, required this.text, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff4d9) : const Color(0xffedf4ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.warning_amber_rounded : Icons.info_outline,
          color: warning ? const Color(0xff9c6200) : const Color(0xff2563eb),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, softWrap: true)),
      ],
    ),
  );
}

class AdminMemberNoticeCard extends StatelessWidget {
  const AdminMemberNoticeCard({
    super.key,
    required this.controller,
    required this.strings,
  });
  final AdminMembersController controller;
  final AdminMembersStrings strings;
  @override
  Widget build(BuildContext context) {
    final notice = controller.notice;
    if (notice == null ||
        {
          AdminMembersNotice.loaded,
          AdminMembersNotice.empty,
        }.contains(notice)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: AdminMemberInfo(
          text: strings.notice(notice),
          warning: !{
            AdminMembersNotice.knownRead,
            AdminMembersNotice.knownPasswordReset,
            AdminMembersNotice.pageAdjusted,
            AdminMembersNotice.unknownReviewed,
          }.contains(notice),
        ),
      ),
    );
  }
}

class AdminMemberStatusBadge extends StatelessWidget {
  const AdminMemberStatusBadge({
    super.key,
    required this.status,
    required this.strings,
  });
  final AdminMemberStatus status;
  final AdminMembersStrings strings;
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      AdminMemberStatus.pending => (
        const Color(0xffffe7ad),
        const Color(0xff8b5700),
      ),
      AdminMemberStatus.approved => (
        const Color(0xffcef4d6),
        const Color(0xff176529),
      ),
      AdminMemberStatus.rejected => (
        const Color(0xffffd9dc),
        const Color(0xffa42c35),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        strings.status(status),
        style: TextStyle(
          color: foreground,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AdminMemberIdentityCard extends StatelessWidget {
  const AdminMemberIdentityCard({
    super.key,
    required this.member,
    required this.strings,
    this.showTimes = true,
    this.current = false,
  });
  final AdminMemberRecord member;
  final AdminMembersStrings strings;
  final bool showTimes, current;
  Widget _value(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xff586882))),
              const SizedBox(height: 4),
              SelectableText(value),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Color(0xff586882)),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: SelectableText(value, textAlign: TextAlign.end),
            ),
          ],
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xffdce3ef)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xffe2edff),
              child: Icon(Icons.person, color: Color(0xff4c78cc)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.account,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('ID: ${member.id}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(strings.role(member.role)),
                        visualDensity: VisualDensity.compact,
                      ),
                      AdminMemberStatusBadge(
                        status: member.status,
                        strings: strings,
                      ),
                      if (current)
                        Chip(
                          label: Text(strings.t('当前账户', 'Current account')),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showTimes) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          _value(
            context,
            strings.t('注册时间', 'Registered'),
            strings.date(member.created),
          ),
          _value(
            context,
            strings.t('最后登录', 'Last sign-in'),
            strings.date(member.lastLogin, login: true),
          ),
        ],
      ],
    ),
  );
}

class AdminMemberOperationPanel extends StatelessWidget {
  const AdminMemberOperationPanel({
    super.key,
    required this.controller,
    required this.strings,
    required this.onReviewed,
  });
  final AdminMembersController controller;
  final AdminMembersStrings strings;
  final VoidCallback onReviewed;
  @override
  Widget build(BuildContext context) {
    final pending = controller.pending;
    final reviewing = controller.phase == AdminMembersPhase.reviewingUnknown;
    final busy = controller.phase == AdminMembersPhase.readingCurrent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminMemberNoticeCard(controller: controller, strings: strings),
        if (pending != null) ...[
          Text(
            strings.t('原操作目标', 'Original operation target'),
            style: const TextStyle(color: Color(0xff586882)),
          ),
          const SizedBox(height: 6),
          Text(
            '${pending.target.account} (ID ${pending.target.id})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (pending.action == AdminMemberAction.resetPassword)
            AdminMemberInfo(
              text: strings.t(
                '密码无法从列表核对。若需要再次重置，必须明确发起新的操作。',
                'Passwords cannot be checked through this list. Another reset must be a new, explicit operation.',
              ),
            ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (reviewing) ...[
          const SizedBox(height: 16),
          Text(
            strings.t('当前列表可用资料', 'Current list details'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 12),
          if (controller.selected != null)
            AdminMemberIdentityCard(
              member: controller.selected!,
              strings: strings,
            )
          else
            Text(
              strings.t(
                '当前页未找到原目标，不能据此确认操作结果。',
                'The original member is not on this page. This does not establish the earlier result.',
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onReviewed,
            child: Text(strings.t('已核对，返回用户详情', 'Finish review and return')),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : () => controller.readCurrent(),
          icon: const Icon(Icons.refresh),
          label: Text(strings.t('只读取当前列表', 'Read current list only')),
        ),
      ],
    );
  }
}
