import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_assets_scope.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';
import 'admin_docker_logs_controller.dart';
import 'admin_docker_theme.dart';
import 'admin_docker_widgets.dart';

class AdminDockerLogsPage extends StatefulWidget {
  const AdminDockerLogsPage({
    super.key,
    required this.scope,
    required this.host,
    required this.container,
    required this.onReturn,
    this.credential,
    this.english = false,
  });
  final AdminAssetsScope scope;
  final AdminAssetHostMetadata host;
  final DockerInspect container;
  final AdminAssetCredentialMetadata? credential;
  final VoidCallback onReturn;
  final bool english;
  @override
  State<AdminDockerLogsPage> createState() => _DockerLogsPageState();
}

class _DockerLogsPageState extends State<AdminDockerLogsPage>
    with WidgetsBindingObserver {
  late final AdminDockerLogsController c;
  final tail = TextEditingController(text: '200'), scroll = ScrollController();
  bool autoScroll = true;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = widget.scope.own(
      AdminDockerLogsController(
        AdminDockerRepository(
          widget.scope,
          widget.host,
          credential: widget.credential,
        ),
        widget.container,
      ),
    );
    c.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.resume();
    } else {
      c.background();
    }
  }

  int? _tail() {
    final n = int.tryParse(tail.text);
    return n != null && n >= 1 && n <= 10000 ? n : null;
  }

  String get _status => switch (c.phase) {
    DockerLogsPhase.idle => t('未读取；选择读取或跟随', 'Not loaded. Read or follow.'),
    DockerLogsPhase.checking => t('正在核对目标', 'Verifying target'),
    DockerLogsPhase.connecting => t('正在等待日志', 'Waiting for log data'),
    DockerLogsPhase.receiving => t('正在接收日志', 'Receiving logs'),
    DockerLogsPhase.snapshot => t('本次日志快照', 'Current log snapshot'),
    DockerLogsPhase.stopped => t('跟随已停止', 'Following stopped'),
    DockerLogsPhase.failed => t(
      '日志读取失败，请返回核对目标后重试。',
      'Logs unavailable. Return and verify the target before retrying.',
    ),
    DockerLogsPhase.background => t(
      '后台已清空；返回后手动读取',
      'Cleared in background. Read again manually.',
    ),
    DockerLogsPhase.revoked => t('管理员会话已失效', 'Administrator session expired'),
  };
  String get _badge => switch (c.phase) {
    DockerLogsPhase.receiving => t('跟随中', 'Following'),
    DockerLogsPhase.connecting => t('等待日志', 'Waiting'),
    DockerLogsPhase.checking => t('核对中', 'Checking'),
    DockerLogsPhase.snapshot => t('本次快照', 'Snapshot'),
    DockerLogsPhase.stopped => t('已停止', 'Stopped'),
    DockerLogsPhase.failed => t('读取失败', 'Read failed'),
    DockerLogsPhase.background => t('已清空', 'Cleared'),
    DockerLogsPhase.revoked => t('会话失效', 'Expired'),
    DockerLogsPhase.idle => t('未读取', 'Not loaded'),
  };
  Widget _toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(14) > 22;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: large
                    ? (constraints.maxWidth < 230 ? constraints.maxWidth : 230)
                    : 130,
                child: DropdownButtonFormField<int>(
                  initialValue: 200,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  items: [100, 200, 500, 1000, 10000]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(
                            t('最近$n行', 'Last $n lines'),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: c.following
                      ? null
                      : (value) {
                          if (value != null) tail.text = '$value';
                        },
                ),
              ),
              Semantics(
                key: const ValueKey('docker-logs-status'),
                label: _status,
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.phase == DockerLogsPhase.receiving
                        ? const Color(0xffd9f5dc)
                        : const Color(0xffe1e5e9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _badge,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.phase == DockerLogsPhase.receiving
                          ? const Color(0xff267c30)
                          : const Color(0xff4b5563),
                    ),
                  ),
                ),
              ),
              if (c.following)
                OutlinedButton.icon(
                  onPressed: c.stop,
                  icon: const Icon(Icons.stop_outlined, size: 18),
                  label: Text(t('停止跟随', 'Stop following')),
                ),
            ],
          ),
          if (!c.following) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    final n = _tail();
                    if (n != null) unawaited(c.snapshot(n));
                  },
                  child: Text(t('读取快照', 'Read snapshot')),
                ),
                FilledButton(
                  onPressed: () {
                    final n = _tail();
                    if (n != null) unawaited(c.follow(n));
                  },
                  child: Text(t('跟随日志', 'Follow logs')),
                ),
              ],
            ),
          ],
          if ({
            DockerLogsPhase.failed,
            DockerLogsPhase.background,
            DockerLogsPhase.revoked,
          }.contains(c.phase)) ...[
            const SizedBox(height: 8),
            Text(_status),
          ],
          if (c.truncated)
            Text(t('仅保留最近1 MiB显示。', 'Only the latest 1 MiB remains.')),
          if (c.containsReplacement)
            Text(
              t(
                '服务端日志含替换字符，部分字符可能已丢失。请停止跟随后读取快照核对。',
                'Server logs contain replacement characters. Stop following and read a snapshot to verify.',
              ),
            ),
        ],
      );
    },
  );
  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final toggle = SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: autoScroll,
          onChanged: (value) => setState(() => autoScroll = value),
          title: Text(t('自动滚动', 'Auto scroll')),
        );
        final clear = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: c.clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t('清空显示', 'Clear display')),
            ),
            Text(
              t('仅清空当前显示。', 'Clears this view only.'),
              style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
            ),
          ],
        );
        if (constraints.maxWidth < 360 &&
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toggle,
              Align(alignment: Alignment.centerRight, child: clear),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: toggle),
            const SizedBox(width: 8),
            clear,
          ],
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => AdminDockerScaffold(
    appBar: AppBar(
      title: Text(t('容器日志', 'Container logs')),
      leading: IconButton(
        onPressed: widget.onReturn,
        tooltip: t('返回', 'Back'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    (MediaQuery.sizeOf(context).width < 360 &&
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? .38
                        : .52),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DockerTargetStrip(
                      title:
                          '${widget.container.name} · SSH #${widget.host.id}',
                      icon: Icons.view_in_ar_outlined,
                    ),
                    const SizedBox(height: 16),
                    _toolbar(),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              key: const ValueKey('docker-log-panel'),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xff0c192e),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  c.text.isEmpty ? t('暂无日志内容', 'No log content') : c.text,
                  style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontFamily: 'BookstarkLogsMono',
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          _footer(),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    widget.scope.release(c);
    tail.dispose();
    scroll.dispose();
    super.dispose();
  }
}
