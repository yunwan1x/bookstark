import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_remote_dav_theme.dart';
import 'admin_asset_secure_window.dart';
import 'admin_assets_scope.dart';
import 'admin_remote_dav_controller.dart';
import 'admin_remote_dav_models.dart';
import 'admin_remote_dav_repository.dart';
import 'admin_remote_dav_files_page.dart';

class AdminDavPage extends StatefulWidget {
  const AdminDavPage({
    super.key,
    required this.scope,
    required this.onReturn,
    required this.onBuiltin,
    this.english = false,
    this.secureWindowFactory,
  });
  final AdminAssetWindowGuard Function()? secureWindowFactory;
  final AdminAssetsScope scope;
  final VoidCallback onReturn, onBuiltin;
  final bool english;
  @override
  State<AdminDavPage> createState() => _AdminDavPageState();
}

class _AdminDavPageState extends State<AdminDavPage>
    with WidgetsBindingObserver {
  late final c = widget.scope.own(
    AdminDavController(AdminDavRepository(widget.scope)),
  );
  final query = TextEditingController();
  AdminAssetStatus? filter;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    unawaited(c.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      query.clear();
      c.background();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    widget.scope.release(c);
    query.dispose();
    super.dispose();
  }

  Future<void> _edit([AdminDavServer? server]) async {
    if (!c.canAct || !await c.loadCredentials() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminDavEditorPage(
          controller: c,
          server: server,
          english: widget.english,
        ),
      ),
    );
  }

  Future<void> _review(AdminDavServer server, AdminDavMutation action) async {
    if (!await c.prepare(action, server: server) || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            AdminDavReviewPage(controller: c, english: widget.english),
      ),
    );
  }

  Future<void> _files(AdminDavServer server) async {
    final binding = await c.bind(server);
    if (!mounted || binding == null || !c.canAct) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AdminDavFilesPage(
          scope: widget.scope,
          binding: binding,
          secureWindow: widget.secureWindowFactory?.call(),
          english: widget.english,
          onReturn: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  String get failure => switch (c.failure) {
    AdminDavFailure.changed => t(
      '连接或凭据已变化，请重新读取核对。',
      'Connection or credential changed. Read again.',
    ),
    AdminDavFailure.refused => t(
      '服务器拒绝了操作。',
      'The server refused the operation.',
    ),
    AdminDavFailure.unknown => t(
      '上次操作结果未确认，请只读核对。',
      'Previous result unknown. Inspect without resending.',
    ),
    AdminDavFailure.ownerLost => t(
      '管理员会话已失效。',
      'Administrator session expired.',
    ),
    AdminDavFailure.background => t(
      '切到后台后已清除连接资料，请重新读取。',
      'Connection details cleared in background. Read again.',
    ),
    _ => t('读取失败，请重试。', 'Read failed. Retry.'),
  };
  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
  String _status(AdminAssetStatus value) => switch (value) {
    AdminAssetStatus.online => t('连接正常', 'Online'),
    AdminAssetStatus.offline => t('连接失败', 'Offline'),
    AdminAssetStatus.unknown => t('尚未检测', 'Not tested'),
  };
  @override
  Widget build(BuildContext context) => AdminDavScaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: Text(t('WebDAV 连接', 'WebDAV connections')),
      leading: IconButton(
        onPressed: widget.onReturn,
        icon: const Icon(Icons.arrow_back),
        tooltip: t('返回', 'Back'),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('管理远程存储连接与文件。', 'Manage remote storage connections and files.'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: c.canAct ? () => unawaited(_edit()) : null,
                icon: const Icon(Icons.add),
                label: Text(t('添加连接', 'Add connection')),
              ),
              OutlinedButton.icon(
                onPressed: c.canRead && c.repository.unknown == null
                    ? () => unawaited(c.load(query: query.text, status: filter))
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(t('重新读取', 'Read again')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: query,
            enabled: c.canRead && c.repository.unknown == null,
            onSubmitted: (_) =>
                unawaited(c.load(query: query.text, status: filter)),
            decoration: InputDecoration(
              labelText: t('搜索连接', 'Search connections'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in <AdminAssetStatus?>[
                null,
                ...AdminAssetStatus.values,
              ])
                ChoiceChip(
                  label: Text(
                    status == null ? t('全部', 'All') : _status(status),
                  ),
                  selected: filter == status,
                  onSelected: c.canRead && c.repository.unknown == null
                      ? (_) {
                          setState(() => filter = status);
                          unawaited(c.load(query: query.text, status: status));
                        }
                      : null,
                ),
            ],
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(failure),
            ),
          if (c.receipt != null)
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('已收到服务器确认', 'Server acknowledgment received')),
                  if (c.tested != null) Text(_status(c.tested!.status)),
                  if (c.tested != null)
                    Text(
                      t(
                        '检测不代表文件读写已验证。',
                        'A connection test does not verify file read/write access.',
                      ),
                    ),
                ],
              ),
            ),
          if (c.repository.unknown != null)
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(
                      '当前列表只用于观察，不能证明上次操作成功。',
                      'The current list is an observation, not a receipt for the previous operation.',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.canRead && !c.suspended
                        ? () => unawaited(c.observeUnknown())
                        : null,
                    child: Text(t('只读核对连接', 'Inspect connections only')),
                  ),
                  if (c.suspended)
                    OutlinedButton(
                      onPressed: c.canRead
                          ? () {
                              c.suspended = false;
                              unawaited(c.observeUnknown());
                            }
                          : null,
                      child: Text(t('明确重新核对', 'Inspect again explicitly')),
                    ),
                  FilledButton(
                    onPressed:
                        c.canRead &&
                            c.rows != null &&
                            c.repository.unknown?.catalogObserved == true
                        ? c.finishUnknownReview
                        : null,
                    child: Text(t('结束本次核对', 'Finish this review')),
                  ),
                ],
              ),
            ),
          if (c.rows?.isEmpty == true)
            Text(t('没有匹配的连接', 'No matching connections')),
          for (final row in c.rows ?? <AdminDavConnection>[])
            if (row is AdminDavBuiltin)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t(
                        '应用密码与本机空间独立管理。',
                        'Manage app passwords and local storage separately.',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: c.canAct ? widget.onBuiltin : null,
                      child: Text(t('管理内置 WebDAV', 'Manage built-in WebDAV')),
                    ),
                  ],
                ),
              )
            else if (row is AdminDavServer)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(row.url),
                    Text('${t('根目录', 'Root')}: ${row.root}'),
                    Text(
                      '${t('凭据', 'Credential')}: ${row.credentialName ?? row.credentialId}',
                    ),
                    Text(_status(row.status)),
                    if (row.checked != null) Text(row.checked!.raw),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: c.canAct
                              ? () => unawaited(_files(row))
                              : null,
                          child: Text(t('浏览文件', 'Browse files')),
                        ),
                        OutlinedButton(
                          onPressed: c.canAct
                              ? () => unawaited(
                                  _review(row, AdminDavMutation.test),
                                )
                              : null,
                          child: Text(t('检测连接', 'Test connection')),
                        ),
                        OutlinedButton(
                          onPressed: c.canAct
                              ? () => unawaited(_edit(row))
                              : null,
                          child: Text(t('编辑', 'Edit')),
                        ),
                        TextButton(
                          onPressed: c.canAct
                              ? () => unawaited(
                                  _review(row, AdminDavMutation.delete),
                                )
                              : null,
                          child: Text(t('删除连接', 'Delete connection')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}

class AdminDavEditorPage extends StatefulWidget {
  const AdminDavEditorPage({
    super.key,
    required this.controller,
    this.server,
    this.english = false,
  });
  final AdminDavController controller;
  final AdminDavServer? server;
  final bool english;
  @override
  State<AdminDavEditorPage> createState() => _AdminDavEditorPageState();
}

class _AdminDavEditorPageState extends State<AdminDavEditorPage>
    with WidgetsBindingObserver {
  late final name = TextEditingController(text: widget.server?.name ?? '');
  late final url = TextEditingController(
    text: widget.server?.urlNeedsReplacement == true
        ? ''
        : widget.server?.url ?? 'https://',
  );
  late final root = TextEditingController(text: widget.server?.root ?? '/');
  late int? credentialId = widget.server?.credentialId;
  String? error;
  bool retired = false;
  AdminDavController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      name.clear();
      url.clear();
      root.clear();
      credentialId = null;
      retired = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    name.dispose();
    url.dispose();
    root.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    try {
      final draft = AdminDavDraft(
        name: name.text,
        url: url.text,
        root: root.text,
        credentialId: credentialId ?? 0,
      );
      if (!await c.prepare(
            widget.server == null
                ? AdminDavMutation.create
                : AdminDavMutation.update,
            server: widget.server,
            draft: draft,
          ) ||
          !mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              AdminDavReviewPage(controller: c, english: widget.english),
        ),
      );
      if (mounted && (c.receipt != null || c.repository.unknown != null)) {
        Navigator.of(context).pop();
      }
    } on FormatException {
      if (mounted) {
        setState(
          () => error = t(
            '请检查名称、URL、根目录及密码类型凭据。URL 不得包含账号密码或查询参数。',
            'Check the name, URL, root and password credential. URL credentials and query parameters are not allowed.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdminDavScaffold(
    appBar: AppBar(title: Text(t('连接设置', 'Connection settings'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.server?.urlNeedsReplacement == true)
            Text(
              t(
                '原地址中的认证参数已隐藏，请重新填写连接地址后再保存。',
                'Authentication parameters in the saved URL are hidden. Enter a replacement URL before saving.',
              ),
            ),
          if (retired)
            Text(
              t(
                '切到后台后已清除表单，请返回重新打开。',
                'Form cleared in background. Return and reopen.',
              ),
            ),
          for (final field in [
            (name, t('连接名称', 'Connection name')),
            (url, 'WebDAV URL'),
            (root, t('根目录', 'Root path')),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: field.$1,
                enabled: !retired && c.canAct,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: field.$2),
              ),
            ),
          Text(
            t(
              '选择密码类型凭据；不会读取或显示密码。',
              'Select a password credential. Its password is never read or displayed.',
            ),
          ),
          RadioGroup<int>(
            groupValue: credentialId,
            onChanged: (value) {
              if (!retired && c.canAct) setState(() => credentialId = value);
            },
            child: Column(
              children: [
                for (final row
                    in c.credentialRows ?? <AdminAssetCredentialMetadata>[])
                  RadioListTile<int>(
                    value: row.id,
                    title: Text(row.name),
                    subtitle: Text(row.username),
                    enabled: !retired && c.canAct,
                  ),
              ],
            ),
          ),
          if (error != null) Text(error!),
          if (c.failure != null)
            Text(
              t(
                '未能准备核对，请返回重新读取。',
                'Could not prepare review. Return and read again.',
              ),
            ),
          FilledButton(
            onPressed: !retired && c.canAct && credentialId != null
                ? () => unawaited(_next())
                : null,
            child: Text(t('下一步', 'Next')),
          ),
        ],
      ),
    ),
  );
}

class AdminDavReviewPage extends StatelessWidget {
  const AdminDavReviewPage({
    super.key,
    required this.controller,
    this.english = false,
  });
  final AdminDavController controller;
  final bool english;
  String t(String zh, String en) => english ? en : zh;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, plan = c.review;
      return AdminDavScaffold(
        appBar: AppBar(title: Text(t('核对连接操作', 'Review connection operation'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (plan != null) ...[
                Text(plan.server?.name ?? plan.draft!.name),
                Text(plan.draft?.url ?? plan.server!.url),
                Text(plan.draft?.root ?? plan.server!.root),
                Text('${t('凭据', 'Credential')}: ${plan.credential.name}'),
                if (plan.action == AdminDavMutation.delete)
                  Text(
                    t(
                      '只删除连接配置，不会删除远程文件。',
                      'Deletes the connection configuration only. Remote files are kept.',
                    ),
                  ),
                if (plan.action == AdminDavMutation.test)
                  Text(
                    t(
                      '通过服务器检测连接，结果不保证文件可读写。',
                      'Test through the server. A connection result does not guarantee file read/write access.',
                    ),
                  ),
              ] else
                Text(t('本次核对已结束或已失效。', 'This review has finished or expired.')),
              FilledButton(
                onPressed: c.canAct && plan != null
                    ? () async {
                        await c.submit();
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    : null,
                child: Text(t('确认操作', 'Confirm')),
              ),
              OutlinedButton(
                onPressed: c.busy
                    ? null
                    : () {
                        c.cancelReview();
                        Navigator.of(context).pop();
                      },
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      );
    },
  );
}
