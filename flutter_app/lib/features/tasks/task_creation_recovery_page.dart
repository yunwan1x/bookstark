import 'package:flutter/material.dart';
import '../../core/task_creation_attempt.dart';
import '../../core/task_creation_controller.dart';

class TaskCreationRecoveryPage extends StatefulWidget {
  const TaskCreationRecoveryPage({
    super.key,
    required this.controller,
    required this.serverLabel,
    required this.initiatorId,
    this.english = false,
    this.local = false,
    this.onEndMissing,
  });
  final TaskCreationRecoveryController controller;
  final Future<void> Function()? onEndMissing;
  final bool local;
  final bool english;
  final String serverLabel;
  final int initiatorId;
  @override
  State<TaskCreationRecoveryPage> createState() =>
      _TaskCreationRecoveryPageState();
}

class _TaskCreationRecoveryPageState extends State<TaskCreationRecoveryPage> {
  final _id = TextEditingController();
  TaskCreationRecoveryController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant TaskCreationRecoveryPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, c)) {
      old.controller.removeListener(_changed);
      c.addListener(_changed);
      _id.clear();
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _id.dispose();
    super.dispose();
  }

  Future<void> _end() async {
    final owner = c, record = c.record;
    if (record == null || owner.busy || owner.storageUnconfirmed) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(t('结束恢复记录？', 'End recovery record?')),
        content: Text(
          widget.local
              ? t(
                  '此操作不代表本地创建从未发生，不会删除本地待办或任何关联。',
                  'This does not prove local creation never happened. No local task or association will be deleted.',
                )
              : t(
                  '此操作不代表服务器未执行请求，不会删除服务器待办或任何关联。',
                  'This does not mean the server did not execute the request. No task or association will be deleted.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('保留记录', 'Keep record')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('确认结束', 'End record')),
          ),
        ],
      ),
    );
    if (!mounted ||
        !identical(c, owner) ||
        !owner.current ||
        !identical(owner.record, record) ||
        yes != true) {
      return;
    }
    await owner.end(record);
  }

  Future<void> _useKnown() async {
    final owner = c, selected = c.reviewed, record = c.record;
    if (selected == null || record == null) return;
    try {
      final verified = await owner.verifyKnown(selected);
      if (!mounted ||
          !identical(owner, c) ||
          !owner.current ||
          !identical(owner.record, record) ||
          !verified) {
        return;
      }
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted && identical(owner, c) && owner.current) await owner.reload();
    }
  }

  Widget frame(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final a = c.record, r = c.reviewed;
    return Scaffold(
      appBar: AppBar(title: Text(t('待办创建恢复', 'Recover task creation'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (r == null)
            frame([
              Text(
                widget.local
                    ? t('本地空间', 'Local space')
                    : t('当前服务器', 'Current server'),
              ),
              SelectableText(widget.serverLabel),
              const SizedBox(height: 8),
              if (widget.local)
                Text(t('仅此设备 · 不联网', 'Only this device · No network'))
              else ...[
                Text(
                  t('发起账号：', 'Initiating account: ') +
                      widget.initiatorId.toString(),
                ),
                Text(
                  t(
                    '只核对属于此账号的实际待办',
                    'Only tasks owned by this account are reviewable',
                  ),
                ),
              ],
            ]),
          if (c.error != null) ...[
            Text(c.error!, semanticsLabel: c.error),
            OutlinedButton(
              onPressed: c.busy ? null : c.reload,
              child: Text(t('重新核对记录', 'Review record again')),
            ),
          ],
          if (c.storageUnconfirmed) ...[
            Text(
              t(
                '记录保存结果尚未确认，请先重新读取。',
                'Record durability is unconfirmed. Reload before continuing.',
              ),
            ),
            FilledButton(
              onPressed: c.busy ? null : c.reload,
              child: Text(t('重新读取记录', 'Reload record')),
            ),
          ],
          if (c.hasKnownAcknowledgement)
            FilledButton(
              onPressed: c.busy ? null : c.retryAcknowledgement,
              child: Text(
                t('完成记录保存（不重新创建）', 'Complete record storage (no new request)'),
              ),
            ),
          if (a == null) ...[
            Text(
              t(
                '未读取到任务记录；这不授权重新创建。',
                'No task record was read; this does not authorize creation.',
              ),
            ),
            if (widget.onEndMissing != null &&
                !c.busy &&
                !c.storageUnconfirmed &&
                c.error == null)
              OutlinedButton(
                onPressed: () async {
                  final owner = c, action = widget.onEndMissing;
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      scrollable: true,
                      title: Text(t('结束空恢复入口？', 'End empty recovery slot?')),
                      content: Text(
                        t(
                          '仅移除此入口，不创建或删除待办。',
                          'Only this slot is removed; no task is created or deleted.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(t('保留', 'Keep')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(t('确认结束', 'End slot')),
                        ),
                      ],
                    ),
                  );
                  if (!mounted ||
                      !identical(c, owner) ||
                      !owner.current ||
                      yes != true ||
                      action == null)
                    return;
                  try {
                    await action();
                  } catch (_) {
                    if (mounted) await owner.reload();
                  }
                },
                child: Text(t('明确结束空入口', 'Explicitly end empty slot')),
              ),
          ],
          if (a != null) ...[
            Text(
              a.phase == TaskCreationPhase.pending
                  ? t('尚未获得发送授权', 'Not submitted')
                  : a.phase == TaskCreationPhase.unknown
                  ? t(
                      '结果未知，不会自动重新创建',
                      'Unknown result. Creation will not be replayed.',
                    )
                  : t(
                      '已记录实际 ID，仅完成记录保存',
                      'Actual ID recorded. Storage completion only.',
                    ),
            ),
            frame([
              Text(t('完整冻结草稿（只读）', 'Complete frozen draft (read only)')),
              SelectableText(a.body['content'] as String),
              Text(t('日期：', 'Due: ') + (a.body['due_date'] as String)),
              Text(t('完成：', 'Done: ') + a.body['done'].toString()),
              Text(
                t('父待办 ID：', 'Parent task ID: ') +
                    a.body['parent_id'].toString(),
              ),
              Text(t('专题 ID：', 'Topic ID: ') + a.body['topic_id'].toString()),
            ]),
            if (a.phase == TaskCreationPhase.unknown && r == null) ...[
              Text(
                widget.local
                    ? t(
                        '只读核对本地原子回执与实际任务，不会重新执行创建。',
                        'Read the local atomic receipt and actual task. Creation is never replayed.',
                      )
                    : t(
                        '请输入实际 ID。相同内容不能证明这是本次请求创建的待办。',
                        'Enter the actual ID. Matching content does not prove which request created this task.',
                      ),
              ),
              if (widget.local)
                FilledButton(
                  onPressed: c.busy || c.storageUnconfirmed
                      ? null
                      : () => c.review(0),
                  child: Text(t('核对本地原子回执', 'Review local atomic receipt')),
                ),
              if (!widget.local)
                TextField(
                  controller: _id,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('实际资源 ID', 'Actual resource ID'),
                  ),
                ),
              if (!widget.local)
                FilledButton(
                  onPressed: c.busy || c.storageUnconfirmed
                      ? null
                      : () {
                          final id = int.tryParse(_id.text);
                          if (id != null && id > 0) c.review(id);
                        },
                  child: Text(t('只读核对', 'Review read only')),
                ),
            ],
            if (r != null) ...[
              frame([
                Text(t('只读 · 当前数据', 'Read only · current data')),
                SelectableText('ID ${r.id}'),
                if (r.wire['content'] is String)
                  SelectableText(r.wire['content'] as String),
                Text(t('完整元数据（只读）', 'Complete metadata (read only)')),
                SelectableText(r.display),
              ]),
              Text(
                t(
                  '接纳此实际 ID 只关联恢复记录，不证明创建请求的来源。',
                  'Adopting this ID links the recovery record; it does not establish request provenance.',
                ),
              ),
              if (a.phase == TaskCreationPhase.unknown)
                FilledButton(
                  onPressed:
                      c.busy || c.storageUnconfirmed || !r.matchesFrozenInput
                      ? null
                      : () => c.adopt(r),
                  child: Text(
                    widget.local
                        ? t('确认本地回执', 'Confirm local receipt')
                        : t('接纳此 ID', 'Adopt this ID'),
                  ),
                ),
            ],
            if (a.phase == TaskCreationPhase.knownID)
              Text(
                a.origin == TaskCreationOrigin.manualExisting
                    ? (widget.local
                          ? t(
                              '已明确采用既有本地待办，不证明本次创建来源。',
                              'Existing local task explicitly adopted; this is not creation proof.',
                            )
                          : t(
                              '已明确采用既有全局待办，不是本次创建回执。',
                              'Existing task explicitly adopted; this is not a creation receipt.',
                            ))
                    : a.origin ==
                          TaskCreationOrigin.localTransactionAcknowledgement
                    ? t(
                        '已收到真实本地事务完成后的实际 ID。进程中断后不能靠同名恢复此证明。',
                        'The actual ID returned after the local transaction completed. Content matching cannot recover this proof after interruption.',
                      )
                    : t(
                        '已收到本次 POST 的实际 ID 回执；此处只保存和核对记录。',
                        'The actual POST ID acknowledgement was received. Recovery only stores and reviews this record.',
                      ),
              ),
            if (a.actualId != null) ...[
              SelectableText('ID ${a.actualId}'),
              FilledButton(
                onPressed: c.busy || c.storageUnconfirmed
                    ? null
                    : () => c.review(a.actualId!),
                child: Text(
                  t('核对已确认 ID 的完整内容', 'Review complete content for known ID'),
                ),
              ),
              if (r != null && r.id == a.actualId)
                FilledButton(
                  onPressed: c.busy || c.storageUnconfirmed ? null : _useKnown,
                  child: Text(t('使用此已确认 ID', 'Use this confirmed ID')),
                ),
            ],
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: c.busy || c.storageUnconfirmed ? null : _end,
              child: Text(t('结束恢复记录', 'End recovery record')),
            ),
          ],
          TextButton(
            onPressed: c.busy ? null : () => Navigator.pop(context),
            child: Text(t('返回并保留记录', 'Return and keep record')),
          ),
        ],
      ),
    );
  }
}
