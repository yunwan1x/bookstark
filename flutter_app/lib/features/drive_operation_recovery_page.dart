import 'package:flutter/material.dart';
import '../core/drive_operation_record.dart';
import '../core/drive_operation_recovery_controller.dart';

class DriveOperationRecoveryPage extends StatefulWidget {
  const DriveOperationRecoveryPage({
    super.key,
    required this.controller,
    this.english = false,
  });
  final DriveOperationRecoveryController controller;
  final bool english;
  @override
  State<DriveOperationRecoveryPage> createState() =>
      _DriveOperationRecoveryPageState();
}

class _DriveOperationRecoveryPageState
    extends State<DriveOperationRecoveryPage> {
  DriveOperationRecoveryController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant DriveOperationRecoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '当前空间已失效，原记录未修改。',
                'This scope is retired. Its record was not changed.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _end() async {
    final owner = c, r = owner.record;
    if (r == null || !owner.store.isCurrent()) return;
    var confirmed = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(t('结束本机记录？', 'End device record?')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    '操作可能已经执行。结束记录不会撤销操作，也不代表操作未执行。不会发送任何文件写请求。',
                    'The operation may have executed. Ending tracking does not undo it or mean it did not execute. No file write will be sent.',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: (v) => setDialog(() => confirmed = v == true),
                  title: Text(
                    t(
                      '我已核对，确认仅结束本机记录',
                      'I reviewed this and will only end device tracking',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('继续保留', 'Keep record')),
            ),
            FilledButton(
              onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
              child: Text(t('确认结束记录', 'End record')),
            ),
          ],
        ),
      ),
    );
    if (yes == true &&
        mounted &&
        identical(c, owner) &&
        owner.store.isCurrent() &&
        owner.record?.fingerprint == r.fingerprint) {
      await _run(
        () => owner.endRecord(
          expectedFingerprint: r.fingerprint,
          explicitlyConfirmed: true,
        ),
      );
    }
  }

  String _difference(DriveOperationObservation current) {
    final r = c.record;
    if (r == null) return '';
    DriveOperationObservation? baseline;
    for (final row in [
      r.source,
      r.destinationBefore,
      r.sourceParent,
      r.destinationParent,
    ]) {
      if (row?.path == current.path) {
        baseline = row;
        break;
      }
    }
    if (baseline == null) {
      return t('没有原始快照可比较', 'No original snapshot to compare');
    }
    return driveMetadataDigest(baseline.toJson()) ==
            driveMetadataDigest(current.toJson())
        ? t(
            '与原快照一致；不代表本操作成功',
            'Matches the original snapshot; does not prove success',
          )
        : t(
            '与原快照不同；不代表由本操作造成',
            'Differs from the original snapshot; cause is unknown',
          );
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  @override
  Widget build(BuildContext context) {
    final r = c.record;
    return PopScope(
      canPop: !c.busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('待核对的文件操作', 'Review file operation')),
          leading: IconButton(
            tooltip: t('返回并保留', 'Return and keep'),
            onPressed: c.busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.safeError != null)
              Semantics(liveRegion: true, child: Text(c.safeError!)),
            if (!c.ready || c.storageUnconfirmed)
              FilledButton(
                onPressed: c.busy ? null : () => _run(c.load),
                child: Text(t('重新读取本机记录', 'Reload device record')),
              ),
            if (c.ready && r == null)
              Text(t('未找到待核对记录。', 'No retained operation record was found.')),
            if (r != null) ...[
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.kind.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (r.source != null) ...[
                      Text(t('原源路径', 'Original source')),
                      SelectableText(r.source!.path),
                      Text('ID ${r.source!.node!.id}'),
                      SelectableText('ETag ${r.source!.node!.etag}'),
                    ],
                    if (r.destination.isNotEmpty) ...[
                      Text(t('固定目标路径', 'Fixed destination')),
                      SelectableText(r.destination),
                    ],
                  ],
                ),
              ),
              Text(
                c.serverAcknowledged
                    ? t(
                        '已收到服务器回执；仅本机记录可重试，不会重发。',
                        'Server acknowledgment received. Only device recording can be retried.',
                      )
                    : t(
                        '结果待核对，操作可能已执行。不会自动重试。',
                        'Result requires review. The operation may have executed. It will not retry automatically.',
                      ),
              ),
              if (c.serverAcknowledged && c.storageUnconfirmed)
                FilledButton(
                  onPressed: c.busy
                      ? null
                      : () => _run(c.retryAcknowledgmentStorage),
                  child: Text(t('仅重试本机确认', 'Retry device acknowledgment only')),
                ),
              FilledButton(
                onPressed: c.busy || !c.ready || c.storageUnconfirmed
                    ? null
                    : () => _run(c.inspect),
                child: Text(
                  t('只读核对源与目标', 'Review source and target (read only)'),
                ),
              ),
              if (c.review != null) ...[
                Text(
                  t(
                    '以下是当前状态，不代表本次操作成功。',
                    'Current observations do not prove this operation succeeded.',
                  ),
                ),
                for (final row in c.review!.observations)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(row.path.isEmpty ? '/' : row.path),
                        Text(switch (row.state) {
                          DriveObservationState.root => t(
                            '根目录',
                            'Root directory',
                          ),
                          DriveObservationState.missing => t(
                            '未找到',
                            'Not found',
                          ),
                          DriveObservationState.found => t(
                            '当前找到',
                            'Currently found',
                          ),
                        }),
                        if (row.node != null) ...[
                          Text('ID ${row.node!.id} · ${row.node!.size} bytes'),
                          SelectableText('ETag ${row.node!.etag}'),
                          Text(
                            row.node!.directory
                                ? t('目录', 'Directory')
                                : row.node!.mime,
                          ),
                          Text(row.node!.modified),
                          Text(
                            row.node!.isPublic
                                ? t('当前公开', 'Currently public')
                                : t('当前非公开', 'Currently private'),
                          ),
                          if (row.node!.isPublic)
                            SelectableText(row.node!.publicPath),
                        ],
                        Text(_difference(row)),
                      ],
                    ),
                  ),
              ],
              OutlinedButton(
                onPressed: c.busy || !c.ready || c.storageUnconfirmed
                    ? null
                    : _end,
                child: Text(t('结束本机记录', 'End device record')),
              ),
              Text(
                t(
                  '关闭页面或重启后仍保留记录。列表刷新不代表操作成功。',
                  'The record survives closing and restarting. A list refresh does not prove success.',
                ),
              ),
            ],
            TextButton(
              onPressed: c.busy ? null : () => Navigator.pop(context),
              child: Text(t('返回并保留记录', 'Return and keep record')),
            ),
          ],
        ),
      ),
    );
  }
}
