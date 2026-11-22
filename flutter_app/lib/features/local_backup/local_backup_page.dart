import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/file_export.dart';
import '../../core/attachments.dart';
import 'local_backup_scaffold.dart';
import '../../core/local_backup_codec.dart';
import '../../core/local_backup_content.dart';
import '../../core/local_backup_exporter.dart';
import '../../core/local_backup_importer.dart';
import '../../core/local_recovery_inventory.dart';
import '../../core/local_restore_coordinator.dart';

/// The page only displays validated manifests. Native mutation/recovery belongs
/// to the injected storage workflow, bound to its original app storage scope.
class LocalBackupPage extends StatefulWidget {
  const LocalBackupPage({
    super.key,
    required this.createExport,
    required this.saveExport,
    required this.inspectPicked,
    required this.apply,
    required this.openRecovery,
    required this.openPending,
    required this.openRetained,
    required this.openLegacyMigration,
    this.english = false,
    this.initialCandidate,
    this.onBack,
    this.cancelInspection,
    this.openDrafts,
    this.exportNotice,
  });
  final Future<CompletedLocalBackup> Function() createExport;
  final Future<FileExportOutcome> Function(CompletedLocalBackup) saveExport;
  final Future<LocalBackupCandidate?> Function() inspectPicked;
  final Future<void> Function(LocalBackupCandidate) apply;
  final Future<void> Function() openRecovery, openRetained, openLegacyMigration;
  final Future<void> Function(LocalRecoverySummary) openPending;
  final bool english;
  final String? exportNotice;
  final VoidCallback? onBack;
  final Future<void> Function()? cancelInspection, openDrafts;
  final LocalBackupCandidate? initialCandidate;
  @override
  State<LocalBackupPage> createState() => _LocalBackupPageState();
}

enum _Step { home, export, inspected, scope }

class _LocalBackupPageState extends State<LocalBackupPage> {
  static const blue = Color(0xff0b57ee), navy = Color(0xff0c192e);
  static const tint = Color(0xffeaf2ff);
  var _step = _Step.home;
  bool _busy = false, _confirmed = false, _needsReview = false;
  bool _picking = false, _cancelling = false;
  String? _message;
  CompletedLocalBackup? _export;
  LocalBackupCandidate? _candidate;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _candidate = widget.initialCandidate;
    if (_candidate != null) _step = _Step.inspected;
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } on AttachmentCancelled {
      if (mounted) {
        setState(
          () => _message = t(
            '检查已取消，当前本地数据未切换。',
            'Check cancelled. Current local data has not switched.',
          ),
        );
      }
    } on PendingLocalRecovery catch (error) {
      if (mounted) await widget.openPending(error.summary);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            '操作未完成。已有文件已保留，请重新检查；恢复结果需要单独核对。',
            'Operation unfinished. Existing files are retained; review any restore result separately.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final backup = _export;
    _export = null;
    await backup?.dispose();
    final candidate = _candidate;
    _candidate = null;
    if (candidate != null && !_needsReview) await candidate.discardUnprepared();
  }

  Future<void> _exportNow() => _run(() async {
    final completed = await widget.createExport();
    _export = completed;
    try {
      if (!mounted) return;
      final outcome = await widget.saveExport(completed);
      if (mounted) {
        setState(() {
          _step = _Step.home;
          _message = outcome == FileExportOutcome.cancelled
              ? t('已取消保存', 'Save cancelled')
              : t('备份已保存到所选位置', 'Backup saved to the selected location');
        });
      }
    } finally {
      await completed.dispose();
      _export = null;
    }
  });

  Future<void> _pick() => _run(() async {
    setState(() {
      _picking = true;
      _cancelling = false;
    });
    try {
      final candidate = await widget.inspectPicked();
      if (candidate == null) return;
      if (!mounted) {
        await candidate.discardUnprepared();
        return;
      }
      setState(() {
        _candidate = candidate;
        _step = _Step.inspected;
      });
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          _cancelling = false;
        });
      }
    }
  });

  Future<void> _cancelInspection() async {
    if (!_picking || _cancelling || widget.cancelInspection == null) return;
    setState(() => _cancelling = true);
    try {
      await widget.cancelInspection!();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            '已请求取消，等待检查结束。',
            'Cancellation requested; waiting for the check to finish.',
          ),
        );
      }
    }
  }

  Future<void> _restore() => _run(() async {
    final candidate = _candidate!;
    // From this user-confirmed attempt onward only the dedicated recovery UI
    // can decide whether preparation/switch happened. Never discard blindly.
    setState(() => _needsReview = true);
    var reviewRequired = true;
    try {
      await widget.apply(candidate);
    } on LocalRestoreNotStarted catch (error, stack) {
      reviewRequired = false;
      if (mounted) setState(() => _needsReview = false);
      Error.throwWithStackTrace(error.cause, stack);
    } finally {
      if (reviewRequired && mounted) await widget.openRecovery();
    }
  });

  Widget _panel(
    Widget child, {
    Color color = tint,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _notice(IconData icon, String title, [String? detail]) => _panel(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: navy, size: 27),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xff475467), height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _button(String text, VoidCallback? onPressed, {bool primary = true}) =>
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
                onPressed: _busy ? null : onPressed,
                child: Text(text),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: blue,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : onPressed,
                child: Text(text),
              ),
      );
  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );
  Widget _actionCard(
    IconData icon,
    String title,
    String detail,
    Widget button,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffdce1e9)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        button,
      ],
    ),
  );
  List<Widget> _home() => [
    _notice(
      Icons.info_outline,
      t('本机数据', 'On this device'),
      t('笔记、书籍、网盘文件与附件', 'Notes, books, drive files and attachments'),
    ),
    if (widget.openDrafts != null)
      _button(
        t('本机草稿', 'Local drafts'),
        () => _run(widget.openDrafts!),
        primary: false,
      ),
    _section(t('备份', 'Backup')),
    _actionCard(
      Icons.insert_drive_file_outlined,
      t('导出本地备份', 'Export local backup'),
      t('保存到你选择的位置', 'Save to a location you choose'),
      _button(
        t('导出备份', 'Export backup'),
        () => setState(() => _step = _Step.export),
      ),
    ),
    _section(t('恢复', 'Restore')),
    _actionCard(
      Icons.history,
      t('从备份恢复', 'Restore from backup'),
      t('先检查文件，再确认恢复范围', 'Check the file, then confirm the restore scope'),
      _button(t('选择备份文件', 'Choose backup file'), _pick, primary: false),
    ),
    _notice(
      Icons.info_outline,
      t('旧版 Android 数据迁移', 'Legacy Android migration'),
      t(
        '旧版数据格式需要单独核对，不能用普通备份替代',
        'Legacy data needs its own format and scope review.',
      ),
    ),
    _button(
      t('查看迁移说明', 'Review legacy migration'),
      () => _run(widget.openLegacyMigration),
      primary: false,
    ),
    _button(
      t('恢复前快照', 'Pre-restore copies'),
      () => _run(widget.openRetained),
      primary: false,
    ),
    _button(
      t('核对恢复状态', 'Review restore status'),
      () => _run(widget.openRecovery),
      primary: false,
    ),
  ];
  List<Widget> _exportReview() => [
    _panel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('笔记、书籍、网盘与附件', 'Notes, books, drive and attachments'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t(
                    '包含回收站与本地资源绑定',
                    'Includes trash and local resource bindings',
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
      color: blue,
    ),
    _notice(
      Icons.block,
      t('不包含账户凭据与登录状态', 'Account credentials and login state are excluded'),
    ),
    _notice(
      Icons.error_outline,
      t('未保存草稿请先处理', 'Resolve unsaved drafts first'),
    ),
    _notice(
      Icons.lock_outline,
      t('备份含本机内容原文', 'Backup contains original local content'),
      t(
        '请妥善保管所选位置中的备份文件。',
        'Keep the saved backup file in a trusted location.',
      ),
    ),
    Text(
      t('保存位置由系统文件选择器指定', 'Choose the save location in the system picker'),
      textAlign: TextAlign.center,
    ),
    if (widget.exportNotice != null) ...[
      Text(widget.exportNotice!),
      const SizedBox(height: 12),
    ],
    _button(t('创建并导出', 'Create and export'), _exportNow),
    TextButton(
      onPressed: _busy ? null : () => setState(() => _step = _Step.home),
      child: Text(t('取消', 'Cancel')),
    ),
  ];
  Widget _facts(
    LocalBackupManifest manifest,
    int size,
    LocalBackupContentReport report,
  ) => _panel(
    Column(
      children: [
        for (final row in <(String, String)>[
          (t('格式版本', 'Format version'), '1'),
          (
            t('笔记与文章（含已删除）', 'Notes and articles, including deleted'),
            '${manifest.tables['notes']}',
          ),
          (
            t('书籍（含已删除）', 'Books, including deleted'),
            '${manifest.tables['books']}',
          ),
          (t('文件与附件', 'Files and attachments'), '${manifest.files.length - 1}'),
          (t('大小', 'Size'), '${(size / 1024 / 1024).toStringAsFixed(2)} MB'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(row.$1)),
                const SizedBox(width: 16),
                Text(
                  row.$2,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        if (report.needsAdditionalReview) ...[
          const Divider(),
          Text(
            t(
              '已保留失效资源绑定 ${report.disabledHtmlBindings} 项、不可用关联 ${report.unavailableReferences} 项、待清理图片 ${report.pendingImageCleanup} 项。',
              'Retained: ${report.disabledHtmlBindings} disabled resource bindings, ${report.unavailableReferences} unavailable references and ${report.pendingImageCleanup} image cleanup records.',
            ),
          ),
        ],
      ],
    ),
  );
  List<Widget> _inspected() {
    final candidate = _candidate!;
    return [
      _notice(
        Icons.insert_drive_file_outlined,
        t('本地备份文件', 'Local backup file'),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xff16a34a), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              t('文件完整性检查通过', 'File integrity verified'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
        ],
      ),
      _facts(
        candidate.manifest,
        candidate.sourceBytes,
        candidate.contentReport,
      ),
      _panel(
        Text(
          t(
            '恢复会切换到备份中的本地数据，当前数据保留为恢复前快照。',
            'Restore switches to the backup data. Current data is retained as a pre-restore copy.',
          ),
        ),
        color: const Color(0xfffff4e5),
      ),
      _button(
        t('查看恢复范围', 'Review restore scope'),
        () => setState(() {
          _step = _Step.scope;
          _confirmed = false;
        }),
        primary: false,
      ),
      _button(
        t('核对并继续', 'Review and continue'),
        () => setState(() {
          _step = _Step.scope;
          _confirmed = false;
        }),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                await _clear();
                if (mounted) setState(() => _step = _Step.home);
              }),
        child: Text(t('取消', 'Cancel')),
      ),
    ];
  }

  List<Widget> _scope() => [
    _panel(
      CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: blue,
        contentPadding: EdgeInsets.zero,
        title: Text(t('我已核对恢复范围', 'I have reviewed the restore scope')),
        value: _confirmed,
        onChanged: _busy || _needsReview
            ? null
            : (value) => setState(() => _confirmed = value == true),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    _notice(
      Icons.menu_book_outlined,
      t('本地笔记与书籍', 'Local notes and books'),
      t('恢复备份中的笔记与书籍数据', 'Restore notes and books in the backup'),
    ),
    _notice(
      Icons.folder_outlined,
      t('本地网盘与附件', 'Local drive and attachments'),
      t('恢复备份中的网盘文件与附件', 'Restore drive files and attachments in the backup'),
    ),
    _notice(
      Icons.delete_outline,
      t('回收站与资源绑定', 'Trash and resource bindings'),
      t(
        '同时恢复回收内容与本地资源绑定关系',
        'Also restore trash and local resource binding records',
      ),
    ),
    _notice(
      Icons.info_outline,
      t('账户与服务器数据不在恢复范围内', 'Account and server data are outside this restore'),
    ),
    _notice(
      Icons.info_outline,
      t(
        '恢复后需核对结果，再重新进入本地空间',
        'Review the result before reentering local space',
      ),
    ),
    _button(
      t('确认恢复', 'Confirm restore'),
      _confirmed && !_needsReview ? _restore : null,
    ),
    if (_needsReview)
      _button(
        t('核对恢复结果', 'Review restore result'),
        () => _run(widget.openRecovery),
        primary: false,
      )
    else
      TextButton(
        onPressed: _busy ? null : () => setState(() => _step = _Step.inspected),
        child: Text(t('取消', 'Cancel')),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.home => t('本地备份与迁移', 'Local backup and migration'),
      _Step.export => t('备份前核对', 'Before exporting'),
      _Step.inspected => t('检查备份', 'Check backup'),
      _Step.scope => t('确认恢复范围', 'Confirm restore scope'),
    };
    final items = switch (_step) {
      _Step.home => _home(),
      _Step.export => _exportReview(),
      _Step.inspected => _inspected(),
      _Step.scope => _scope(),
    };
    final split = switch (_step) {
      _Step.home => items.length,
      _Step.export => 4,
      _Step.inspected => 5,
      _Step.scope => 6,
    };
    return LocalBackupScaffold(
      title: title,
      busy: _busy,
      onBack: widget.onBack,
      scrollIdentity: (_step, _picking),
      content: [
        if (_busy) ...[
          const LinearProgressIndicator(),
          Text(
            t(
              _cancelling ? '正在取消检查…' : '正在检查或保存，请稍候…',
              _cancelling ? 'Cancelling the check…' : 'Checking or saving…',
            ),
          ),
          if (_picking && widget.cancelInspection != null)
            OutlinedButton(
              onPressed: _cancelling ? null : _cancelInspection,
              child: Text(t('取消检查', 'Cancel check')),
            ),
        ],
        if (_message != null)
          _panel(Text(_message!), color: const Color(0xfffff4e5)),
        ...items.take(split),
      ],
      actions: items.skip(split).toList(),
    );
  }

  @override
  void dispose() {
    final backup = _export;
    if (backup != null) unawaited(backup.dispose());
    if (_picking && widget.cancelInspection != null) {
      unawaited(widget.cancelInspection!().catchError((Object _) {}));
    }
    // Submitted or uncertain candidates are always retained. Unsubmitted copies
    // remain available for explicit serialized cleanup; no blind dispose delete.
    super.dispose();
  }
}
