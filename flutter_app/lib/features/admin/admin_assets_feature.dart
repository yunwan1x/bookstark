import '../../core/webdav_password_repository.dart';
import '../credentials/webdav_password_page.dart';
import 'admin_remote_dav_page.dart';
import 'admin_asset_secure_window.dart';
import 'admin_terminal_page.dart';
import 'admin_files_page.dart';
import 'admin_docker_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_asset_credential_editor_page.dart';
import 'admin_asset_delete_page.dart';
import 'admin_asset_host_detail_page.dart';
import 'admin_asset_host_editor_page.dart';
import 'admin_asset_migration_page.dart';
import 'admin_asset_private_key_page.dart';
import 'admin_asset_secret_page.dart';
import 'admin_asset_settings_page.dart';
import 'admin_assets_catalog_page.dart';
import 'admin_assets_controller.dart';
import 'admin_assets_repository.dart';
import 'admin_assets_scope.dart';

/// Every child route belongs to the same server/session/administrator scope.
class AdminAssetsFeature extends StatefulWidget {
  const AdminAssetsFeature({
    super.key,
    required this.scope,
    required this.onReturn,
    this.english = false,
    this.controller,
    this.secureWindowFactory,
  });
  final AdminAssetsScope scope;
  final VoidCallback onReturn;
  final bool english;
  final AdminAssetsController? controller;
  final AdminAssetWindowGuard Function()? secureWindowFactory;
  @override
  State<AdminAssetsFeature> createState() => _AssetsFeatureState();
}

class _AssetsFeatureState extends State<AdminAssetsFeature>
    with WidgetsBindingObserver {
  var _navigator = GlobalKey<NavigatorState>();
  final _routeChanges = ValueNotifier<int>(0);
  AdminAssetsController? _controller;
  AdminAssetCatalog _catalog = AdminAssetCatalog.hosts;
  bool _opening = false, _retiring = false;
  AdminAssetsController get c => _controller!;
  AdminAssetsScope get scope => widget.scope;
  String t(String zh, String en) => widget.english ? en : zh;
  bool _guard() => mounted && scope.guard() && _controller != null && !c.closed;
  bool _held(
    AdminAssetsScope heldScope,
    AdminAssetsController heldController,
  ) =>
      mounted &&
      identical(scope, heldScope) &&
      identical(_controller, heldController) &&
      _guard();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _install();
  }

  void _install() {
    scope.addListener(_scopeChanged);
    if (!scope.guard() || scope.owner.role != 0) {
      scope.close();
      return;
    }
    final controller =
        widget.controller ??
        AdminAssetsController(AdminAssetsRepository(scope.client), scope.owner);
    if (!identical(controller.repository.client, scope.client) ||
        !controller.owner.sameAs(scope.owner)) {
      controller.dispose();
      throw StateError('Asset feature owner/client mismatch');
    }
    _controller = scope.own(controller);
    c.addListener(_changed);
    unawaited(c.load(_catalog));
  }

  void _remove(AdminAssetsScope old) {
    old.removeListener(_scopeChanged);
    _controller?.removeListener(_changed);
    old.release(_controller);
    _controller = null;
  }

  @override
  void didUpdateWidget(covariant AdminAssetsFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != scope || oldWidget.controller != widget.controller) {
      _remove(oldWidget.scope);
      _navigator = GlobalKey<NavigatorState>();
      _catalog = AdminAssetCatalog.hosts;
      _opening = false;
      _retiring = false;
      _install();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (c.closed && !_retiring) {
      _retiring = true;
      final held = scope;
      scheduleMicrotask(() {
        if (mounted && identical(scope, held)) {
          held.close();
          if (mounted) {
            setState(() {
              _navigator = GlobalKey<NavigatorState>();
            });
          }
        }
      });
    }
    setState(() {});
  }

  void _scopeChanged() {
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _navigator = GlobalKey<NavigatorState>();
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.background();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remove(scope);
    _routeChanges.dispose();
    super.dispose();
  }

  void _pop() {
    if (_navigator.currentState?.canPop() ?? false) {
      _navigator.currentState!.pop();
    }
  }

  Future<void> _push(WidgetBuilder builder) async {
    if (!_guard()) return;
    await _navigator.currentState?.push<void>(
      MaterialPageRoute(builder: builder),
    );
  }

  Future<void> _webdav() async {
    if (!_guard() || !c.canWrite) return;
    c.background();
    await _push(
      (_) => AdminDavPage(
        scope: scope,
        secureWindowFactory: widget.secureWindowFactory,
        english: widget.english,
        onReturn: _pop,
        onBuiltin: () {
          if (!_guard()) return;
          unawaited(
            _push(
              (_) => WebdavPasswordPage(
                repository: RemoteWebdavPasswordRepository(
                  scope.client,
                  memberId: scope.owner.memberId,
                ),
                english: widget.english,
              ),
            ),
          );
        },
      ),
    );
  }

  void _toCatalog(AdminAssetCatalog kind, {bool read = false}) {
    if (!_guard()) return;
    c.background();
    _navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _catalog = kind;
    });
    _routeChanges.value++;
    if (read) unawaited(c.load(kind));
  }

  void _failure(String message, Future<void> Function() retry) {
    unawaited(
      _push(
        (_) => Scaffold(
          appBar: AppBar(
            title: Text(t('读取资产资料', 'Read asset data')),
            leading: IconButton(
              onPressed: _pop,
              tooltip: t('返回', 'Back'),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      _pop();
                      unawaited(retry());
                    },
                    child: Text(t('重试', 'Retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectCatalog(AdminAssetCatalog kind) {
    if (!_guard() ||
        _opening ||
        c.operation == AdminAssetOperationState.submitting) {
      return;
    }
    setState(() {
      _catalog = kind;
    });
    _routeChanges.value++;
    unawaited(c.load(kind));
  }

  Future<void> _credentialEditor({
    AdminAssetCredentialMetadata? initial,
    bool returnToHost = false,
  }) async {
    if (!_guard() || _opening || !c.canWrite || c.migrationPartial) return;
    _opening = true;
    final heldScope = scope, heldController = c;
    try {
      if (!await c.load(AdminAssetCatalog.credentials) ||
          !_held(heldScope, heldController)) {
        if (_held(heldScope, heldController)) {
          _failure(
            t('凭据读取失败，请重试。', 'Could not read credentials. Try again.'),
            () =>
                _credentialEditor(initial: initial, returnToHost: returnToHost),
          );
        }
        return;
      }
      AdminAssetCredentialMetadata? current;
      if (initial != null) {
        for (final row in c.credentials!) {
          if (row.id == initial.id) current = row;
        }
        if (current == null) {
          _failure(
            t(
              '该凭据已不存在，请重新读取。',
              'This credential no longer exists. Read again.',
            ),
            () async {
              _toCatalog(AdminAssetCatalog.credentials, read: true);
            },
          );
          return;
        }
      }
      final baseline = current;
      unawaited(
        _push(
          (_) => AdminAssetCredentialEditorPage(
            secureWindow: widget.secureWindowFactory?.call(),
            initial: baseline,
            english: widget.english,
            onReturn: _pop,
            onEditPrivateKey: (apply) {
              unawaited(
                _push(
                  (_) => AdminAssetPrivateKeyPage(
                    secureWindow: widget.secureWindowFactory?.call(),
                    english: widget.english,
                    onReturn: _pop,
                    onApply: (value) {
                      if (_guard()) {
                        apply(value);
                        _pop();
                      }
                    },
                  ),
                ),
              );
            },
            onSave: (draft, replacement, onSubmitted) async {
              if (!_held(heldScope, heldController) || !c.canWrite) {
                return false;
              }
              final saved = baseline == null
                  ? replacement != null &&
                        await c.createCredential(
                          draft,
                          replacement,
                          onSubmitted: onSubmitted,
                        )
                  : await c.updateCredential(
                      baseline,
                      draft,
                      replacement: replacement,
                      onSubmitted: onSubmitted,
                    );
              if (!_held(heldScope, heldController)) return false;
              if (saved && returnToHost) {
                _pop();
                await c.load(AdminAssetCatalog.credentials);
                if (_held(heldScope, heldController)) {
                  await c.load(AdminAssetCatalog.hosts);
                }
              } else {
                _toCatalog(AdminAssetCatalog.credentials, read: saved);
              }
              return saved;
            },
          ),
        ),
      );
    } finally {
      if (mounted && identical(scope, heldScope)) _opening = false;
    }
  }

  Future<void> _hostEditor([AdminAssetHostMetadata? initial]) async {
    if (!_guard() || _opening || !c.canWrite || c.migrationPartial) return;
    _opening = true;
    final heldScope = scope, heldController = c;
    try {
      if (!await c.load(AdminAssetCatalog.credentials) ||
          !_held(heldScope, heldController)) {
        if (_held(heldScope, heldController)) {
          _failure(
            t('凭据读取失败，请重试。', 'Could not read credentials. Try again.'),
            () => _hostEditor(initial),
          );
        }
        return;
      }
      unawaited(
        _push(
          (_) => AnimatedBuilder(
            animation: heldController,
            builder: (context, _) => AdminAssetHostEditorPage(
              initial: initial,
              credentials: heldController.credentials ?? const [],
              english: widget.english,
              onReturn: _pop,
              onNewCredential: () =>
                  unawaited(_credentialEditor(returnToHost: true)),
              onSave: (draft, chosen) async {
                if (!_held(heldScope, heldController) || !c.canWrite) {
                  return false;
                }
                final saved = initial == null
                    ? chosen != null && await c.createHost(draft, chosen)
                    : await c.updateHost(initial, draft, chosen: chosen);
                if (_held(heldScope, heldController)) {
                  _toCatalog(AdminAssetCatalog.hosts, read: saved);
                }
                return saved;
              },
            ),
          ),
        ),
      );
    } finally {
      if (mounted && identical(scope, heldScope)) _opening = false;
    }
  }

  void _host(AdminAssetHostMetadata baseline) {
    if (!_guard() || _opening) return;
    unawaited(
      _push(
        (_) => AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            AdminAssetHostMetadata? current;
            for (final row in c.hosts ?? const <AdminAssetHostMetadata>[]) {
              if (row.id == baseline.id) current = row;
            }
            final shown = current ?? baseline;
            final reviewed =
                c.repository.reviewedHosts?.any(
                  (row) =>
                      row.id == shown.id &&
                      row.reviewFingerprint == shown.reviewFingerprint,
                ) ??
                false;
            if (current == null &&
                c.loadState(AdminAssetCatalog.hosts) ==
                    AdminAssetLoadState.ready) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(t('SSH 主机详情', 'SSH host details')),
                  leading: IconButton(
                    onPressed: _pop,
                    tooltip: t('返回', 'Back'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t(
                            '该主机已不在当前资料中，请返回刷新列表。',
                            'This host is absent from current data. Return and refresh the list.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () =>
                              _toCatalog(AdminAssetCatalog.hosts, read: true),
                          child: Text(t('返回主机列表', 'Return to host list')),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return AdminAssetHostDetailPage(
              host: shown,
              staleSnapshot: !reviewed,
              english: widget.english,
              enabled: c.canWrite && reviewed,
              busy: c.operation == AdminAssetOperationState.submitting,
              receipt: c.testedHostId == shown.id ? c.connectionReceipt : null,
              onReturn: _pop,
              onRefresh: () => unawaited(c.load(AdminAssetCatalog.hosts)),
              onEdit: () => unawaited(_hostEditor(shown)),
              onTest: () => unawaited(c.testHost(shown)),
              onTerminal: () {
                if (!_guard() || !c.canWrite || !reviewed) return;
                unawaited(
                  _push(
                    (_) => AdminTerminalPage(
                      scope: scope,
                      host: shown,
                      english: widget.english,
                      secureWindow: widget.secureWindowFactory?.call(),
                      onReturn: _pop,
                    ),
                  ),
                );
              },
              onFiles: () {
                if (!_guard() || !c.canWrite || !reviewed) return;
                unawaited(
                  _push(
                    (_) => AdminFilesPage(
                      scope: scope,
                      host: shown,
                      english: widget.english,
                      secureWindow: widget.secureWindowFactory?.call(),
                      onReturn: _pop,
                    ),
                  ),
                );
              },
              onDocker: () {
                if (!_guard() || !c.canWrite || !reviewed) return;
                unawaited(
                  _push(
                    (_) => AdminDockerPage(
                      scope: scope,
                      host: shown,
                      english: widget.english,
                      secureWindowFactory: widget.secureWindowFactory,
                      onReturn: _pop,
                    ),
                  ),
                );
              },
              onDelete: () => _delete(host: shown),
              onMigrate: () {
                if (!_guard() || !c.canWrite || c.migrationPartial) return;
                unawaited(
                  _push(
                    (_) => AdminAssetMigrationPage(
                      controller: c,
                      host: shown,
                      english: widget.english,
                      onReturn: () => _toCatalog(AdminAssetCatalog.hosts),
                      onBound: () =>
                          _toCatalog(AdminAssetCatalog.hosts, read: true),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _delete({
    AdminAssetHostMetadata? host,
    AdminAssetCredentialMetadata? credential,
  }) {
    if (!_guard() || !c.canWrite) return;
    final heldScope = scope, heldController = c;
    unawaited(
      _push(
        (_) => AdminAssetDeletePage(
          host: host,
          credential: credential,
          english: widget.english,
          onCancel: _pop,
          onConfirm: () async {
            if (!_held(heldScope, heldController) || !c.canWrite) return;
            final saved = host != null
                ? await c.deleteHost(host)
                : await c.deleteCredential(credential!);
            if (_held(heldScope, heldController)) {
              _toCatalog(
                host != null
                    ? AdminAssetCatalog.hosts
                    : AdminAssetCatalog.credentials,
                read: saved,
              );
            }
          },
        ),
      ),
    );
  }

  void _revealCredential(AdminAssetCredentialMetadata row) {
    if (!_guard()) return;
    final heldScope = scope, heldController = c;
    unawaited(
      _push(
        (_) => AdminAssetSecretPage(
          secureWindow: widget.secureWindowFactory?.call(),
          title: t('查看凭据', 'View credential'),
          english: widget.english,
          details: [
            ('ID', row.id.toString()),
            (t('名称', 'Name'), row.name),
            (t('用户名', 'Username'), row.username),
          ],
          onReturn: _pop,
          onHide: heldController.repository.closeSecrets,
          onReveal: () {
            if (!_held(heldScope, heldController)) throw AdminAssetOwnerLost();
            return heldController.revealCredential(row);
          },
        ),
      ),
    );
  }

  Future<void> _settings() async {
    if (!_guard() || _opening) return;
    _opening = true;
    final heldScope = scope, heldController = c;
    try {
      if (!await c.load(AdminAssetCatalog.settings) ||
          !_held(heldScope, heldController)) {
        if (_held(heldScope, heldController)) {
          _failure(
            t('资产设置读取失败，请重试。', 'Could not read asset settings. Try again.'),
            _settings,
          );
        }
        return;
      }
      final baseline = c.settings!;
      unawaited(
        _push(
          (_) => AdminAssetSettingsPage(
            secureWindow: widget.secureWindowFactory?.call(),
            controller: c,
            initial: baseline,
            english: widget.english,
            onReturn: _pop,
            onSaved: () => _toCatalog(_catalog),
            onMigrate: () => _toCatalog(AdminAssetCatalog.hosts, read: true),
            onRevealKey: () {
              unawaited(
                _push(
                  (_) => AdminAssetSecretPage(
                    secureWindow: widget.secureWindowFactory?.call(),
                    title: t('查看当前密钥', 'View current key'),
                    english: widget.english,
                    details: [
                      (
                        t('凭据加密', 'Credential encryption'),
                        baseline.encryptionEnabled
                            ? t('已启用', 'Enabled')
                            : t('未启用', 'Disabled'),
                      ),
                    ],
                    onReturn: _pop,
                    onHide: heldController.repository.closeSecrets,
                    onReveal: () {
                      if (!_held(heldScope, heldController)) {
                        throw AdminAssetOwnerLost();
                      }
                      return heldController.revealSettingsKey(baseline);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted && identical(scope, heldScope)) _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!scope.active || _controller == null || c.closed) {
      return Scaffold(
        appBar: AppBar(title: Text(t('资产管理', 'Asset management'))),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    '管理员会话已失效，请返回重新登录。',
                    'The administrator session is no longer valid. Return and sign in again.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.onReturn,
                  child: Text(t('返回', 'Back')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Navigator(
      key: _navigator,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _routeChanges,
          builder: (context, revision, child) => AdminAssetsCatalogPage(
            controller: c,
            catalog: _catalog,
            english: widget.english,
            onReturn: () {
              c.background();
              widget.onReturn();
            },
            onSettings: () => unawaited(_settings()),
            onWebdav: () => unawaited(_webdav()),
            onCatalog: _selectCatalog,
            onCreate: () => _catalog == AdminAssetCatalog.hosts
                ? unawaited(_hostEditor())
                : unawaited(_credentialEditor()),
            onHost: _host,
            onCredential: (row) => unawaited(_credentialEditor(initial: row)),
            onRevealCredential: _revealCredential,
            onDeleteCredential: (row) => _delete(credential: row),
          ),
        ),
      ),
    );
  }
}
