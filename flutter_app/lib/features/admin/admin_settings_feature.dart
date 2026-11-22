import 'admin_settings_l10n.dart';
import 'admin_settings_widgets.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_ai_settings_controller.dart';
import 'admin_ai_settings_page.dart';
import 'admin_content_settings_controller.dart';
import 'admin_content_settings_page.dart';
import 'admin_mail_settings_controller.dart';
import 'admin_mail_settings_page.dart';
import 'admin_numeric_settings_controller.dart';
import 'admin_numeric_settings_page.dart';
import 'admin_public_tags_controller.dart';
import 'admin_public_tags_page.dart';
import 'admin_recommendations_controller.dart';
import 'admin_recommendations_page.dart';
import 'admin_registration_controller.dart';
import 'admin_registration_page.dart';
import 'admin_settings_hub_page.dart';
import 'admin_settings_repository.dart';
import 'admin_settings_scope.dart';
import 'admin_signaling_controller.dart';
import 'admin_signaling_page.dart';
import 'admin_smtp_settings_controller.dart';
import 'admin_smtp_settings_page.dart';
import 'admin_text_settings_controller.dart';
import 'admin_text_settings_page.dart';
import 'admin_webdav_controller.dart';
import 'admin_webdav_page.dart';

enum _Page {
  hub,
  general,
  pagination,
  content,
  recommendations,
  publicTags,
  registration,
  signaling,
  ai,
  prompts,
  actions,
  mail,
  smtp,
  webDav,
  terminal,
}

class AdminSettingsFeature extends StatefulWidget {
  const AdminSettingsFeature({
    super.key,
    required this.scope,
    required this.onReturn,
    this.english = false,
  });
  final AdminSettingsScope scope;
  final VoidCallback onReturn;
  final bool english;
  @override
  State<AdminSettingsFeature> createState() => _AdminSettingsFeatureState();
}

class _AdminSettingsFeatureState extends State<AdminSettingsFeature> {
  String t(String value) =>
      adminSettingsTranslate(value, english: widget.english);
  String f(String pattern, List<Object?> values) =>
      adminSettingsFormat(context, pattern, values, english: widget.english);
  final _navigator = GlobalKey<NavigatorState>();
  AdminSettingsScope get scope => widget.scope;
  AdminSettingsHubController? _hub;
  ChangeNotifier? _controller;
  _Page _page = _Page.hub;
  bool _opening = false;
  AdminSettingsRepository _repository() =>
      AdminSettingsRepository(scope.client);

  @override
  void initState() {
    super.initState();
    _install();
  }

  void _install() {
    scope.addListener(_scopeChanged);
    if (scope.guard()) {
      _hub = scope.own(AdminSettingsHubController(_repository(), scope.owner));
    }
  }

  void _scopeChanged() {
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AdminSettingsFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != scope) {
      oldWidget.scope.removeListener(_scopeChanged);
      oldWidget.scope.release(_controller);
      oldWidget.scope.release(_hub);
      _controller = null;
      _hub = null;
      _page = _Page.hub;
      _install();
    }
  }

  @override
  void dispose() {
    scope.removeListener(_scopeChanged);
    scope.release(_controller);
    scope.release(_hub);
    super.dispose();
  }

  void _show(_Page page) {
    if (!mounted || !scope.guard()) return;
    scope.release(_controller);
    _controller = null;
    if (page != _Page.hub) {
      final repo = _repository();
      final owner = scope.owner;
      _controller = scope.own(switch (page) {
        _Page.general => AdminNumericSettingsController(
          repo,
          owner,
          general: true,
        ),
        _Page.pagination => AdminNumericSettingsController(
          repo,
          owner,
          general: false,
        ),
        _Page.terminal => AdminNumericSettingsController(
          repo,
          owner,
          general: false,
          terminal: true,
        ),
        _Page.content => AdminContentSettingsController(repo, owner),
        _Page.recommendations => AdminRecommendationsController(repo, owner),
        _Page.publicTags => AdminPublicTagsController(repo, owner),
        _Page.registration => AdminRegistrationController(repo, owner),
        _Page.signaling => AdminSignalingController(repo, owner),
        _Page.ai => AdminAiSettingsController(repo, owner),
        _Page.prompts => AdminTextSettingsController(
          repo,
          owner,
          prompts: true,
        ),
        _Page.actions => AdminTextSettingsController(
          repo,
          owner,
          prompts: false,
        ),
        _Page.mail => AdminMailSettingsController(repo, owner),
        _Page.smtp => AdminSmtpSettingsController(repo, owner),
        _Page.webDav => AdminWebDavSettingsController(repo, owner),
        _Page.hub => throw StateError('Hub uses its own controller'),
      });
    }
    setState(() => _page = page);
  }

  Future<void> _open(AdminSettingsDestination destination) async {
    if (_opening || !scope.guard() || _hub == null) return;
    _opening = true;
    try {
      final verified = await _hub!.verify();
      if (!mounted || !scope.guard() || !verified) return;
      _show(switch (destination) {
        AdminSettingsDestination.general => _Page.general,
        AdminSettingsDestination.content => _Page.content,
        AdminSettingsDestination.registration => _Page.registration,
        AdminSettingsDestination.ai => _Page.ai,
        AdminSettingsDestination.mail => _Page.mail,
        AdminSettingsDestination.webDav => _Page.webDav,
        AdminSettingsDestination.terminal => _Page.terminal,
      });
    } finally {
      _opening = false;
    }
  }

  Widget _content() {
    final key = ValueKey(_page);
    return switch (_page) {
      _Page.hub => AdminSettingsHubPage(
        key: key,
        controller: _hub!,
        onReturn: widget.onReturn,
        onOpen: _open,
      ),
      _Page.general => AdminNumericSettingsPage(
        key: key,
        controller: _controller! as AdminNumericSettingsController,
        onReturn: () => _show(_Page.hub),
        onPagination: () => _show(_Page.pagination),
      ),
      _Page.pagination || _Page.terminal => AdminNumericSettingsPage(
        key: key,
        controller: _controller! as AdminNumericSettingsController,
        onReturn: () =>
            _show(_page == _Page.terminal ? _Page.hub : _Page.general),
      ),
      _Page.content => AdminContentSettingsPage(
        key: key,
        controller: _controller! as AdminContentSettingsController,
        onReturn: () => _show(_Page.hub),
        onRecommendations: () => _show(_Page.recommendations),
        onPublicTags: () => _show(_Page.publicTags),
      ),
      _Page.recommendations => AdminRecommendationsPage(
        key: key,
        controller: _controller! as AdminRecommendationsController,
        onReturn: () => _show(_Page.content),
      ),
      _Page.publicTags => AdminPublicTagsPage(
        key: key,
        controller: _controller! as AdminPublicTagsController,
        onReturn: () => _show(_Page.content),
      ),
      _Page.registration => AdminRegistrationPage(
        key: key,
        controller: _controller! as AdminRegistrationController,
        onReturn: () => _show(_Page.hub),
        onSignaling: () => _show(_Page.signaling),
      ),
      _Page.signaling => AdminSignalingPage(
        key: key,
        controller: _controller! as AdminSignalingController,
        onReturn: () => _show(_Page.registration),
      ),
      _Page.ai => AdminAiSettingsPage(
        key: key,
        controller: _controller! as AdminAiSettingsController,
        onReturn: () => _show(_Page.hub),
        onPrompts: () => _show(_Page.prompts),
        onActions: () => _show(_Page.actions),
      ),
      _Page.prompts || _Page.actions => AdminTextSettingsPage(
        key: key,
        controller: _controller! as AdminTextSettingsController,
        onReturn: () => _show(_Page.ai),
      ),
      _Page.mail => AdminMailSettingsPage(
        key: key,
        controller: _controller! as AdminMailSettingsController,
        onReturn: () => _show(_Page.hub),
        onSmtp: () => _show(_Page.smtp),
      ),
      _Page.smtp => AdminSmtpSettingsPage(
        key: key,
        controller: _controller! as AdminSmtpSettingsController,
        onReturn: () => _show(_Page.mail),
      ),
      _Page.webDav => AdminWebDavSettingsPage(
        key: key,
        controller: _controller! as AdminWebDavSettingsController,
        onReturn: () => _show(_Page.hub),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = scope.active && _hub != null;
    if (!active) scope.close();
    return AdminSettingsLanguage(
      english: widget.english,
      child: Theme(
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
        ),
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
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
                      key: const ValueKey('admin-settings-owned'),
                      child: _content(),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                )
              : Scaffold(
                  appBar: adminSettingsAppBar(
                    context,
                    title: t('系统设置'),
                    dirty: false,
                    onReturn: widget.onReturn,
                    backLabel: t('返回'),
                    dirtyLabel: t('未保存'),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t('管理员会话已结束，请返回后重新进入。')),
                  ),
                ),
        ),
      ),
    );
  }
}
