import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'admin_comment_models.dart';
import 'admin_community_confirmation_pages.dart';
import 'admin_community_controller.dart';
import 'admin_community_repository.dart';
import 'admin_community_scope.dart';
import 'admin_community_strings.dart';
import 'admin_community_widgets.dart';
import 'admin_friend_links_models.dart';
import 'admin_friend_links_page.dart';
import 'admin_friend_link_editor_page.dart';
import 'admin_share_comments_page.dart';
import 'admin_settings_widgets.dart';

enum AdminCommunityKind { links, comments }

enum _CommunityPage { list, editor, confirmation }

class AdminCommunityFeature extends StatefulWidget {
  const AdminCommunityFeature({
    super.key,
    required this.scope,
    required this.kind,
    required this.onReturn,
    this.english = false,
    this.controller,
    this.qrTransportFactory,
  });
  final AdminCommunityScope scope;
  final AdminCommunityKind kind;
  final VoidCallback onReturn;
  final bool english;
  final AdminCommunityController? controller;
  final http.Client Function()? qrTransportFactory;
  @override
  State<AdminCommunityFeature> createState() => _AdminCommunityFeatureState();
}

class _AdminCommunityFeatureState extends State<AdminCommunityFeature> {
  var _navigator = GlobalKey<NavigatorState>();
  AdminCommunityController? _controller;
  _CommunityPage _page = _CommunityPage.list;
  AdminFriendLink? _editorInitial;
  int? _editorRowKey;
  int _editorRevision = 0, _confirmationRevision = 0;
  bool _editorQr = false,
      _editorDirty = false,
      _editorNew = false,
      _confirming = false;
  AdminFriendLinksSnapshot? _saveSnapshot;
  List<AdminCommentRecord> _deleteTargets = [];
  AdminCommunityScope get scope => widget.scope;
  AdminCommunityStrings get s => AdminCommunityStrings(widget.english);
  AdminCommunityController get c => _controller!;
  BuildContext? get _dialogContext => _navigator.currentState?.overlay?.context;
  void _clearRoute() {
    _page = _CommunityPage.list;
    _editorInitial = null;
    _editorRowKey = null;
    _editorRevision = 0;
    _editorQr = false;
    _editorDirty = false;
    _editorNew = false;
    _saveSnapshot = null;
    _deleteTargets = [];
    _confirmationRevision = 0;
  }

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
        switch (widget.kind) {
          AdminCommunityKind.links => AdminFriendLinksController(
            AdminFriendLinksRepository(scope.client),
            scope.owner,
          ),
          AdminCommunityKind.comments => AdminCommentsController(
            AdminCommentsRepository(scope.client),
            scope.owner,
          ),
        };
    final client = switch (controller) {
      AdminFriendLinksController value => value.repository.client,
      AdminCommentsController value => value.repository.client,
      _ => null,
    };
    final kindMatches = widget.kind == AdminCommunityKind.links
        ? controller is AdminFriendLinksController
        : controller is AdminCommentsController;
    if (!kindMatches ||
        !controller.owner.sameAs(scope.owner) ||
        !identical(client, scope.client)) {
      controller.dispose();
      throw StateError('Community feature owner/client mismatch');
    }
    _controller = scope.own(controller);
    controller.addListener(_changed);
    switch (controller) {
      case AdminFriendLinksController value:
        unawaited(value.load().then<void>((_) {}));
      case AdminCommentsController value:
        unawaited(value.load().then<void>((_) {}));
    }
  }

  void _remove(AdminCommunityScope oldScope) {
    oldScope.removeListener(_scopeChanged);
    _controller?.removeListener(_changed);
    oldScope.release(_controller);
    _controller = null;
    _clearRoute();
  }

  @override
  void didUpdateWidget(covariant AdminCommunityFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != scope ||
        oldWidget.controller != widget.controller ||
        oldWidget.kind != widget.kind) {
      _remove(oldWidget.scope);
      _navigator = GlobalKey<NavigatorState>();
      _confirming = false;
      _install();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (c.phase == AdminCommunityPhase.permissionLost) {
      _clearRoute();
      final navigator = _navigator.currentState;
      scheduleMicrotask(() {
        if (mounted &&
            navigator != null &&
            identical(_navigator.currentState, navigator)) {
          navigator.popUntil((route) => route.isFirst);
        }
      });
    }
    setState(() {});
  }

  void _scopeChanged() {
    _clearRoute();
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

  Future<bool> _confirm(String title, String body, String action) async {
    final context = _dialogContext, heldScope = scope;
    if (_confirming || context == null || !context.mounted || !scope.guard()) {
      return false;
    }
    _confirming = true;
    var answered = false;
    try {
      final choice = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) {
          void finish(bool value) {
            if (answered) return;
            answered = true;
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(body)),
            actions: [
              TextButton(
                onPressed: () => finish(false),
                child: Text(s.t('取消', 'Cancel')),
              ),
              FilledButton(onPressed: () => finish(true), child: Text(action)),
            ],
          );
        },
      );
      return mounted &&
          identical(scope, heldScope) &&
          scope.guard() &&
          choice == true;
    } finally {
      if (mounted && identical(scope, heldScope)) {
        setState(() => _confirming = false);
      }
    }
  }

  Future<void> _back() async {
    if (!scope.active ||
        _controller == null ||
        c.phase == AdminCommunityPhase.permissionLost) {
      widget.onReturn();
      return;
    }
    if (c.phase == AdminCommunityPhase.submitting || _confirming) return;
    if (_page == _CommunityPage.confirmation) {
      setState(() {
        _page = _CommunityPage.list;
        _saveSnapshot = null;
        _deleteTargets = [];
      });
      return;
    }
    if (_page == _CommunityPage.editor) {
      if (_editorDirty &&
          !await _confirm(
            s.t('放弃当前编辑？', 'Discard this edit?'),
            s.t(
              '只放弃本页尚未应用的修改，列表中的草稿不变。',
              'Only unapplied changes on this page are discarded. The list draft is retained.',
            ),
            s.t('放弃编辑', 'Discard edit'),
          )) {
        return;
      }
      if (!mounted || !scope.active) return;
      setState(_clearRoute);
      return;
    }
    final dirty =
        c is AdminFriendLinksController &&
        (c as AdminFriendLinksController).dirty;
    if (c.pending || dirty) {
      final message = c.pendingKind == AdminCommunityPendingKind.notSubmitted
          ? s.t(
              '本次未提交，离开将放弃本地草稿。',
              'This operation was not submitted. Leaving discards the local draft.',
            )
          : c.pending
          ? s.t(
              '离开不会撤销服务器可能已完成的操作。旧请求不会自动重发。',
              'Leaving does not undo an operation the server may have completed. The earlier request will not be replayed.',
            )
          : s.t('离开将放弃尚未保存的列表草稿。', 'Leaving discards the unsaved list draft.');
      if (!await _confirm(
        s.t('离开管理页面？', 'Leave this page?'),
        message,
        s.t('离开本页', 'Leave page'),
      )) {
        return;
      }
    }
    if (mounted && scope.active) {
      widget.onReturn();
    }
  }

  Future<void> _chooseNew() async {
    if (_confirming ||
        !scope.guard() ||
        c is! AdminFriendLinksController ||
        !c.ready) {
      return;
    }
    final held = c as AdminFriendLinksController,
        heldScope = scope,
        revision = c.revision,
        context = _dialogContext;
    if (context == null || !context.mounted || held.rows.length >= 200) return;
    _confirming = true;
    var answered = false;
    try {
      final qr = await showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: false,
        isScrollControlled: true,
        builder: (context) {
          void choose(bool? value) {
            if (answered) return;
            answered = true;
            Navigator.pop(context, value);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () => choose(false),
                    child: Text(s.t('新增友情链接', 'Add friend link')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => choose(true),
                    child: Text(s.t('新增二维码条目', 'Add QR entry')),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => choose(null),
                    child: Text(s.t('取消', 'Cancel')),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (qr == null ||
          !mounted ||
          !identical(scope, heldScope) ||
          !identical(_controller, held) ||
          !scope.guard() ||
          !held.ready ||
          held.revision != revision) {
        return;
      }
      setState(() {
        _editorInitial = AdminFriendLink.create();
        _editorRowKey = null;
        _editorRevision = held.revision;
        _editorQr = qr;
        _editorNew = true;
        _editorDirty = false;
        _page = _CommunityPage.editor;
      });
    } finally {
      if (mounted && identical(scope, heldScope)) {
        setState(() => _confirming = false);
      }
    }
  }

  void _edit(AdminFriendLinkDraftRow row) {
    if (!scope.guard() ||
        c is! AdminFriendLinksController ||
        !c.ready ||
        _confirming) {
      return;
    }
    setState(() {
      _editorInitial = row.link;
      _editorRowKey = row.key;
      _editorRevision = c.revision;
      _editorQr = row.link.qr.trim().isNotEmpty;
      _editorNew = false;
      _editorDirty = false;
      _page = _CommunityPage.editor;
    });
  }

  bool _applyEditor(AdminFriendLink row) {
    if (!scope.guard() || c is! AdminFriendLinksController) return false;
    final applied = (c as AdminFriendLinksController).applyRow(
      _editorRowKey,
      row,
      expectedRevision: _editorRevision,
    );
    if (applied && mounted) {
      setState(_clearRoute);
    }
    return applied;
  }

  Future<void> _removeEditor() async {
    if (_editorRowKey == null ||
        _editorInitial == null ||
        c is! AdminFriendLinksController ||
        !c.ready) {
      return;
    }
    final held = c as AdminFriendLinksController,
        key = _editorRowKey!,
        revision = _editorRevision,
        name = _editorInitial!.name;
    if (!await _confirm(
      s.t('移除这条草稿？', 'Remove this draft entry?'),
      s.t(
        '$name\n仅从本地列表草稿移除。保存全部链接后才会更新服务器。',
        '$name\nThis removes it only from the local list draft. The server changes after saving the complete list.',
      ),
      s.t('移除草稿', 'Remove draft'),
    )) {
      return;
    }
    if (!identical(_controller, held) ||
        !held.removeRow(key, expectedRevision: revision)) {
      return;
    }
    if (mounted) {
      setState(_clearRoute);
    }
  }

  void _save() {
    if (!scope.guard() || c is! AdminFriendLinksController || _confirming) {
      return;
    }
    final held = c as AdminFriendLinksController;
    if (!held.validateDraft()) return;
    setState(() {
      _saveSnapshot = held.draft;
      _confirmationRevision = held.revision;
      _page = _CommunityPage.confirmation;
    });
  }

  void _delete() {
    if (!scope.guard() ||
        c is! AdminCommentsController ||
        !c.ready ||
        _confirming) {
      return;
    }
    final targets = (c as AdminCommentsController).reviewedSelection();
    if (targets.isEmpty) return;
    setState(() {
      _deleteTargets = List.unmodifiable(targets);
      _confirmationRevision = c.revision;
      _page = _CommunityPage.confirmation;
    });
  }

  Future<void> _submit() async {
    if (!scope.guard() ||
        !c.ready ||
        c.revision != _confirmationRevision ||
        _confirming) {
      return;
    }
    final held = c,
        heldScope = scope,
        revision = _confirmationRevision,
        targets = _deleteTargets;
    switch (held) {
      case AdminFriendLinksController value:
        await value.submit(expectedRevision: revision);
      case AdminCommentsController value:
        await value.submitDelete(expectedRevision: revision, targets: targets);
    }
    if (mounted &&
        identical(scope, heldScope) &&
        identical(_controller, held) &&
        scope.guard()) {
      setState(() {
        _page = _CommunityPage.list;
        _saveSnapshot = null;
        _deleteTargets = [];
      });
    }
  }

  Future<void> _reloadLinks() async {
    if (!scope.guard() || c is! AdminFriendLinksController || c.busy) return;
    final held = c as AdminFriendLinksController;
    if (held.dirty &&
        !await _confirm(
          s.t('放弃本地草稿并重新读取？', 'Discard the local draft and reload?'),
          s.t(
            '将采用服务器当前配置，本地列表草稿不会被保存。',
            'Current server configuration will be loaded. The local list draft will not be saved.',
          ),
          s.t('放弃草稿并读取', 'Discard draft and reload'),
        )) {
      return;
    }
    if (!identical(_controller, held) || !scope.guard()) return;
    await held.load(discardDraft: true);
  }

  Future<void> _readCurrent() async {
    if (!scope.guard() || c.busy) return;
    switch (c) {
      case AdminFriendLinksController value:
        await value.readCurrent();
      case AdminCommentsController value:
        await value.readCurrent();
    }
  }

  Future<void> _adoptLinks() async {
    if (!scope.guard() ||
        c is! AdminFriendLinksController ||
        !c.reviewing ||
        _confirming) {
      return;
    }
    final held = c as AdminFriendLinksController, revision = c.revision;
    if (!await _confirm(
      s.t('采用服务器当前配置？', 'Adopt current server configuration?'),
      s.t(
        '将放弃原本地列表草稿并结束本次核对。不会重新提交旧请求。',
        'The earlier local list draft will be discarded and this review will end. The earlier request will not be replayed.',
      ),
      s.t('采用当前配置', 'Adopt current configuration'),
    )) {
      return;
    }
    if (identical(_controller, held) &&
        held.revision == revision &&
        scope.guard()) {
      held.acknowledgeCurrent();
    }
  }

  void _finishCommentReview() {
    if (scope.guard() && c is AdminCommentsController) {
      (c as AdminCommentsController).acknowledgeCurrent();
    }
  }

  Widget _denied({bool closed = false}) => Scaffold(
    backgroundColor: Colors.white,
    appBar: adminSettingsAppBar(
      context,
      title: widget.kind == AdminCommunityKind.links
          ? s.t('友情链接', 'Friend links')
          : s.t('评论管理', 'Comment management'),
      dirty: false,
      onReturn: widget.onReturn,
      backLabel: s.t('返回', 'Back'),
      dirtyLabel: s.t('未保存', 'Unsaved'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!closed && _controller != null)
            AdminCommunityNoticeCard(controller: c, strings: s)
          else
            Text(
              s.t(
                '管理员会话已结束，请返回重新进入。',
                'The administrator session ended. Return and open this page again.',
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: widget.onReturn,
            child: Text(s.t('返回', 'Back')),
          ),
        ],
      ),
    ),
  );
  Widget _content() {
    if (c.phase == AdminCommunityPhase.permissionLost) return _denied();
    if (c is AdminFriendLinksController) {
      final links = c as AdminFriendLinksController;
      if (_page == _CommunityPage.editor && _editorInitial != null) {
        return AdminFriendLinkEditorPage(
          scope: scope,
          initial: _editorInitial!,
          strings: s,
          qrMode: _editorQr,
          isNew: _editorNew,
          enabled: links.ready && links.revision == _editorRevision,
          qrTransportFactory: widget.qrTransportFactory,
          onReturn: _back,
          onApply: _applyEditor,
          onDirtyChanged: (value) => _editorDirty = value,
          onRemove: _editorRowKey == null ? null : _removeEditor,
        );
      }
      if (_page == _CommunityPage.confirmation && _saveSnapshot != null) {
        return AdminFriendLinksSavePage(
          draft: _saveSnapshot!,
          strings: s,
          onReturn: _back,
          onConfirm: _submit,
          enabled: links.ready && links.revision == _confirmationRevision,
          busy: links.busy,
        );
      }
      return AdminFriendLinksPage(
        controller: links,
        strings: s,
        onReturn: _back,
        onAdd: _chooseNew,
        onSave: _save,
        onReload: _reloadLinks,
        onEdit: _edit,
        onReadCurrent: _readCurrent,
        onAdoptCurrent: _adoptLinks,
      );
    }
    final comments = c as AdminCommentsController;
    if (_page == _CommunityPage.confirmation && _deleteTargets.isNotEmpty) {
      return AdminCommentDeletePage(
        targets: _deleteTargets,
        strings: s,
        onReturn: _back,
        onConfirm: _submit,
        enabled: comments.ready && comments.revision == _confirmationRevision,
        busy: comments.busy,
      );
    }
    return AdminShareCommentsPage(
      controller: comments,
      strings: s,
      onReturn: _back,
      onDelete: _delete,
      onReadCurrent: _readCurrent,
      onFinishReview: _finishCommentReview,
    );
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
                    key: ValueKey(('admin-community-owned', widget.kind)),
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
            : _denied(closed: true),
      ),
    );
  }
}
