import 'package:flutter/material.dart';
import 'local_backup_scaffold.dart';
import '../../core/local_applied_backup_review.dart';
import '../../core/local_generation_state.dart';
import '../../core/native_local_data_control.dart';

class LocalRecoveryPage extends StatefulWidget {
  const LocalRecoveryPage({
    super.key,
    required this.load,
    required this.reviewApplied,
    required this.finishUnapplied,
    required this.acknowledge,
    required this.reenter,
    required this.openRetained,
    required this.returnToConnection,
    this.english = false,
    this.onBack,
  });
  final Future<LocalDataControlState> Function() load;
  final Future<ReviewedLocalAppliedBackup> Function(LocalDataControlState)
  reviewApplied;
  final Future<LocalDataControlState> Function(LocalDataControlState)
  finishUnapplied;
  final Future<void> Function(ReviewedLocalAppliedBackup) acknowledge;
  final Future<void> Function(LocalDataControlState) reenter;
  final Future<void> Function() openRetained, returnToConnection;
  final bool english;
  final Future<void> Function()? onBack;
  @override
  State<LocalRecoveryPage> createState() => _LocalRecoveryPageState();
}

class _LocalRecoveryPageState extends State<LocalRecoveryPage> {
  static const blue = Color(0xff0b57ee), tint = Color(0xffeaf2ff);
  LocalDataControlState? _state;
  ReviewedLocalAppliedBackup? _review;
  bool _busy = false, _confirmed = false, _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = null;
          _review = null;
          _confirmed = false;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    try {
      await (widget.onBack ?? widget.returnToConnection)();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _reload() => _run(() async {
    final state = await widget.load();
    if (mounted) {
      setState(() {
        _state = state;
        _review = null;
        _confirmed = false;
      });
    }
  });
  Widget _panel(Widget child, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(16),
    width: double.infinity,
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff0ca) : tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
  Widget _notice(IconData icon, String title, [String? detail]) => _panel(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null) ...[const SizedBox(height: 6), Text(detail)],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _statusCard(IconData icon, String title) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffdce1e9)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  Widget _uncheckedFacts() => _panel(
    Column(
      children: [
        for (final entry in [
          (Icons.menu_book_outlined, t('笔记', 'Notes')),
          (Icons.attach_file, t('文件与附件', 'Files and attachments')),
          (Icons.storage_outlined, t('大小', 'Size')),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(entry.$1),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.$2)),
                const SizedBox(width: 12),
                Text(t('待检查', 'Unchecked')),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _button(String title, VoidCallback? callback, {bool primary = true}) =>
      SizedBox(
        width: double.infinity,
        child: primary
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: blue,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : callback,
                child: Text(title),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: blue,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : callback,
                child: Text(title),
              ),
      );
  Widget _catalog() => _button(
    t('查看恢复前快照', 'View pre-restore copies'),
    () => _run(widget.openRetained),
    primary: false,
  );
  List<Widget> _inconsistent() => [
    _panel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xff805015),
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('恢复记录不一致', 'Restore records need review'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 23),
            ),
          ),
        ],
      ),
      warning: true,
    ),
    Text(
      t(
        '为保留现有内容，暂时停止本地写入。',
        'Local writes are paused to preserve existing content.',
      ),
    ),
    _notice(
      Icons.info_outline,
      t('现有内容和保留快照不会自动清除。', 'Existing content and retained copies are kept.'),
    ),
    _button(t('重新只读检查', 'Check again without writing'), _reload),
    _button(
      t('查看保留快照', 'View retained copies'),
      () => _run(widget.openRetained),
      primary: false,
    ),
    TextButton(
      onPressed: _busy ? null : () => _run(widget.returnToConnection),
      child: Text(t('返回连接页', 'Return to connection')),
    ),
  ];
  List<Widget> _prepared(LocalDataControlState state) => [
    _panel(
      Text(
        t('尚未切换数据', 'Data has not switched'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      warning: true,
    ),
    _notice(
      Icons.info_outline,
      t(
        '原数据和恢复前快照均已保留。',
        'Original data and the pre-restore copy are retained.',
      ),
    ),
    _statusCard(Icons.layers_outlined, t('当前：恢复前数据', 'Current: original data')),
    _statusCard(Icons.history, t('待恢复：已检查的备份', 'Pending: the checked backup')),
    _button(
      t('结束本次恢复', 'End this restore'),
      () => _run(() async {
        final next = await widget.finishUnapplied(state);
        if (mounted) {
          setState(() {
            _state = next;
            _review = null;
          });
        }
      }),
    ),
    _catalog(),
    Text(t('结束后仍需明确重新进入原数据。', 'Then explicitly reenter the original data.')),
  ];
  List<Widget> _retained(LocalDataControlState state) => [
    _panel(Text(t('尚未切换数据', 'Data has not switched')), warning: true),
    _notice(
      Icons.info_outline,
      t(
        '原数据和恢复前快照均已保留。',
        'Original data and the pre-restore copy are retained.',
      ),
    ),
    _statusCard(Icons.layers_outlined, t('当前：恢复前数据', 'Current: original data')),
    _button(
      t('重新进入原数据', 'Reenter original data'),
      () => _run(() => widget.reenter(state)),
    ),
    _catalog(),
    _button(
      t('重新只读检查', 'Check again without writing'),
      _reload,
      primary: false,
    ),
  ];
  List<Widget> _switched(LocalDataControlState state) => [
    _panel(Text(t('已切换，等待核对', 'Switched, awaiting review')), warning: true),
    _notice(
      Icons.info_outline,
      t(
        '先核对已保存内容，再进入本地空间。',
        'Review saved content before entering local space.',
      ),
    ),
    _uncheckedFacts(),
    _button(
      t('只读查看范围', 'Review scope without writing'),
      () => _run(() async {
        final review = await widget.reviewApplied(state);
        if (mounted) {
          setState(() {
            _review = review;
            _confirmed = false;
          });
        }
      }),
    ),
    _catalog(),
    _button(
      t('重新只读检查', 'Check again without writing'),
      _reload,
      primary: false,
    ),
  ];
  List<Widget> _reviewed(ReviewedLocalAppliedBackup review) => [
    _notice(
      Icons.menu_book_outlined,
      t('本地笔记与书籍', 'Local notes and books'),
      t(
        '笔记及文章 ${review.manifest.tables['notes']} · 书籍 ${review.manifest.tables['books']}（含已删除记录）',
        'Notes/articles ${review.manifest.tables['notes']} · books ${review.manifest.tables['books']}, including deleted',
      ),
    ),
    _notice(
      Icons.folder_outlined,
      t('本地网盘与附件', 'Local drive and attachments'),
      t(
        '${review.manifest.files.length - 1} 个文件 · ${(review.bytes / 1048576).toStringAsFixed(2)} MB',
        '${review.manifest.files.length - 1} files · ${(review.bytes / 1048576).toStringAsFixed(2)} MB',
      ),
    ),
    _notice(
      Icons.recycling,
      t('回收站与资源绑定', 'Trash and resource bindings'),
      t('保留已保存关系', 'Saved relationships are retained'),
    ),
    if (review.contentReport.needsAdditionalReview)
      _panel(
        Text(
          t(
            '失效资源绑定 ${review.contentReport.disabledHtmlBindings} 项，不可用关联 ${review.contentReport.unavailableReferences} 项，待清理图片 ${review.contentReport.pendingImageCleanup} 项；原记录均已保留。',
            'Retained records: ${review.contentReport.disabledHtmlBindings} disabled bindings, ${review.contentReport.unavailableReferences} unavailable references, ${review.contentReport.pendingImageCleanup} image cleanup entries.',
          ),
        ),
        warning: true,
      ),
    CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: blue,
      contentPadding: EdgeInsets.zero,
      value: _confirmed,
      title: Text(t('我已核对恢复范围', 'I have reviewed the restore scope')),
      onChanged: _busy
          ? null
          : (value) => setState(() => _confirmed = value == true),
    ),
    Text(
      t(
        '账号、登录状态和服务器数据不在恢复范围内。',
        'Accounts, login state and server data are excluded.',
      ),
    ),
    _button(
      t('确认并进入本地空间', 'Confirm and enter local space'),
      _confirmed ? () => _run(() => widget.acknowledge(review)) : null,
    ),
    TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
              _review = null;
              _confirmed = false;
            }),
      child: Text(t('暂不确认', 'Not now')),
    ),
  ];
  List<Widget> _ready(LocalDataControlState state) => [
    _notice(
      Icons.info_outline,
      t('没有待核对的恢复操作', 'No restore operation awaits review'),
    ),
    Text(
      t(
        '已有本地内容和保留快照仍在。',
        'Existing local content and retained copies remain available.',
      ),
    ),
    _button(
      t('进入本地空间', 'Enter local space'),
      () => _run(() => widget.reenter(state)),
    ),
    _catalog(),
  ];
  @override
  Widget build(BuildContext context) {
    final state = _state;
    final phase = state?.observation.phase;
    final inconsistent = _failed || phase == LocalGenerationPhase.inconsistent;
    final title = _review != null
        ? t('核对恢复内容', 'Review restored content')
        : inconsistent
        ? t('本机数据需要核对', 'Local data needs review')
        : t('恢复待核对', 'Review restore state');
    final children = _review != null
        ? _reviewed(_review!)
        : inconsistent
        ? _inconsistent()
        : state == null
        ? <Widget>[]
        : switch (phase!) {
            LocalGenerationPhase.prepared => _prepared(state),
            LocalGenerationPhase.retained => _retained(state),
            LocalGenerationPhase.switched => _switched(state),
            LocalGenerationPhase.ready => _ready(state),
            LocalGenerationPhase.inconsistent => _inconsistent(),
          };
    final split = _review != null
        ? children.length - 2
        : inconsistent
        ? 3
        : state == null
        ? children.length
        : switch (phase!) {
            LocalGenerationPhase.prepared => 4,
            LocalGenerationPhase.retained => 3,
            LocalGenerationPhase.switched => 3,
            LocalGenerationPhase.ready => 2,
            LocalGenerationPhase.inconsistent => 3,
          };
    return LocalBackupScaffold(
      title: title,
      busy: _busy,
      onBack: _back,
      scrollIdentity: (_review != null, phase),
      content: [
        if (_busy) const LinearProgressIndicator(),
        ...children.take(split),
      ],
      actions: children.skip(split).toList(),
    );
  }
}
