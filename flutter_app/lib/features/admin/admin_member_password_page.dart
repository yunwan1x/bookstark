import 'package:flutter/material.dart';
import 'admin_members_controller.dart';
import 'admin_members_models.dart';
import 'admin_members_repository.dart';
import 'admin_members_strings.dart';
import 'admin_members_widgets.dart';
import 'admin_settings_widgets.dart';

class AdminMemberPasswordPage extends StatefulWidget {
  const AdminMemberPasswordPage({
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
  State<AdminMemberPasswordPage> createState() =>
      _AdminMemberPasswordPageState();
}

class _AdminMemberPasswordPageState extends State<AdminMemberPasswordPage> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _showPassword = false, _showConfirmation = false, _confirming = false;
  String? _error;
  AdminMembersController get c => widget.controller;
  AdminMembersStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AdminMemberPasswordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
      _clear();
    }
    if (oldWidget.member.id != widget.member.id ||
        oldWidget.member.account != widget.member.account) {
      _clear();
    }
  }

  void _clear() {
    _password.clear();
    _confirmation.clear();
    _showPassword = false;
    _showConfirmation = false;
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    if (!{
          AdminMembersPhase.ready,
          AdminMembersPhase.submitting,
        }.contains(c.phase) ||
        c.notice == AdminMembersNotice.knownPasswordReset) {
      _clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  bool _validate() {
    try {
      AdminMemberPassword.validate(_password.text, _confirmation.text);
      return true;
    } on FormatException catch (error) {
      setState(
        () => _error = error.message.contains('confirmation')
            ? s.t('两次新密码不一致。', 'The new passwords do not match.')
            : s.t(
                '密码必须为 6–72 个 UTF-8 字节。',
                'The password must contain 6–72 UTF-8 bytes.',
              ),
      );
      return false;
    }
  }

  Future<void> _confirm() async {
    if (_confirming ||
        !c.ready ||
        widget.member.status != AdminMemberStatus.approved ||
        !_validate()) {
      return;
    }
    final target = widget.member;
    final revision = c.revision;
    setState(() {
      _confirming = true;
      _showPassword = false;
      _showConfirmation = false;
    });
    try {
      // Do not retain a password string across the confirmation dialog.
      final choice = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(s.t('确认重置密码', 'Confirm password reset')),
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
                Text(
                  s.t(
                    '重置后，该用户已有登录将失效。',
                    'Resetting the password invalidates the member’s existing sessions.',
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
              child: Text(s.t('确认重置', 'Confirm reset')),
            ),
          ],
        ),
      );
      if (!mounted ||
          choice != true ||
          !c.ready ||
          c.revision != revision ||
          !_validate()) {
        return;
      }
      await c.submit(
        target,
        AdminMemberAction.resetPassword,
        newPassword: _password.text,
        onSubmitted: () {
          if (mounted) {
            setState(_clear);
          }
        },
      );
      if (mounted && c.ready) {
        widget.onDone();
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  void _edited(String value) {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final operation = {
      AdminMembersPhase.unknown,
      AdminMembersPhase.reviewingUnknown,
      AdminMembersPhase.readingCurrent,
      AdminMembersPhase.knownNeedsRead,
    }.contains(c.phase);
    final enabled =
        c.ready &&
        !_confirming &&
        widget.member.status == AdminMemberStatus.approved;
    return Scaffold(
      backgroundColor: const Color(0xfff8faff),
      appBar: adminSettingsAppBar(
        context,
        title: s.t('重置密码', 'Reset password'),
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
              AdminMemberIdentityCard(
                member: widget.member,
                strings: s,
                showTimes: false,
                current: widget.member.id == c.owner.memberId,
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xffad2535)),
                    ),
                  ),
                ),
              Column(
                key: const ValueKey('member-password-form'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminSettingsField(
                    fieldKey: const ValueKey('member-new-password'),
                    controller: _password,
                    label: s.t('新密码', 'New password'),
                    enabled: enabled,
                    onChanged: _edited,
                    obscureText: !_showPassword,
                    suffixIcon: IconButton(
                      onPressed: enabled
                          ? () => setState(() => _showPassword = !_showPassword)
                          : null,
                      tooltip: _showPassword
                          ? s.t('隐藏新密码', 'Hide new password')
                          : s.t('显示新密码', 'Show new password'),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  AdminSettingsField(
                    fieldKey: const ValueKey('member-confirm-password'),
                    controller: _confirmation,
                    label: s.t('确认新密码', 'Confirm new password'),
                    enabled: enabled,
                    onChanged: _edited,
                    obscureText: !_showConfirmation,
                    helper: s.t(
                      '密码长度为 6–72 个 UTF-8 字节。',
                      'Use 6–72 UTF-8 bytes.',
                    ),
                    suffixIcon: IconButton(
                      onPressed: enabled
                          ? () => setState(
                              () => _showConfirmation = !_showConfirmation,
                            )
                          : null,
                      tooltip: _showConfirmation
                          ? s.t('隐藏确认密码', 'Hide password confirmation')
                          : s.t('显示确认密码', 'Show password confirmation'),
                      icon: Icon(
                        _showConfirmation
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    enabled &&
                        _password.text.isNotEmpty &&
                        _confirmation.text.isNotEmpty
                    ? _confirm
                    : null,
                child: Text(
                  c.phase == AdminMembersPhase.submitting
                      ? s.t('正在处理…', 'Processing…')
                      : s.t('确认重置', 'Confirm reset'),
                ),
              ),
              const SizedBox(height: 24),
              AdminMemberInfo(
                warning: true,
                text: s.t(
                  '重置后，该用户已有登录将失效。',
                  'Resetting the password invalidates the member’s existing sessions.',
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
  }
}
