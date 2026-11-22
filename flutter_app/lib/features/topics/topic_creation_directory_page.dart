import 'package:flutter/material.dart';
import '../../core/topic_creation_attempt.dart';
import '../../core/topic_creation_directory.dart';

class TopicCreationDirectoryPage extends StatefulWidget {
  const TopicCreationDirectoryPage({
    super.key,
    required this.directory,
    required this.onOpen,
    this.english = false,
  });
  final TopicCreationDirectory directory;
  final Future<void> Function(BuildContext, TopicCreationDirectoryEntry) onOpen;
  final bool english;
  @override
  State<TopicCreationDirectoryPage> createState() =>
      _TopicCreationDirectoryPageState();
}

class _TopicCreationDirectoryPageState
    extends State<TopicCreationDirectoryPage> {
  List<TopicCreationDirectoryEntry> _rows = [];
  bool _loading = true, _opening = false;
  int _generation = 0;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TopicCreationDirectoryPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.directory, widget.directory)) {
      _rows = [];
      _opening = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation, source = widget.directory;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await source.list();
      if (!mounted ||
          generation != _generation ||
          !identical(source, widget.directory)) {
        return;
      }
      setState(() => _rows = rows);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = [];
          _error = t(
            '恢复索引不可用，未省略或更改记录',
            'Recovery index unavailable. No records were omitted or changed.',
          );
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(TopicCreationDirectoryEntry entry) async {
    if (_opening) return;
    final generation = _generation,
        source = widget.directory,
        open = widget.onOpen;
    setState(() => _opening = true);
    try {
      source.guard();
      await open(context, entry);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = t(
            '恢复未完成，记录已保留',
            'Recovery incomplete. Record retained.',
          ),
        );
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          identical(source, widget.directory)) {
        setState(() => _opening = false);
        await _load();
      }
    }
  }

  String _phase(TopicCreationDirectoryEntry e) =>
      e.phase == TopicCreationPhase.pending
      ? t('尚未发送', 'Not submitted')
      : e.phase == TopicCreationPhase.unknown
      ? t('结果未知，不自动重发', 'Unknown result. No replay.')
      : e.phase == TopicCreationPhase.knownID
      ? t('已取得 ID，仅存储恢复', 'Known ID. Storage recovery only.')
      : t('记录保存待核对', 'Record storage requires review');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('创建恢复记录', 'Creation recovery records')),
      actions: [
        IconButton(
          onPressed: _loading || _opening ? null : _load,
          tooltip: t('重新读取', 'Reload'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t('仅当前账号 · 不自动重发', 'Current account only · No automatic replay')),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _error == null && _rows.isEmpty)
          Text(t('没有恢复记录', 'No recovery records')),
        for (final e in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.kind?.name ?? t('恢复记录', 'Recovery record')} · ${e.topicId ?? 0}',
                  ),
                  Text(_phase(e)),
                  if (e.target != null && e.target!.isNotEmpty)
                    Text('${e.target!} ${e.targetId}'),
                  if (e.actualId != null) Text('ID ${e.actualId}'),
                  FilledButton(
                    onPressed: _opening || _loading ? null : () => _open(e),
                    child: Text(t('打开恢复记录', 'Open recovery record')),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
