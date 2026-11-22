import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'admin_asset_models.dart';
import 'admin_asset_secure_window.dart';
import 'admin_assets_scope.dart';
import 'admin_docker_controller.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';
import 'admin_docker_forms.dart';
import 'admin_docker_logs_page.dart';
import 'admin_docker_terminal_access.dart';
import 'admin_docker_theme.dart';
import 'admin_docker_widgets.dart';
import 'admin_terminal_page.dart';

class AdminDockerPage extends StatefulWidget {
  const AdminDockerPage({
    super.key,
    required this.scope,
    required this.host,
    required this.onReturn,
    this.english = false,
    this.secureWindowFactory,
  });
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final VoidCallback onReturn;
  final bool english;
  final AdminAssetWindowGuard Function()? secureWindowFactory;
  @override
  State<AdminDockerPage> createState() => _AdminDockerPageState();
}

class _DockerRoutes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _retire(route);
  }

  void _retire(Route<dynamic> route) {
    if (route is TransitionRoute<dynamic>) {
      unawaited(route.completed.then((_) => routes.remove(route)));
    } else {
      routes.remove(route);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _retire(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (at >= 0) {
      if (newRoute == null) {
        routes.removeAt(at);
      } else {
        routes[at] = newRoute;
      }
    }
  }
}

class _AdminDockerPageState extends State<AdminDockerPage>
    with WidgetsBindingObserver {
  late final AdminDockerController c;
  late final AdminAssetWindowGuard secure;
  final query = TextEditingController(), revision = ValueNotifier<int>(0);
  final navigator = GlobalKey<NavigatorState>();
  final routeOwner = _DockerRoutes();
  bool ready = false,
      secureFailed = false,
      leaving = false,
      revoked = false,
      disposed = false;
  Future<void>? _retiring;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    c = widget.scope.own(
      AdminDockerController(AdminDockerRepository(widget.scope, widget.host)),
    );
    c.addListener(_changed);
    widget.scope.addListener(_scopeChanged);
    secure = widget.secureWindowFactory?.call() ?? AdminAssetSecureWindow();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await secure.acquire();
      if (!mounted || leaving) return;
      ready = true;
      _changed();
      if (c.phase != DockerPhase.background) await c.read();
    } catch (_) {
      if (mounted) {
        secureFailed = true;
        _changed();
      }
    }
  }

  void _changed() {
    if (mounted && !disposed) revision.value++;
  }

  void _scopeChanged() {
    if (!widget.scope.active && mounted) {
      revoked = true;
      _changed();
      unawaited(_dismissRoutes());
    }
  }

  Future<void> _dismissRoutes() async {
    // This navigator owns dropdowns and dialogs as well as pushed pages.
    final owned = routeOwner.routes.skip(1).toList().reversed.toList();
    for (final route in owned) {
      if (route.isActive && route.navigator?.mounted == true) {
        route.navigator?.removeRoute<dynamic>(route);
      }
    }
    await Future.wait(
      owned.whereType<TransitionRoute<dynamic>>().map(
        (route) => route.completed,
      ),
    );
  }

  Future<Object?> _push(WidgetBuilder builder) async {
    if (!mounted || leaving || !widget.scope.active) return null;
    final route = MaterialPageRoute<Object>(builder: builder);
    try {
      return await navigator.currentState!.push(route);
    } finally {
      await route.completed;
    }
  }

  void _pop([Object? value]) {
    final state = navigator.currentState;
    if (state != null && state.canPop()) state.pop(value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.resume();
      return;
    }
    c.background();
    query.clear();
    unawaited(_dismissRoutes());
  }

  Future<void> _back() async {
    if (navigator.currentState?.canPop() ?? false) {
      await navigator.currentState!.maybePop();
      return;
    }
    await _leave();
  }

  Future<void> _leave() async {
    if (leaving) return;
    leaving = true;
    _changed();
    c.background();
    query.clear();
    await _retire();
    if (mounted) widget.onReturn();
  }

  Future<void> _retire() => _retiring ??= _closeWindow();
  Future<void> _closeWindow() async {
    await _dismissRoutes();
    await WidgetsBinding.instance.endOfFrame;
    await secure.close();
  }

  Future<bool> _review(Future<DockerReview> Function() prepare) async {
    final plan = await c.review(prepare);
    if (plan == null || !mounted || leaving) return false;
    final result = await _push(
      (_) => DockerReviewPage(
        host: widget.host,
        review: plan,
        english: widget.english,
        onReturn: (value) => _pop(value),
        onConfirm: () async {
          await c.commit(plan);
        },
      ),
    );
    c.cancelReview();
    return result == true;
  }

  Future<void> _create() async {
    if (!c.canMutate) return;
    if (c.resource == DockerResource.containers) {
      await _push(
        (_) => DockerCreatePage(
          host: widget.host,
          english: widget.english,
          onReturn: _pop,
          onReview: (value) =>
              _review(() => c.repository.reviewContainerCreate(value)),
        ),
      );
    } else {
      final resource = c.resource;
      await _push(
        (_) => DockerNamedCreatePage(
          resource: resource,
          english: widget.english,
          onReturn: _pop,
          onReview: (name, driver) => _review(
            () => resource == DockerResource.images
                ? c.repository.reviewPull(name)
                : c.repository.reviewNamedCreate(resource, name, driver),
          ),
        ),
      );
    }
  }

  Future<Object?> _logs(DockerInspect info) => _push(
    (_) => AdminDockerLogsPage(
      scope: widget.scope,
      host: widget.host,
      container: info,
      credential: c.repository.reviewedCredential,
      english: widget.english,
      onReturn: _pop,
    ),
  );
  Future<Object?> _terminal(DockerInspect info) => _push(
    (_) => AdminDockerTheme(
      child: AdminTerminalPage(
        scope: widget.scope,
        host: widget.host,
        english: widget.english,
        onReturn: _pop,
        secureWindow: widget.secureWindowFactory?.call(),
        containerId: info.id,
        containerName: info.name,
        sessionAccess: DockerTerminalAccess(
          widget.scope,
          widget.host,
          info,
          credential: c.repository.reviewedCredential,
        ),
      ),
    ),
  );
  Future<void> _shortcut(DockerRecord row, {bool terminal = false}) async {
    final info = await c.inspect(row);
    if (info == null || !mounted || leaving) return;
    if (terminal) {
      if (info.running && c.canMutate) await _terminal(info);
    } else {
      await _logs(info);
    }
  }

  Future<void> _detail(DockerRecord row) async {
    final info = await c.inspect(row);
    if (info == null || !mounted || leaving) return;
    await _push(
      (_) => DockerDetailPage(
        controller: c,
        row: row,
        initial: info,
        english: widget.english,
        onReturn: _pop,
        onAction: (detail, action, policy) => _review(
          () => c.repository.reviewAction(
            row,
            action,
            baseline: detail,
            policy: policy,
          ),
        ),
        onLogs: _logs,
        onTerminal: _terminal,
      ),
    );
  }

  Future<void> _containerActions(DockerRecord row) async {
    if (!c.canMutate) return;
    final action = await _push(
      (_) => _DockerActionPage(
        title: row.name,
        english: widget.english,
        onReturn: _pop,
        actions: [
          for (final action in ['start', 'stop', 'restart', 'delete'])
            (
              action,
              dockerActionTitle(action, widget.english),
              !(action == 'delete' && row.status == 'running'),
            ),
        ],
      ),
    );
    if (action is String && c.canMutate) {
      await _review(() => c.repository.reviewAction(row, action));
    }
  }

  Future<void> _maintenance() async {
    if (!c.canMutate) return;
    final resource = c.resource;
    final action = await _push(
      (_) => _DockerActionPage(
        title: dockerResourceTitle(resource, widget.english),
        english: widget.english,
        onReturn: _pop,
        actions: [('prune', t('清理整台主机', 'Prune across host'), true)],
      ),
    );
    if (action == 'prune' && c.canMutate) {
      await _review(() => c.repository.reviewPrune(resource));
    }
  }

  Widget card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: dockerCard,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
  String get _failure => switch (c.failure) {
    DockerFailure.changed => t(
      '目标资料已变化，未提交。请重新读取并核对。',
      'Target metadata changed. Nothing was submitted. Read and review again.',
    ),
    DockerFailure.invalid => t(
      '配置或服务器数据无效，请重新核对。',
      'Invalid configuration or server data. Review again.',
    ),
    DockerFailure.refused => t(
      '服务器拒绝操作，请重新读取核对。',
      'The server refused the operation. Read and review again.',
    ),
    DockerFailure.unknown => t(
      '上次操作结果未确认',
      'Previous operation result unknown',
    ),
    _ => t('读取或连接失败，请手动重试。', 'Read or connection failed. Retry manually.'),
  };
  IconData icon(DockerResource resource) => switch (resource) {
    DockerResource.containers => Icons.view_in_ar_outlined,
    DockerResource.networks => Icons.hub_outlined,
    DockerResource.volumes => Icons.storage_outlined,
    DockerResource.images => Icons.layers_outlined,
  };
  void _selectResource(DockerResource resource) {
    if (!c.active || c.busy || leaving) return;
    query.clear();
    c.filter('');
    unawaited(c.read(resource));
  }

  Widget _tabs() => LayoutBuilder(
    builder: (context, size) {
      final large = MediaQuery.textScalerOf(context).scale(14) > 22;
      Widget tab(DockerResource resource) => Semantics(
        button: true,
        selected: c.resource == resource,
        enabled: !c.busy,
        label: dockerResourceTitle(resource, widget.english),
        onTap: c.busy ? null : () => _selectResource(resource),
        child: ExcludeSemantics(
          child: Material(
            color: Colors.white,
            child: InkWell(
              key: ValueKey('docker-resource-${resource.name}'),
              onTap: c.busy ? null : () => _selectResource(resource),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon(resource),
                      size: 24,
                      color: c.resource == resource ? dockerBlue : dockerInk,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dockerResourceTitle(resource, widget.english),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: c.resource == resource
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: c.resource == resource ? dockerBlue : dockerInk,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 2,
                      color: c.resource == resource
                          ? dockerBlue
                          : const Color(0xffe2e8f0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (large) {
        return Wrap(
          children: [
            for (final resource in DockerResource.values)
              SizedBox(width: size.maxWidth / 2, child: tab(resource)),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final resource in DockerResource.values)
            Expanded(child: tab(resource)),
        ],
      );
    },
  );
  String get createTitle => switch (c.resource) {
    DockerResource.containers => t('创建容器', 'Create container'),
    DockerResource.networks => t('创建网络', 'Create network'),
    DockerResource.volumes => t('创建数据卷', 'Create volume'),
    DockerResource.images => t('拉取镜像', 'Pull image'),
  };
  Widget _mainActions() => LayoutBuilder(
    builder: (context, size) {
      final create = FilledButton.icon(
        onPressed: c.canMutate ? _create : null,
        icon: const Icon(Icons.add),
        label: Text(createTitle, textAlign: TextAlign.center),
      );
      final read = OutlinedButton.icon(
        onPressed: c.busy ? null : () => unawaited(c.read()),
        icon: const Icon(Icons.refresh),
        label: Text(t('重新读取', 'Read again'), textAlign: TextAlign.center),
      );
      if (size.maxWidth < 330 ||
          MediaQuery.textScalerOf(context).scale(14) > 22) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [create, const SizedBox(height: 8), read],
        );
      }
      return Row(
        children: [
          Expanded(child: create),
          const SizedBox(width: 8),
          Expanded(child: read),
        ],
      );
    },
  );
  Widget _containerCard(DockerRecord row) {
    final style = OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: dockerInk,
      side: const BorderSide(color: Color(0xffd7e0e9)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
    final actions = <Widget>[
      OutlinedButton.icon(
        style: style,
        onPressed: c.busy ? null : () => unawaited(_detail(row)),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: Text(t('查看', 'View')),
      ),
      OutlinedButton.icon(
        style: style,
        onPressed: c.busy ? null : () => unawaited(_shortcut(row)),
        icon: const Icon(Icons.description_outlined, size: 18),
        label: Text(t('日志', 'Logs')),
      ),
      OutlinedButton.icon(
        style: style,
        onPressed: c.canMutate && row.status == 'running'
            ? () => unawaited(_shortcut(row, terminal: true))
            : null,
        icon: const Icon(Icons.terminal, size: 18),
        label: Text(t('终端', 'Terminal')),
      ),
      IconButton.filledTonal(
        onPressed: c.canMutate ? () => unawaited(_containerActions(row)) : null,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: dockerInk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        tooltip: t('容器操作', 'Container actions'),
        icon: const Icon(Icons.more_vert),
      ),
    ];
    return card([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.view_in_ar_outlined, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          DockerStatusBadge(status: row.status, english: widget.english),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        t('镜像：', 'Image: ') + row.image,
        style: const TextStyle(fontSize: 14),
      ),
      if ((row.fields['ports'] as String? ?? '').isNotEmpty)
        Text(
          t('端口：', 'Ports: ') +
              (row.fields['ports'] as String).replaceAll('->', ' → '),
          style: const TextStyle(fontSize: 14),
        ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, size) {
          if (MediaQuery.textScalerOf(context).scale(14) > 22 ||
              size.maxWidth < 290 ||
              (widget.english && size.maxWidth < 380)) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  SizedBox(width: (size.maxWidth - 8) / 2, child: action),
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(child: actions[i]),
                const SizedBox(width: 6),
              ],
              SizedBox(width: 48, height: 48, child: actions.last),
            ],
          );
        },
      ),
    ]);
  }

  Widget _resourceCard(DockerRecord row) => card([
    Row(
      children: [
        Icon(icon(row.resource), size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            row.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    if (row.id.isNotEmpty)
      Text(
        row.id,
        style: const TextStyle(color: Color(0xff64748b), fontSize: 13),
      ),
    for (final key in switch (row.resource) {
      DockerResource.networks => ['driver', 'scope'],
      DockerResource.volumes => [
        'driver',
        'scope',
        'mountpoint',
        'size',
        'created_at',
      ],
      _ => ['size', 'created_since', 'created_at'],
    })
      if ((row.fields[key] as String? ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${dockerFieldTitle(key, widget.english)} · ${row.fields[key]}',
          ),
        ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: c.canMutate
          ? () => unawaited(
              _review(() => c.repository.reviewAction(row, 'delete')),
            )
          : null,
      icon: const Icon(Icons.delete_outline),
      label: Text(t('删除', 'Delete')),
    ),
  ]);
  Widget _home(BuildContext context) {
    final hidden = leaving || revoked;
    final receipt = c.receiptSummary;
    return AdminDockerScaffold(
      appBar: AppBar(
        title: Text(t('Docker 管理', 'Docker management')),
        leading: IconButton(
          onPressed: () => unawaited(_leave()),
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (ready && !hidden)
            IconButton(
              onPressed: c.canMutate ? () => unawaited(_maintenance()) : null,
              tooltip: t('资源维护', 'Resource actions'),
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      body: SafeArea(
        child: hidden
            ? Center(
                child: Text(
                  revoked ? t('管理员会话已失效', 'Administrator session expired') : '',
                ),
              )
            : !ready
            ? Center(
                child: Text(
                  secureFailed
                      ? t(
                          '无法启用安全窗口，页面未开启。',
                          'Secure window unavailable. Page remains closed.',
                        )
                      : t('正在准备', 'Preparing'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DockerTargetStrip(
                    title: 'SSH #${widget.host.id} · ${widget.host.name}',
                  ),
                  const SizedBox(height: 12),
                  _tabs(),
                  const SizedBox(height: 16),
                  _mainActions(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: query,
                    onChanged: c.filter,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      labelText: t(
                        '搜索已读取的${dockerResourceTitle(c.resource, false)}',
                        'Search loaded ${dockerResourceTitle(c.resource, true).toLowerCase()}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (c.busy) const LinearProgressIndicator(),
                  if (c.receipt)
                    card([
                      Text(
                        t('已收到服务器确认。', 'Server confirmation received.'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (receipt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${dockerResourceTitle(receipt.resource, widget.english)} · ${dockerActionTitle(receipt.action, widget.english)}',
                        ),
                        if (receipt.name.isNotEmpty) Text(receipt.name),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        t(
                          '下方仍为已读快照，可明确重新读取核对。',
                          'The list below is a read snapshot. Read again to verify.',
                        ),
                      ),
                    ]),
                  if (c.failure != null) card([Text(_failure)]),
                  if (c.unknown)
                    card([
                      Text(
                        t('上次操作结果未确认', 'Previous operation result unknown'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(
                          '先读取当前状态，不重发操作；观察结果不等于提交回执。',
                          'Observe the current state without replaying. An observation is not a submission receipt.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: c.busy ? null : () => unawaited(c.observe()),
                        child: Text(t('只读核对当前状态', 'Observe current state')),
                      ),
                      if (c.observation != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${t('当前观察', 'Current observation')} · ${c.observation!.rows.length}',
                        ),
                        for (final row in c.observation!.rows) Text(row.name),
                        if (c.observation!.container != null) ...[
                          Text(c.observation!.container!.id),
                          Text(
                            dockerStatusTitle(
                              c.observation!.container!.status,
                              widget.english,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: c.finishObservation,
                          child: Text(t('结束本次核对', 'Finish this review')),
                        ),
                      ],
                    ]),
                  if (c.phase == DockerPhase.idle)
                    Text(
                      t(
                        '点击重新读取；返回前台不会自动连接。',
                        'Choose Read again. Returning to foreground never connects automatically.',
                      ),
                    ),
                  if (c.phase == DockerPhase.ready && c.rows.isEmpty)
                    Text(t('当前资源列表为空', 'This resource list is empty')),
                  if (c.rows.isNotEmpty && c.filtered.isEmpty)
                    Text(
                      t('没有符合当前筛选的条目', 'No loaded entries match this filter'),
                    ),
                  for (final row in c.filtered)
                    row.resource == DockerResource.containers
                        ? _containerCard(row)
                        : _resourceCard(row),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: HeroControllerScope.none(
      child: Navigator(
        key: navigator,
        observers: [routeOwner],
        onGenerateRoute: (_) => MaterialPageRoute<Object>(
          builder: (context) => ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, _, child) => _home(context),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.scope.removeListener(_scopeChanged);
    c.removeListener(_changed);
    widget.scope.release(c);
    query.dispose();
    revision.dispose();
    unawaited(_retire());
    super.dispose();
  }
}

class _DockerActionPage extends StatelessWidget {
  const _DockerActionPage({
    required this.title,
    required this.actions,
    required this.onReturn,
    required this.english,
  });
  final String title;
  final List<(String, String, bool)> actions;
  final void Function([Object?]) onReturn;
  final bool english;
  @override
  Widget build(BuildContext context) => AdminDockerScaffold(
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        onPressed: onReturn,
        tooltip: english ? 'Back' : '返回',
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                onPressed: action.$3 ? () => onReturn(action.$1) : null,
                child: Text(action.$2),
              ),
            ),
        ],
      ),
    ),
  );
}

class DockerDetailPage extends StatefulWidget {
  const DockerDetailPage({
    super.key,
    required this.controller,
    required this.row,
    required this.initial,
    required this.onReturn,
    required this.onAction,
    required this.onLogs,
    required this.onTerminal,
    this.english = false,
  });
  final AdminDockerController controller;
  final DockerRecord row;
  final DockerInspect initial;
  final VoidCallback onReturn;
  final Future<bool> Function(DockerInspect, String, String?) onAction;
  final Future<Object?> Function(DockerInspect) onLogs, onTerminal;
  final bool english;
  @override
  State<DockerDetailPage> createState() => _DockerDetailState();
}

class _DockerDetailState extends State<DockerDetailPage> {
  late DockerInspect info = widget.initial;
  bool showCommand = false, editPolicy = false;
  String policy = 'no';
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    policy = dockerPolicies.contains(info.policy) ? info.policy : 'no';
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    final result = await widget.controller.inspect(widget.row);
    if (mounted && result != null) {
      setState(() {
        info = result;
        policy = dockerPolicies.contains(result.policy) ? result.policy : 'no';
        showCommand = false;
        editPolicy = false;
      });
    }
  }

  Future<void> copyId() async {
    try {
      await Clipboard.setData(ClipboardData(text: info.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    Widget action(String name, IconData icon, {bool primary = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: primary
              ? FilledButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => unawaited(widget.onLogs(info)),
                  icon: Icon(icon),
                  label: Text(t('查看日志', 'View logs')),
                )
              : OutlinedButton.icon(
                  onPressed: c.canMutate
                      ? () => unawaited(widget.onAction(info, name, null))
                      : null,
                  icon: Icon(icon),
                  label: Text(dockerActionTitle(name, widget.english)),
                ),
        );
    return AdminDockerScaffold(
      appBar: AppBar(
        title: Text(t('容器详情', 'Container details')),
        leading: IconButton(
          onPressed: widget.onReturn,
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: c.busy ? null : refresh,
            tooltip: t('重新读取详情', 'Read details again'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.view_in_ar_outlined, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    info.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DockerStatusBadge(
                  status: info.status,
                  english: widget.english,
                  solid: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            DockerInfoCard(
              children: [
                DockerMetadataRow(
                  icon: Icons.fingerprint,
                  label: t('容器 ID', 'Container ID'),
                  value:
                      '${info.id.substring(0, 6)}…${info.id.substring(info.id.length - 4)}',
                  trailing: IconButton(
                    onPressed: copyId,
                    tooltip: t('复制完整ID', 'Copy full ID'),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                ),
                DockerMetadataRow(
                  icon: Icons.layers_outlined,
                  label: t('镜像', 'Image'),
                  value: info.image,
                ),
                DockerMetadataRow(
                  icon: Icons.hub_outlined,
                  label: t('IP 地址', 'IP address'),
                  value: info.fields['ip_address'] as String,
                ),
                DockerMetadataRow(
                  icon: Icons.sync,
                  label: t('重启策略', 'Restart policy'),
                  value: info.policy,
                ),
                DockerMetadataRow(
                  icon: Icons.calendar_today_outlined,
                  label: t('创建时间', 'Created'),
                  value: dockerTimeLabel(info.fields['created'] as String),
                ),
                DockerMetadataRow(
                  icon: Icons.play_arrow_outlined,
                  label: t('启动时间', 'Started'),
                  value: dockerTimeLabel(info.fields['started_at'] as String),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '上次读取的详情；操作后可明确重新读取核对。',
                'Last-read details. Read again explicitly after an operation.',
              ),
              style: const TextStyle(color: Color(0xff64748b), fontSize: 13),
            ),
            if (c.receipt &&
                c.receiptSummary?.resource == DockerResource.containers &&
                c.receiptSummary?.target == info.id) ...[
              const SizedBox(height: 8),
              Text(
                t(
                  '服务器已确认操作；请重新读取详情。',
                  'The server confirmed the operation. Read the details again.',
                ),
              ),
            ],
            if (c.failure != null) ...[
              const SizedBox(height: 8),
              Text(
                t(
                  '核对或操作未完成，请返回查看状态或重新读取。',
                  'Review or operation did not complete. Return to view its state or read again.',
                ),
              ),
            ],
            if (c.unknown) ...[
              const SizedBox(height: 8),
              Text(
                t(
                  '操作结果未确认，请返回只读核对。',
                  'Result unknown. Return to observe without replaying.',
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: c.canMutate
                  ? () => setState(() => editPolicy = !editPolicy)
                  : null,
              icon: const Icon(Icons.settings_outlined),
              label: Text(t('修改重启策略', 'Change restart policy')),
            ),
            if (editPolicy) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: policy,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t('重启策略', 'Restart policy'),
                ),
                items: [
                  for (final p in dockerPolicies)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: c.canMutate
                    ? (value) => setState(() => policy = value ?? 'no')
                    : null,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: c.canMutate
                    ? () => unawaited(
                        widget.onAction(info, 'restart-policy', policy),
                      )
                    : null,
                child: Text(t('核对策略更改', 'Review policy change')),
              ),
            ],
            const SizedBox(height: 12),
            action(
              info.running ? 'stop' : 'start',
              info.running
                  ? Icons.stop_circle_outlined
                  : Icons.play_arrow_outlined,
            ),
            action('restart', Icons.refresh),
            action('logs', Icons.description_outlined, primary: true),
            OutlinedButton.icon(
              onPressed: c.canMutate && info.running
                  ? () => unawaited(widget.onTerminal(info))
                  : null,
              icon: const Icon(Icons.terminal),
              label: Text(t('容器终端', 'Container terminal')),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xff64748b),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.running
                        ? t(
                            '删除前请先停止容器。',
                            'Stop the container before deleting it.',
                          )
                        : t(
                            '容器已停止；删除不提供撤销。',
                            'Container stopped. Deletion has no undo.',
                          ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xff64748b),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: c.canMutate && !info.running
                  ? () => unawaited(widget.onAction(info, 'delete', null))
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(t('删除容器', 'Delete container')),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xffbf2637),
              ),
            ),
            ExpansionTile(
              title: Text(t('更多详情', 'More details')),
              children: [
                DockerMetadataRow(
                  icon: Icons.fingerprint,
                  label: t('完整 ID', 'Full ID'),
                  value: info.id,
                  selectable: true,
                ),
                DockerMetadataRow(
                  icon: Icons.dns_outlined,
                  label: t('主机名', 'Hostname'),
                  value: info.fields['hostname'] as String,
                ),
                DockerMetadataRow(
                  icon: Icons.stop_circle_outlined,
                  label: t('退出码', 'Exit code'),
                  value: info.fields['exit_code'].toString(),
                ),
                DockerMetadataRow(
                  icon: Icons.schedule,
                  label: t('结束时间', 'Finished'),
                  value: dockerTimeLabel(info.fields['finished_at'] as String),
                ),
                TextButton(
                  onPressed: () => setState(() => showCommand = !showCommand),
                  child: Text(
                    showCommand
                        ? t('隐藏命令', 'Hide command')
                        : t('查看命令', 'Show command'),
                  ),
                ),
                if (showCommand)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      (info.fields['command'] as List).join('\n'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
}
