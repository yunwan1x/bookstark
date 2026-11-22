import 'package:flutter/material.dart';
import '../../core/local_assistant_creation_receipts.dart';
import '../../widgets/bookstark_markdown.dart';

/// Read-only review. The owner must drain the originating save before opening.
/// Resolution callbacks re-read the receipt and compare the reviewed fingerprint.
class LocalAssistantSaveReviewPage extends StatefulWidget {
  const LocalAssistantSaveReviewPage({
    super.key,
    required this.inspect,
    required this.resolve,
    required this.onOpenResource,
    this.english = false,
  });
  final Future<LocalAssistantCreationInspection> Function() inspect;
  final Future<void> Function(LocalAssistantCreationInspection reviewed)
  resolve;
  final Future<void> Function(LocalAssistantCreationInspection reviewed)
  onOpenResource;
  final bool english;
  @override
  State<LocalAssistantSaveReviewPage> createState() => _ReviewState();
}

class _ReviewState extends State<LocalAssistantSaveReviewPage> {
  LocalAssistantCreationInspection? _review;
  bool _busy = true;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.inspect();
      if (mounted) {
        setState(() {
          _review = value;
          _busy = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t(
            '暂时无法核对，请重试。原资料和草稿已保留。',
            'Review unavailable. Your resources and draft are retained.',
          );
        });
      }
    }
  }

  Future<void> _act(bool open) async {
    final reviewed = _review;
    if (_busy || reviewed == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh = await widget.inspect();
      if (!mounted) return;
      if (fresh.fingerprint != reviewed.fingerprint) {
        setState(() {
          _review = fresh;
          _busy = false;
          _error = t(
            '资料状态已变化，请重新核对。',
            'The resource changed. Review it again.',
          );
        });
        return;
      }
      if (open) {
        await widget.onOpenResource(fresh);
        if (mounted) await _load();
      } else {
        await widget.resolve(fresh);
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t(
            '操作未完成，请重新核对。资料和草稿仍保留。',
            'Action incomplete. Review again. Your resources and draft are retained.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final absent = review?.state == LocalAssistantCreationResourceState.absent;
    final stateText = switch (review?.state) {
      LocalAssistantCreationResourceState.matching => t(
        '与上次保存内容一致',
        'Matches the saved content',
      ),
      LocalAssistantCreationResourceState.changed => t(
        '当前资料已变化，请核对最新内容',
        'The resource has changed. Review the current content',
      ),
      LocalAssistantCreationResourceState.missing => t(
        '找到保存记录，但资料已删除',
        'Save recorded; resource deleted',
      ),
      LocalAssistantCreationResourceState.protected => t(
        '资料已加密，请打开资料查看',
        'Resource protected. Open it to review',
      ),
      LocalAssistantCreationResourceState.formatChanged => t(
        '资料格式已变化，请打开资料查看',
        'Format changed. Open the resource to review',
      ),
      LocalAssistantCreationResourceState.unreadable => t(
        '无法完整读取当前资料，请打开资料检查',
        'Current content cannot be read completely. Open it to check',
      ),
      _ => t('原编辑草稿已保留，请确认后再处理。', 'Your original editor draft is retained.'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(t('核对保存结果', 'Review save result'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              t('本地空间', 'Local space'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xfffff2d6),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      absent
                          ? t('暂未找到保存记录', 'No save record found')
                          : t('上次保存结果待确认', 'Previous save needs review'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(stateText),
                  ],
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            if (review?.note case final note?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      BookstarkMarkdown(
                        data: String.fromCharCodes(
                          note.content.runes.take(24000),
                        ),
                      ),
                      if (note.content.runes.length > 24000)
                        Text(
                          t(
                            '这里只显示部分内容，请打开资料查看全文。',
                            'Preview shortened. Open the resource for the complete content.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (review?.task case final task?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(task.content),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy || review == null ? null : () => _act(false),
              child: Text(
                absent
                    ? t('放弃这次保存尝试', 'End this save attempt')
                    : t('确认已保存', 'Confirm saved'),
              ),
            ),
            if (!absent &&
                review != null &&
                review.state != LocalAssistantCreationResourceState.missing)
              OutlinedButton(
                onPressed: _busy ? null : () => _act(true),
                child: Text(t('打开资料', 'Open resource')),
              ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(t('重新核对', 'Review again')),
            ),
            Text(
              t('资料与草稿都会保留', 'Resources and drafts are retained'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
