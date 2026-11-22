import 'package:flutter/material.dart';
import '../../core/local_backup_importer.dart';
import '../../core/local_generation_state.dart';
import '../../core/native_local_data_control.dart';

class LocalRetentionCatalogPage extends StatefulWidget {
  const LocalRetentionCatalogPage({
    super.key,
    required this.load,
    required this.inspect,
    required this.restore,
    required this.canRestore,
    this.english = false,
  });
  final Future<LocalRetentionCatalog> Function() load;
  final Future<LocalBackupCandidate> Function(LocalRetention) inspect;
  final Future<void> Function(LocalBackupCandidate) restore;
  final bool canRestore, english;
  @override
  State<LocalRetentionCatalogPage> createState() =>
      _LocalRetentionCatalogPageState();
}

class _LocalRetentionCatalogPageState extends State<LocalRetentionCatalogPage> {
  LocalRetentionCatalog? _catalog;
  final _checked = <String, LocalBackupCandidate>{};
  bool _busy = false, _failed = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() => _run(() async {
    final catalog = await widget.load();
    if (mounted) setState(() => _catalog = catalog);
  });
  Future<void> _inspect(LocalRetention entry) => _run(() async {
    final previous = _checked.remove(entry.id);
    await previous?.discardUnprepared();
    final candidate = await widget.inspect(entry);
    if (mounted) {
      setState(() => _checked[entry.id] = candidate);
    } else {
      await candidate.discardUnprepared();
    }
  });
  String _date(String createdAt) {
    final time = DateTime.parse(createdAt).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  Future<void> _scope(LocalBackupCandidate candidate) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('快照范围', 'Snapshot scope')),
        content: SingleChildScrollView(
          child: Text(
            t(
              '笔记及文章 ${candidate.manifest.tables['notes']} · 书籍 ${candidate.manifest.tables['books']}（含已删除记录）\n文件与附件 ${candidate.manifest.files.length - 1}\n回收站 ${candidate.manifest.tables['trash_entries']} 项\n\n仅本地内容；不包含账户、登录状态或服务器数据。',
              'Notes/articles ${candidate.manifest.tables['notes']} · books ${candidate.manifest.tables['books']}, including deleted\nFiles/attachments ${candidate.manifest.files.length - 1}\nTrash ${candidate.manifest.tables['trash_entries']} entries\n\nLocal content only. No accounts, login state or server data.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(t('恢复前快照', 'Pre-restore copies')),
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              if (_failed) ...[
                Text(
                  t(
                    '快照未能完成检查。已有文件保留，请重试。',
                    'Snapshot check unfinished. Existing files are retained.',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (catalog != null) ...[
                if (catalog.entries.isEmpty)
                  Text(t('尚无已登记的恢复前快照', 'No registered pre-restore copies')),
                if (catalog.unknown > 0 || catalog.overflow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      t(
                        '存在未完成或无法识别的快照，或目录超过本次检查上限。所有文件均保留。',
                        'Some copies are incomplete or unrecognized, or the catalog inspection limit was reached. All files are retained.',
                      ),
                    ),
                  ),
                for (final (index, entry) in catalog.entries.indexed) ...[
                  _entry(entry, index),
                  const SizedBox(height: 16),
                ],
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.canRestore
                      ? t(
                          '恢复会创建新的工作副本，当前数据另存为快照。',
                          'Restore creates a new working copy and independently retains current data.',
                        )
                      : t(
                          '当前只读核对。先处理恢复状态并进入本地空间，再从快照恢复。',
                          'Read-only review. Resolve restore state and enter local space before restoring a copy.',
                        ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy ? null : _reload,
                child: Text(t('重新检查目录', 'Check catalog again')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entry(LocalRetention entry, int index) {
    final candidate = _checked[entry.id];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffdce1e9)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.calendar_today_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  candidate == null
                      ? t(
                          '待检查的恢复前快照 · ${index + 1}',
                          'Pre-restore copy · ${index + 1} · unchecked',
                        )
                      : _date(candidate.manifest.createdAt),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (candidate == null)
            OutlinedButton(
              onPressed: _busy ? null : () => _inspect(entry),
              child: Text(t('检查此快照', 'Check this copy')),
            )
          else ...[
            Text(
              t(
                '笔记及文章 ${candidate.manifest.tables['notes']} · 文件 ${candidate.manifest.files.length - 1} · ${(candidate.sourceBytes / 1048576).toStringAsFixed(2)} MB',
                'Notes/articles ${candidate.manifest.tables['notes']} · files ${candidate.manifest.files.length - 1} · ${(candidate.sourceBytes / 1048576).toStringAsFixed(2)} MB',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _scope(candidate),
                  child: Text(t('查看范围', 'Review scope')),
                ),
                if (widget.canRestore)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            // Ownership transfers to the checked-file/confirmation workflow.
                            _checked.remove(entry.id);
                            await widget.restore(candidate);
                          }),
                    child: Text(t('从此快照恢复', 'Restore this copy')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
