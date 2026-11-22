import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_member_password_page.dart';
import 'admin_member_role_page.dart';
import 'admin_members_controller.dart';
import 'admin_members_page.dart';
import 'admin_members_repository.dart';
import 'admin_members_scope.dart';
import 'admin_members_strings.dart';
import 'admin_members_widgets.dart';
import 'admin_settings_widgets.dart';

enum _MemberPage { list, detail, role, password }

class AdminMembersFeature extends StatefulWidget {
  const AdminMembersFeature({
    super.key,
    required this.scope,
    required this.onReturn,
    this.english = false,
    this.controller,
  });
  final AdminMembersScope scope;
  final VoidCallback onReturn;
  final bool english;
  final AdminMembersController? controller;
  @override
  State<AdminMembersFeature> createState() => _AdminMembersFeatureState();
}

class _AdminMembersFeatureState extends State<AdminMembersFeature> {
  var _navigator = GlobalKey<NavigatorState>();
  AdminMembersController? _controller;
  _MemberPage _page = _MemberPage.list;
  bool _confirming = false, _leaving = false;
  AdminMembersStrings get s => AdminMembersStrings(widget.english);
  AdminMembersScope get scope => widget.scope;
  AdminMembersController get c => _controller!;
  BuildContext? get _dialogContext => _navigator.currentState?.overlay?.context;
  @override
  void initState() {
    super.initState();
    _install();
  }

  void _install() {
    scope.addListener(_scopeChanged);
    if (!scope.guard() || scope.owner.role != 0) {
      widget.controller?.dispose();
      scope.close();
      return;
    }
    final controller =
        widget.controller ??
        AdminMembersController(
          AdminMembersRepository(scope.client),
          scope.owner,
        );
    if (!controller.owner.sameAs(scope.owner) ||
        !identical(controller.repository.client, scope.client)) {
      controller.dispose();
      throw StateError('Member feature owner/client mismatch');
    }
    _controller = scope.own(controller);
    controller.addListener(_changed);
    unawaited(controller.load());
  }

  void _remove(AdminMembersScope oldScope) {
    oldScope.removeListener(_scopeChanged);
    _controller?.removeListener(_changed);
    oldScope.release(_controller);
    _controller = null;
  }

  @override
  void didUpdateWidget(covariant AdminMembersFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != scope || oldWidget.controller != widget.controller) {
      _remove(oldWidget.scope);
      _navigator = GlobalKey<NavigatorState>();
      _page = _MemberPage.list;
      _confirming = false;
      _install();
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scopeChanged() {
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _remove(scope);
    super.dispose();
  }

  void _select(int id) {
    if (scope.guard() && c.select(id)) {
      setState(() => _page = _MemberPage.detail);
    }
  }

  void _done() {
    if (!mounted || !scope.guard() || !c.ready) {
      return;
    }
    setState(
      () => _page = c.selected == null ? _MemberPage.list : _MemberPage.detail,
    );
  }

  void _reviewed() {
    if (c.acknowledgeUnknown()) {
      _done();
    }
  }

  Future<void> _back() async {
    if (!scope.guard() || _controller == null) {
      widget.onReturn();
      return;
    }
    if (c.phase == AdminMembersPhase.submitting || _leaving) {
      return;
    }
    if (c.phase == AdminMembersPhase.permissionLost) {
      widget.onReturn();
      return;
    }
    if (!c.hasUnresolved && c.selected == null && _page != _MemberPage.list) {
      setState(() => _page = _MemberPage.list);
      return;
    }
    if (c.hasUnresolved) {
      final context = _dialogContext;
      if (context == null || !context.mounted) {
        return;
      }
      _leaving = true;
      try {
        final leave = await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (context) => AlertDialog(
            title: Text(s.t('离开用户管理？', 'Leave member management?')),
            content: SingleChildScrollView(
              child: Text(
                s.t(
                  '离开不会撤销服务器可能已完成的操作。上次请求不会自动重发。',
                  'Leaving does not undo an operation the server may have completed. The earlier request will not be replayed.',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.t('继续核对', 'Continue review')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.t('离开用户管理', 'Leave member management')),
              ),
            ],
          ),
        );
        if (mounted && leave == true) {
          widget.onReturn();
        }
      } finally {
        _leaving = false;
      }
      return;
    }
    switch (_page) {
      case _MemberPage.list:
        widget.onReturn();
      case _MemberPage.detail:
        c.closeDetail();
        if (mounted) {
          setState(() => _page = _MemberPage.list);
        }
      case _MemberPage.role:
      case _MemberPage.password:
        if (mounted) {
          setState(() => _page = _MemberPage.detail);
        }
    }
  }

  Future<void> _approval() async {
    if (_confirming || !scope.guard() || !c.ready || c.selected == null) {
      return;
    }
    final target = c.selected!;
    final revision = c.revision;
    final context = _dialogContext;
    if (context == null || !context.mounted) {
      return;
    }
    setState(() => _confirming = true);
    try {
      final action = await showModalBottomSheet<AdminMemberAction>(
        context: context,
        useRootNavigator: false,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.t('审批处理', 'Review approval'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text('${target.account} (ID ${target.id})'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, AdminMemberAction.approve),
                  child: Text(s.t('审批通过', 'Approve member')),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, AdminMemberAction.reject),
                  child: Text(s.t('拒绝审批', 'Reject member')),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.t('取消', 'Cancel')),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted ||
          action == null ||
          !scope.guard() ||
          !c.ready ||
          c.revision != revision) {
        return;
      }
      final ownedContext = _dialogContext;
      if (ownedContext == null || !ownedContext.mounted) {
        return;
      }
      final approve = action == AdminMemberAction.approve;
      final confirmed = await showDialog<bool>(
        context: ownedContext,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(
            approve
                ? s.t('审批通过', 'Approve member')
                : s.t('拒绝审批', 'Reject member'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${target.account} (ID ${target.id})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  approve
                      ? s.t('将状态设置为已通过。', 'Set approval status to approved.')
                      : s.t('将状态设置为已拒绝。', 'Set approval status to rejected.'),
                ),
                const SizedBox(height: 12),
                Text(
                  s.t(
                    '操作前重新核对目标，完成后重新读取列表。',
                    'The target is checked again before the operation and the list is reloaded afterwards.',
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
              child: Text(
                approve
                    ? s.t('确认通过', 'Confirm approval')
                    : s.t('确认拒绝', 'Confirm rejection'),
              ),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          !scope.guard() ||
          !c.ready ||
          c.revision != revision) {
        return;
      }
      await c.submit(target, action);
      _done();
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  Widget _status() => Scaffold(
    backgroundColor: Colors.white,
    appBar: adminSettingsAppBar(
      context,
      title: s.t('用户管理', 'User management'),
      dirty: false,
      onReturn: _back,
      backLabel: s.t('返回', 'Back'),
      dirtyLabel: s.t('未保存', 'Unsaved'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.pending != null)
            AdminMemberOperationPanel(
              controller: c,
              strings: s,
              onReviewed: _reviewed,
            )
          else
            AdminMemberNoticeCard(controller: c, strings: s),
          if (c.phase == AdminMembersPhase.loading)
            const Center(child: CircularProgressIndicator()),
          if (c.pending == null && c.phase != AdminMembersPhase.permissionLost)
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _page = _MemberPage.list);
                if (c.ready) {
                  c.closeDetail();
                } else {
                  unawaited(c.load());
                }
              },
              icon: const Icon(Icons.refresh),
              label: Text(s.t('返回用户列表', 'Return to member list')),
            ),
        ],
      ),
    ),
  );
  Widget _content() {
    if (_page == _MemberPage.list) {
      return AdminMembersPage(
        controller: c,
        strings: s,
        onReturn: _back,
        onSelect: _select,
      );
    }
    final member = c.selected;
    if (member == null) {
      return _status();
    }
    return switch (_page) {
      _MemberPage.list => throw StateError('Unreachable member list'),
      _MemberPage.detail => AdminMemberDetailPage(
        controller: c,
        member: member,
        strings: s,
        onReturn: _back,
        onApproval: _approval,
        confirming: _confirming,
        onRole: () {
          if (c.ready) {
            setState(() => _page = _MemberPage.role);
          }
        },
        onPassword: () {
          if (c.ready) {
            setState(() => _page = _MemberPage.password);
          }
        },
        onReviewed: _reviewed,
      ),
      _MemberPage.role => AdminMemberRolePage(
        controller: c,
        member: member,
        strings: s,
        onReturn: _back,
        onDone: _done,
        onReviewed: _reviewed,
      ),
      _MemberPage.password => AdminMemberPasswordPage(
        controller: c,
        member: member,
        strings: s,
        onReturn: _back,
        onDone: _done,
        onReviewed: _reviewed,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = scope.active && scope.owner.role == 0 && _controller != null;
    if (!active) {
      scope.close();
    }
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            backgroundColor: const Color(0xff1555ef),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          if (!active) {
            widget.onReturn();
          } else {
            _navigator.currentState?.maybePop();
          }
        },
        child: active
            ? Navigator(
                key: _navigator,
                pages: [
                  MaterialPage<void>(
                    key: const ValueKey('admin-members-owned'),
                    child: PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (didPop, result) {
                        if (!didPop) {
                          unawaited(_back());
                        }
                      },
                      child: _content(),
                    ),
                  ),
                ],
                onDidRemovePage: (_) {},
              )
            : Scaffold(
                appBar: adminSettingsAppBar(
                  context,
                  title: s.t('用户管理', 'User management'),
                  dirty: false,
                  onReturn: widget.onReturn,
                  backLabel: s.t('返回', 'Back'),
                  dirtyLabel: s.t('未保存', 'Unsaved'),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    s.t(
                      '管理员会话已结束，请返回后重新进入。',
                      'The administrator session ended. Return and open this page again.',
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
