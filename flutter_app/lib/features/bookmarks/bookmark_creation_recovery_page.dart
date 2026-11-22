import 'package:flutter/material.dart';
import '../../core/bookmark_creation_attempt.dart';
import '../../core/bookmark_creation_controller.dart';

class BookmarkCreationRecoveryPage extends StatefulWidget {
  const BookmarkCreationRecoveryPage({
    super.key,
    required this.controller,
    this.english = false,
  });
  final BookmarkCreationController controller;
  final bool english;
  @override
  State<BookmarkCreationRecoveryPage> createState() =>
      _BookmarkCreationRecoveryPageState();
}

class _BookmarkCreationRecoveryPageState
    extends State<BookmarkCreationRecoveryPage> {
  final _id = TextEditingController();
  BookmarkCreationController get c => widget.controller;
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
  void didUpdateWidget(covariant BookmarkCreationRecoveryPage old) {
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
          t(
            '此操作不代表服务器未创建资源。结束后不会自动删除服务器资源。',
            'This does not mean the server did not create the resource. No server resource will be deleted.',
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

  @override
  Widget build(BuildContext context) {
    final a = c.record, r = c.reviewed;
    return Scaffold(
      appBar: AppBar(title: Text(t('书签创建恢复', 'Recover bookmark creation'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.error != null) Text(c.error!, semanticsLabel: c.error),
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
          if (a == null) Text(t('没有恢复记录。', 'No recovery record.')),
          if (a != null) ...[
            Text(
              a.phase == BookmarkCreationPhase.pending
                  ? t('尚未获得发送授权', 'Not submitted')
                  : a.phase == BookmarkCreationPhase.unknown
                  ? t(
                      '结果未知，不会自动重新创建',
                      'Unknown result. Creation will not be replayed.',
                    )
                  : t(
                      '已获实际 ID，仅完成记录保存',
                      'Actual ID received. Storage completion only.',
                    ),
            ),
            SelectableText('Attempt ${a.key}'),
            // Full frozen input is reviewable; never claim a title is creation proof.
            SelectableText(a.body.toString()),
            if (a.phase == BookmarkCreationPhase.pending)
              FilledButton(
                onPressed: c.busy || c.storageUnconfirmed ? null : c.submit,
                child: Text(t('提交同一草稿', 'Submit this draft')),
              ),
            if (a.phase == BookmarkCreationPhase.unknown) ...[
              Text(
                t(
                  '请输入实际 ID。相同 URL 或标题不能证明这是本次请求创建的书签。',
                  'Enter the actual ID. Matching URL or title does not prove which request created this bookmark.',
                ),
              ),
              TextField(
                controller: _id,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('实际资源 ID', 'Actual resource ID'),
                ),
              ),
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
              SelectableText(r.display),
              Text(
                t(
                  '接纳此实际 ID 只关联恢复记录，不证明创建请求的来源。',
                  'Adopting this ID links the recovery record; it does not establish request provenance.',
                ),
              ),
              FilledButton(
                onPressed:
                    c.busy || c.storageUnconfirmed || !r.matchesFrozenInput
                    ? null
                    : () => c.adopt(r),
                child: Text(t('接纳此 ID', 'Adopt this ID')),
              ),
            ],
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
