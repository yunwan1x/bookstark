import 'package:flutter/material.dart';
import 'admin_members_controller.dart';
import 'admin_members_models.dart';
import 'admin_members_repository.dart';
import 'admin_members_strings.dart';
import 'admin_members_widgets.dart';
import 'admin_settings_widgets.dart';

class AdminMemberRolePage extends StatefulWidget {
  const AdminMemberRolePage({
    super.key,
    required this.controller,
    required this.member,
    required this.strings,
    required this.onReturn,
    required this.onDone,
    required this.onReviewed,
  });
  final AdminMembersController controller;
  final AdminMemberRecord member;
  final AdminMembersStrings strings;
  final VoidCallback onReturn, onDone, onReviewed;
  @override
  State<AdminMemberRolePage> createState() => _AdminMemberRolePageState();
}

class _AdminMemberRolePageState extends State<AdminMemberRolePage> {
  late AdminMemberRole _role = widget.member.role;
  bool _confirming = false;
  AdminMembersController get c => widget.controller;
  AdminMembersStrings get s => widget.strings;
  @override
  void didUpdateWidget(covariant AdminMemberRolePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.id != widget.member.id ||
        oldWidget.member.account != widget.member.account) {
      _role = widget.member.role;
      _confirming = false;
    }
  }

  Future<void> _confirm() async {
    if (_confirming ||
        !c.ready ||
        widget.member.id == c.owner.memberId ||
        _role == widget.member.role) {
      return;
    }
    final target = widget.member;
    final role = _role;
    final revision = c.revision;
    setState(() => _confirming = true);
    try {
      final choice = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(s.t('确认修改角色', 'Confirm role change')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${target.account} (ID ${target.id})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Text('${s.role(target.role)} → ${s.role(role)}'),
                const SizedBox(height: 16),
                Text(
                  s.t(
                    '修改前会重新核对资料，完成后重新读取列表。',
                    'Details are checked again before the change and reloaded afterwards.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('确认修改', 'Confirm change')),
            ),
          ],
        ),
      );
      if (!mounted || choice != true || !c.ready || c.revision != revision) {
        return;
      }
      await c.submit(target, AdminMemberAction.role, newRole: role);
      if (mounted && c.ready) {
        widget.onDone();
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final operation = {
        AdminMembersPhase.unknown,
        AdminMembersPhase.reviewingUnknown,
        AdminMembersPhase.readingCurrent,
        AdminMembersPhase.knownNeedsRead,
      }.contains(c.phase);
      final self = widget.member.id == c.owner.memberId;
      final enabled = c.ready && !_confirming && !self;
      return Scaffold(
        backgroundColor: const Color(0xfff8faff),
        appBar: adminSettingsAppBar(
          context,
          title: s.t('修改角色', 'Change role'),
          dirty: false,
          onReturn: widget.onReturn,
          backLabel: s.t('返回', 'Back'),
          dirtyLabel: s.t('未保存', 'Unsaved'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (operation)
                AdminMemberOperationPanel(
                  controller: c,
                  strings: s,
                  onReviewed: widget.onReviewed,
                )
              else ...[
                AdminMemberNoticeCard(controller: c, strings: s),
                Container(
                  key: const ValueKey('member-role-summary'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xffdce3ef)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t('账号', 'Account'),
                        style: const TextStyle(color: Color(0xff586882)),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        widget.member.account,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('ID ${widget.member.id}'),
                      const SizedBox(height: 12),
                      Text(
                        '${s.t("当前角色", "Current role")}: ${s.role(widget.member.role)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  s.t('选择新角色', 'Choose a new role'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                RadioGroup<AdminMemberRole>(
                  groupValue: _role,
                  onChanged: (value) {
                    if (enabled && value != null) {
                      setState(() => _role = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final role in [
                        AdminMemberRole.member,
                        AdminMemberRole.administrator,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            key: ValueKey('member-role-option-${role.value}'),
                            color: _role == role
                                ? const Color(0xffe4efff)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: RadioListTile<AdminMemberRole>(
                              value: role,
                              enabled: enabled,
                              title: Text(s.role(role)),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (self)
                  AdminMemberInfo(
                    text: s.t('不能修改自己的角色。', 'You cannot change your own role.'),
                  )
                else
                  AdminMemberInfo(
                    text: s.t(
                      '管理员可以管理系统设置和用户。',
                      'Administrators can manage system settings and members.',
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: enabled && _role != widget.member.role
                      ? _confirm
                      : null,
                  child: Text(
                    c.phase == AdminMembersPhase.submitting
                        ? s.t('正在处理…', 'Processing…')
                        : s.t('下一步', 'Next'),
                  ),
                ),
                if (c.phase == AdminMembersPhase.submitting)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
