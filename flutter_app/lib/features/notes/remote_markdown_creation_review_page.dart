import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

import '../../core/remote_markdown_creation_controller.dart';
import '../../core/remote_markdown_creation_vault.dart';

/// Standalone recovery component. It never calls save/submit or mutates SQL.
/// Caller owns controller/transport retirement and the actual editor route.
class RemoteMarkdownCreationReviewPage extends StatefulWidget {
  const RemoteMarkdownCreationReviewPage({
    super.key,
    required this.controller,
    this.english = false,
    this.onOpenSaved,
  });
  final RemoteMarkdownCreationController controller;
  final bool english;
  final Future<void> Function(int id)? onOpenSaved;
  @override
  State<RemoteMarkdownCreationReviewPage> createState() => _ReviewState();
}

class _ReviewState extends State<RemoteMarkdownCreationReviewPage> {
  final _id = TextEditingController();
  bool _checking = false,
      _busy = false,
      _localRead = false,
      _serverRead = false;
  String? _error;
  RemoteMarkdownCreationController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (c.failure != null) {
        _error = t(
          '无法完成操作，记录已保留。',
          'Could not finish. The record is retained.',
        );
      }
    } catch (_) {
      if (mounted) {
        _error = t(
          '无法完成操作，记录已保留。',
          'Could not finish. The record is retained.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _view(
    MarkdownCreationInput input, {
    required bool server,
  }) async {
    final fingerprint = server
        ? c.observed?.fingerprint
        : c.record.input.fingerprint;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _FullSnapshotPage(input: input, english: widget.english),
      ),
    );
    if (!mounted || done != true) return;
    setState(() {
      if (server && fingerprint == c.observed?.fingerprint) _serverRead = true;
      if (!server && fingerprint == c.record.input.fingerprint) {
        _localRead = true;
      }
    });
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget _banner(String text, Color color) => _card(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
  Widget _snapshot(
    String title,
    MarkdownCreationInput input, {
    required bool server,
  }) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(input.title),
        Wrap(
          spacing: 6,
          children: input.labels
              .take(8)
              .map((label) => Chip(label: Text(label)))
              .toList(),
        ),
        BookstarkMarkdown(
          data: _chunk(input.content, 0).$1,
          english: widget.english,
          onLink: (_, _) async {},
          imageBuilder: (_, _, alt) =>
              Text(alt ?? t('图片引用', 'Image reference')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _view(input, server: server),
          child: Text(t('查看完整快照', 'View full snapshot')),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final phase = c.phase, observed = c.observed;
    final cleanup = phase == MarkdownCreationPhase.cleanup;
    final finished = phase == MarkdownCreationPhase.finished;
    final review = phase == MarkdownCreationPhase.review && observed != null;
    final title = finished
        ? t('已完成', 'Finished')
        : cleanup
        ? t('已保存资料', 'Saved note')
        : review
        ? t('核对两个版本', 'Review both versions')
        : _checking
        ? t('核对已保存资料', 'Check saved note')
        : t('新建结果未知', 'Result unknown');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              Text(
                '${c.record.scope.server} · ${t('账号 ', 'Owner ')}${c.record.scope.memberId} · ${c.record.scope.collection} · Markdown',
              ),
            ),
            if (_error != null) _banner(_error!, Colors.red),
            if (finished)
              _banner(
                t(
                  '本机记录已清理，服务器资料未被修改。',
                  'Device record cleared. Server content was not changed.',
                ),
                Colors.green,
              )
            else if (cleanup) ...[
              _banner(
                t('已确认资料 ID：', 'Confirmed saved ID: ') +
                    c.record.knownId.toString(),
                Colors.green,
              ),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('本机记录清理未完成', 'Device record cleanup pending')),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _action(c.retryCleanup),
                      child: Text(t('仅重试清理', 'Retry cleanup only')),
                    ),
                    Text(t('不会再次请求新建。', 'No second create request.')),
                  ],
                ),
              ),
            ] else if (review) ...[
              _banner(
                t(
                  '如服务器版本变化，必须重新核对。',
                  'If the server version changes, review again.',
                ),
                Colors.amber.shade800,
              ),
              _snapshot(
                t('本机完整草稿', 'Your saved draft'),
                c.record.input,
                server: false,
              ),
              _snapshot(
                t('服务器资料 ID：', 'Server note · ID ') + observed.id.toString(),
                observed.input,
                server: true,
              ),
              _card(
                Text(
                  t(
                    '选择已有资料不证明它由上次请求创建；采用后仅清理本机记录，不覆盖服务器内容或标签。',
                    'Selecting a note does not prove which request created it. Adoption clears this device record without overwriting server content or labels.',
                  ),
                ),
              ),
              FilledButton(
                onPressed: _busy || !_localRead || !_serverRead
                    ? null
                    : () => _action(() async {
                        c.markReviewed(observed);
                        await c.adopt();
                        _serverRead = false;
                      }),
                child: Text(t('使用这份已保存资料', 'Use this saved note')),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        _serverRead = false;
                        await c.inspect(observed.id);
                      }),
                child: Text(t('重新读取服务器版本', 'Read latest version')),
              ),
              if (widget.onOpenSaved != null && c.record.knownId != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() => widget.onOpenSaved!(observed.id)),
                  child: Text(
                    t('打开已保存资料处理标签', 'Open saved note to finish labels'),
                  ),
                ),
            ] else ...[
              _banner(
                t('请求可能已经创建资料，不能再次新建。', 'The request may have created a note.'),
                Colors.amber.shade800,
              ),
              if (!_checking) ...[
                _snapshot(
                  t('本机完整草稿', 'Your saved draft'),
                  c.record.input,
                  server: false,
                ),
                FilledButton(
                  onPressed: null,
                  child: Text(t('再次创建', 'Create again')),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _checking = true;
                          if (c.record.knownId != null) {
                            _id.text = c.record.knownId.toString();
                          }
                        }),
                  child: Text(t('核对明确 ID', 'Check an existing ID')),
                ),
              ] else ...[
                TextField(
                  controller: _id,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('明确资料 ID', 'Exact note ID'),
                    helperText: t(
                      '标题不能识别这次请求。',
                      'A title cannot identify this request.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          final id = int.tryParse(_id.text.trim());
                          if (id == null || id <= 0) {
                            throw const FormatException('Positive ID required');
                          }
                          _serverRead = false;
                          await c.inspect(id);
                        }),
                  child: Text(t('读取资料', 'Read note')),
                ),
                _card(
                  Text(
                    t(
                      '必须匹配当前服务器、账号、集合和 Markdown 格式，并且没有密码。',
                      'Server, owner, collection and ordinary Markdown format must match.',
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy ? null : () => Navigator.maybePop(context),
              child: Text(
                finished
                    ? t('返回', 'Return')
                    : t('返回并保留记录', 'Return and keep record'),
              ),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// Exact UTF16 chunks with surrogate-safe boundaries; no source bytes are lost.
(String, int) _chunk(String source, int start) {
  var end = start + 12000;
  if (end > source.length) end = source.length;
  if (end < source.length && end > start) {
    final unit = source.codeUnitAt(end - 1);
    if (unit >= 0xd800 && unit <= 0xdbff) end--;
  }
  return (source.substring(start, end), end);
}

class _FullSnapshotPage extends StatefulWidget {
  const _FullSnapshotPage({required this.input, required this.english});
  final MarkdownCreationInput input;
  final bool english;
  @override
  State<_FullSnapshotPage> createState() => _FullSnapshotState();
}

class _FullSnapshotState extends State<_FullSnapshotPage> {
  int start = 0;
  final starts = <int>[0];
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  Widget build(BuildContext context) {
    final snapshot =
        '${jsonEncode({'title': widget.input.title, 'labels': widget.input.labels})}\n\n${widget.input.content}';
    final chunk = _chunk(snapshot, start);
    return Scaffold(
      appBar: AppBar(title: Text(t('完整只读快照', 'Complete read-only snapshot'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SelectableText(chunk.$1),
            if (starts.length > 1)
              OutlinedButton(
                onPressed: () => setState(() {
                  starts.removeLast();
                  start = starts.last;
                }),
                child: Text(t('上一段', 'Previous section')),
              ),
            if (chunk.$2 < snapshot.length)
              FilledButton(
                onPressed: () => setState(() {
                  start = chunk.$2;
                  starts.add(start);
                }),
                child: Text(t('下一段', 'Next section')),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('已查看完整快照', 'I reviewed the complete snapshot')),
              ),
          ],
        ),
      ),
    );
  }
}
