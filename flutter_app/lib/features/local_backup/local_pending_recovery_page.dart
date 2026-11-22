import 'package:flutter/material.dart';
import '../../core/local_recovery_inventory.dart';

class LocalPendingRecoveryItem {
  const LocalPendingRecoveryItem({
    required this.title,
    required this.detail,
    required this.reference,
    this.open,
    this.actionLabel,
    this.archived = false,
  });
  final String title, detail;
  final String? actionLabel;
  final bool archived;
  final LocalRecoveryReference? reference;
  final Future<void> Function()? open;
}

class LocalPendingRecoveryView {
  const LocalPendingRecoveryView(this.summary, this.items);
  final LocalRecoverySummary summary;
  final List<LocalPendingRecoveryItem> items;
}

/// The resolver supplies only titles from verified owned local resources.
/// Unknown, unreadable, legacy-scope and orphan records remain blocked and kept.
class LocalPendingRecoveryPage extends StatefulWidget {
  const LocalPendingRecoveryPage({
    super.key,
    required this.load,
    this.english = false,
  });
  final Future<LocalPendingRecoveryView> Function() load;
  final bool english;
  @override
  State<LocalPendingRecoveryPage> createState() =>
      _LocalPendingRecoveryPageState();
}

class _LocalPendingRecoveryPageState extends State<LocalPendingRecoveryPage> {
  LocalPendingRecoveryView? _view;
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

  Future<void> _read() async {
    final view = await widget.load();
    if (mounted) setState(() => _view = view);
  }

  Future<void> _reload() => _run(_read);
  Widget _draftCard(LocalPendingRecoveryItem item) {
    final button = item.open == null
        ? null
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xff315fca),
              side: const BorderSide(color: Color(0xff315fca)),
              minimumSize: const Size(0, 48),
            ),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await item.open!();
                    await _read();
                  }),
            child: Text(item.actionLabel ?? t('打开编辑器', 'Open editor')),
          );
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xffe7f0ff),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: Color(0xff315fca),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(item.detail),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xffdce1e9)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final large = MediaQuery.textScalerOf(context).scale(16) > 21;
            if (button != null && constraints.maxWidth >= 300 && !large) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 10),
                  SizedBox(width: 120, child: button),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                if (button != null) ...[const SizedBox(height: 12), button],
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(t('本机草稿', 'Local drafts')),
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: view?.summary.needsAttention == false
                      ? const Color(0xffe4f4e7)
                      : const Color(0xfffff0ca),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _failed
                      ? t(
                          '暂时无法完成检查。已有恢复记录保留，请重试。',
                          'Check unavailable. Existing recovery records are retained.',
                        )
                      : view?.summary.needsAttention == false
                      ? t('未发现待处理的本机草稿。', 'No pending local drafts found.')
                      : t(
                          '未保存记录已保留，请先处理。',
                          'Unsaved records are retained. Resolve them first.',
                        ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              if (view != null) ...[
                if (view.items.any((item) => !item.archived))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      t('待处理', 'Pending'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                for (final item in view.items.where((item) => !item.archived))
                  _draftCard(item),
                if (view.items.any((item) => item.archived)) ...[
                  const SizedBox(height: 8),
                  Text(
                    t('已处理的旧文章草稿', 'Handled old article drafts'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xffe7f0ff),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t(
                        '原记录仅保留在此设备，不包含在备份中。',
                        'Original drafts stay on this device and are excluded from backups.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final item in view.items.where((item) => item.archived))
                    _draftCard(item),
                  Text(
                    t(
                      '旧稿仅供查阅，恢复需要明确操作。',
                      'Old drafts are read-only until you explicitly choose to restore.',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (view.summary.unknown > 0 ||
                    view.summary.activeTransfers > 0 ||
                    view.summary.overflow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      t(
                        '存在无法定位的记录、未完成传输或检查上限。保留所有记录，暂不能备份或恢复。',
                        'Some records cannot be located, transfers are active, or an inspection limit was reached. All records are kept; backup and restore remain blocked.',
                      ),
                    ),
                  ),
              ],
              Text(
                t(
                  '这里只检查本机恢复记录，不包含账号信息。',
                  'Only local recovery metadata is checked; account information is excluded.',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff0b57ee),
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _busy ? null : _reload,
                child: Text(t('重新检查', 'Check again')),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(t('返回', 'Back')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
