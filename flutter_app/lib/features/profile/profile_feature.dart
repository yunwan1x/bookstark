import '../admin/admin_assets_feature.dart';
import '../admin/admin_assets_scope.dart';
import '../admin/admin_community_feature.dart';
import '../admin/admin_community_scope.dart';
import '../admin/admin_members_feature.dart';
import '../admin/admin_members_scope.dart';
import '../admin/admin_settings_feature.dart';
import '../admin/admin_settings_scope.dart';
import '../admin/admin_settings_repository.dart';
import '../admin/admin_dashboard_controller.dart';
import '../admin/admin_dashboard_repository.dart';
import '../admin/admin_dashboard_page.dart';
import '../../core/trash_repository.dart';
import '../trash/trash_page.dart';
import '../credentials/credentials_feature.dart';

import 'dart:typed_data';

import '../../core/background_repository.dart';
import 'background_page.dart';
import '../../core/reminder_repository.dart';
import 'reminder_page.dart';
import 'profile_edit_page.dart';
import '../../core/account_password_repository.dart';
import 'account_security_page.dart';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/profile_repository.dart';
import 'profile_page.dart';

class ProfileFeature extends StatefulWidget {
  const ProfileFeature({
    super.key,
    required this.client,
    required this.memberId,
    required this.onLanguage,
    required this.onLogout,
    required this.onNavigate,
    required this.persistSession,
    required this.onBackgroundApplied,
    this.verifierFactory,
    this.english = false,
  });
  final BookstarkClient client;
  final Future<void> Function(BackgroundPreference, Uint8List?)
  onBackgroundApplied;
  final Future<bool> Function() persistSession;
  final BookstarkClient Function(String)? verifierFactory;
  final int memberId;
  final bool english;
  final Future<void> Function(bool) onLanguage;
  final Future<void> Function() onLogout;
  final ValueChanged<String> onNavigate;
  @override
  State<ProfileFeature> createState() => _ProfileFeatureState();
}

class _ProfileFeatureState extends State<ProfileFeature> {
  late final _repository = RemoteProfileRepository(
    widget.client,
    memberId: widget.memberId,
  );
  late bool _english = widget.english;
  AdminDashboardController? _dashboardController;
  Future<void>? _dashboardOpening;
  AdminAssetsScope? _assetsScope;
  Future<void>? _assetsOpening;
  AdminCommunityScope? _communityScope;
  Future<void>? _communityOpening;
  AdminMembersScope? _membersScope;
  Future<void>? _membersOpening;
  AdminSettingsScope? _settingsScope;
  Future<void>? _settingsOpening;

  @override
  void dispose() {
    _assetsScope?.dispose();
    _assetsScope = null;
    _communityScope?.dispose();
    _communityScope = null;
    _membersScope?.dispose();
    _membersScope = null;
    _settingsScope?.dispose();
    _settingsScope = null;
    final controller = _dashboardController;
    _dashboardController = null;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _dashboard() {
    final inFlight = _dashboardOpening;
    if (inFlight != null) return inFlight;
    final opening = _openDashboard();
    _dashboardOpening = opening;
    return opening.whenComplete(() {
      if (identical(_dashboardOpening, opening)) _dashboardOpening = null;
    });
  }

  Future<void> _openDashboard() async {
    final session = widget.client.exportSession()['token'];
    if (session is! String || session.isEmpty) {
      throw StateError('An authenticated server session is required');
    }
    final member = await _repository.read();
    if (!mounted ||
        widget.client.exportSession()['token'] != session ||
        member.id != widget.memberId) {
      return;
    }
    if (member.role != 0) throw StateError('Administrator access required');
    final controller = AdminDashboardController(
      AdminDashboardRepository(widget.client),
    );
    _dashboardController = controller;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => AdminDashboardPage(
            controller: controller,
            english: _english,
            onReturn: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } finally {
      if (identical(_dashboardController, controller)) {
        _dashboardController = null;
        controller.dispose();
      }
    }
  }

  Future<void> _settings() {
    final pending = _settingsOpening;
    if (pending != null) return pending;
    final task = _openSettings();
    _settingsOpening = task;
    return task.whenComplete(() {
      if (identical(_settingsOpening, task)) _settingsOpening = null;
    });
  }

  Future<void> _openSettings() async {
    final session = widget.client.exportSession()['token'];
    if (session is! String || session.isEmpty) {
      throw StateError('Authenticated administrator required');
    }
    final member = await _repository.read();
    if (!mounted ||
        widget.client.exportSession()['token'] != session ||
        member.id != widget.memberId) {
      return;
    }
    if (member.role != 0) throw StateError('Administrator access required');
    final scope = AdminSettingsScope(
      widget.client,
      AdminPrincipal(
        memberId: member.id,
        account: member.account,
        role: member.role,
      ),
    );
    _settingsScope = scope;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => AdminSettingsFeature(
            scope: scope,
            english: _english,
            onReturn: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } finally {
      if (identical(_settingsScope, scope)) {
        _settingsScope = null;
        scope.dispose();
      }
    }
  }

  Future<void> _members() {
    final pending = _membersOpening;
    if (pending != null) return pending;
    final task = _openMembers();
    _membersOpening = task;
    return task.whenComplete(() {
      if (identical(_membersOpening, task)) _membersOpening = null;
    });
  }

  Future<void> _openMembers() async {
    final session = widget.client.exportSession()['token'];
    if (session is! String || session.isEmpty) {
      throw StateError('Authenticated administrator required');
    }
    final member = await _repository.read();
    if (!mounted ||
        widget.client.exportSession()['token'] != session ||
        member.id != widget.memberId) {
      return;
    }
    if (member.role != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _english
                ? 'The current account cannot manage members.'
                : '当前账户没有用户管理权限。',
          ),
        ),
      );
      return;
    }
    final scope = AdminMembersScope(
      widget.client,
      AdminPrincipal(
        memberId: member.id,
        account: member.account,
        role: member.role,
      ),
    );
    _membersScope = scope;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => AdminMembersFeature(
            scope: scope,
            english: _english,
            onReturn: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } finally {
      if (identical(_membersScope, scope)) {
        _membersScope = null;
        scope.dispose();
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProfileFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.memberId != widget.memberId) {
      _assetsScope?.dispose();
      _assetsScope = null;
    }
  }

  Future<void> _assets() {
    final pending = _assetsOpening;
    if (pending != null) return pending;
    final task = _openAssets();
    _assetsOpening = task;
    return task.whenComplete(() {
      if (identical(_assetsOpening, task)) _assetsOpening = null;
    });
  }

  Future<void> _openAssets() async {
    final client = widget.client;
    final session = client.exportSession()['token'];
    if (session is! String || session.isEmpty) {
      throw StateError('Authenticated administrator required');
    }
    final profile = await client.adminAssetPrincipalJson();
    if (!mounted ||
        !identical(widget.client, client) ||
        client.exportSession()['token'] != session) {
      return;
    }
    final id = profile['member_id'],
        account = profile['account'],
        role = profile['role'];
    if (id is! int ||
        id != widget.memberId ||
        account is! String ||
        account.isEmpty ||
        role is! int) {
      throw const FormatException('Invalid asset administrator identity');
    }
    if (role != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _english
                ? 'The current account cannot manage these resources.'
                : '当前账户没有此管理权限。',
          ),
        ),
      );
      return;
    }
    final scope = AdminAssetsScope(
      client,
      AdminPrincipal(memberId: id, account: account, role: role),
    );
    _assetsScope = scope;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => AdminAssetsFeature(
            scope: scope,
            english: _english,
            onReturn: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } finally {
      if (identical(_assetsScope, scope)) {
        _assetsScope = null;
        scope.dispose();
      }
    }
  }

  Future<void> _community(AdminCommunityKind kind) {
    final pending = _communityOpening;
    if (pending != null) return pending;
    final task = _openCommunity(kind);
    _communityOpening = task;
    return task.whenComplete(() {
      if (identical(_communityOpening, task)) _communityOpening = null;
    });
  }

  Future<void> _openCommunity(AdminCommunityKind kind) async {
    final session = widget.client.exportSession()['token'];
    if (session is! String || session.isEmpty) {
      throw StateError('Authenticated administrator required');
    }
    final member = await _repository.read();
    if (!mounted ||
        widget.client.exportSession()['token'] != session ||
        member.id != widget.memberId) {
      return;
    }
    if (member.role != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _english
                ? 'The current account cannot manage these resources.'
                : '当前账户没有此管理权限。',
          ),
        ),
      );
      return;
    }
    final scope = AdminCommunityScope(
      widget.client,
      AdminPrincipal(
        memberId: member.id,
        account: member.account,
        role: member.role,
      ),
    );
    _communityScope = scope;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => AdminCommunityFeature(
            scope: scope,
            kind: kind,
            english: _english,
            onReturn: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    } finally {
      if (identical(_communityScope, scope)) {
        _communityScope = null;
        scope.dispose();
      }
    }
  }

  Future<void> _security() async {
    final member = await _repository.read();
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSecurityPage(
          member: member,
          repository: RemoteAccountPasswordRepository(
            widget.client,
            member: member,
            saveSession: widget.persistSession,
            verifierFactory: widget.verifierFactory,
          ),
          english: _english,
        ),
      ),
    );
  }

  Future<void> _background() async {
    final repo = RemoteBackgroundRepository(
      widget.client,
      memberId: widget.memberId,
    );
    final preference = await repo.read();
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BackgroundPage(
          repository: repo,
          preference: preference,
          english: _english,
          onApplied: widget.onBackgroundApplied,
        ),
      ),
    );
  }

  Future<void> _reminders() async {
    final repo = RemoteReminderRepository(
      widget.client,
      memberId: widget.memberId,
    );
    final settings = await repo.read();
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderPage(
          repository: repo,
          settings: settings,
          english: _english,
          onEditEmail: () async {
            final profile = await _repository.read();
            if (!mounted) {
              return;
            }
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileEditPage(
                  repository: _repository,
                  profile: profile,
                  english: _english,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ProfilePage(
    repository: _repository,
    onSecurity: _security,
    onAdminDashboard: _dashboard,
    onAdminSettings: _settings,
    onAdminMembers: _members,
    onAdminFriendLinks: () => _community(AdminCommunityKind.links),
    onAdminShareComments: () => _community(AdminCommunityKind.comments),
    onAdminAssets: _assets,
    onReminders: _reminders,
    onAppearance: _background,
    onTrash: () => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TrashPage(
          repository: RemoteTrashRepository(
            widget.client,
            memberId: widget.memberId,
          ),
          english: _english,
        ),
      ),
    ),
    onApi: () => openCredentials(
      context,
      client: widget.client,
      memberId: widget.memberId,
      english: _english,
    ),
    server: widget.client.baseUri,
    english: _english,
    onLogout: widget.onLogout,
    onNavigate: widget.onNavigate,
    onLanguage: (english) async {
      await widget.onLanguage(english);
      if (mounted) {
        setState(() => _english = english);
      }
    },
  );
}
