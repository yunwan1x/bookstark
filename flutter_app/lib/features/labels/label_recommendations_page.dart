import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/label_management_repository.dart';
import 'label_picker_dialog.dart';

class LabelRecommendationsPage extends StatefulWidget {
  const LabelRecommendationsPage({
    super.key,
    required this.repository,
    this.english = false,
    this.local = false,
  });
  final LabelManagementRepository repository;
  final bool english, local;
  @override
  State<LabelRecommendationsPage> createState() =>
      _LabelRecommendationsPageState();
}

class _LabelRecommendationsPageState extends State<LabelRecommendationsPage> {
  final _size = TextEditingController();
  LabelRecommendationStrategy _strategy = LabelRecommendationStrategy.recent;
  List<String> _manual = [];
  List<ManagedLabel>? _preview;
  LabelRecommendationSettings? _saved;
  bool _loading = true, _busy = false, _previewing = false, _allowLeave = false;
  int _generation = 0;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _editable => widget.repository.canManage;
  LabelRecommendationSettings get _value => LabelRecommendationSettings(
    strategy: _strategy,
    manualLabels: List.of(_manual),
    pageSize: int.tryParse(_size.text) ?? 0,
  );
  bool get _dirty =>
      _saved != null &&
      (_saved!.strategy != _strategy ||
          _saved!.pageSize.toString() != _size.text ||
          !listEquals(_saved!.manualLabels, _manual));
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _size.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.repository.recommendationSettings();
      if (!mounted) return;
      setState(() {
        _saved = value;
        _strategy = value.strategy;
        _manual = List.of(value.manualLabels);
        _size.text = '${value.pageSize}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose() async {
    final picked = await chooseLabels(
      context,
      repository: widget.repository,
      title: t('添加精选标签', 'Add selected labels'),
      maximum: 50,
      english: widget.english,
    );
    if (!mounted || picked == null) return;
    final names = {..._manual, ...picked.map((item) => item.name)}.toList();
    if (names.length > 50) {
      setState(() => _error = t('精选最多50项', 'Choose at most 50 labels'));
      return;
    }
    _change(() => _manual = names);
  }

  Future<void> _generatePreview() async {
    final value = _value;
    try {
      value.writeBody();
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final generation = ++_generation;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final result = await widget.repository.recommendations(value);
      if (mounted && generation == _generation) {
        setState(() => _preview = result);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _previewing = false);
      }
    }
  }

  void _change(VoidCallback update) {
    _generation++;
    setState(() {
      update();
      _preview = null;
      _previewing = false;
    });
  }

  Future<void> _save() async {
    if (!_editable || _busy || _saved == null) return;
    final value = _value;
    try {
      value.writeBody();
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveRecommendationSettings(value);
      final stored = await widget.repository.recommendationSettings();
      if (mounted) {
        setState(() {
          _saved = stored;
          _strategy = stored.strategy;
          _manual = List.of(stored.manualLabels);
          _size.text = '${stored.pageSize}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('放弃未保存的推荐设置？', 'Discard unsaved recommendations?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续编辑', 'Keep editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('放弃', 'Discard')),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _allowLeave = true);
    Navigator.pop(context);
  }

  String _strategyName(LabelRecommendationStrategy value) => switch (value) {
    LabelRecommendationStrategy.recent =>
      widget.local
          ? t('最近更新资源', 'Recently updated resources')
          : t('最近90天使用', 'Used in the last 90 days'),
    LabelRecommendationStrategy.total => t('三类关联总数', 'Three-type total'),
    LabelRecommendationStrategy.book => t('书籍使用', 'Book usage'),
    LabelRecommendationStrategy.bookmark => t('书签使用', 'Bookmark usage'),
    LabelRecommendationStrategy.manual => t('手动精选', 'Manual selection'),
  };
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(t('推荐设置', 'Recommendations')),
        actions: [
          if (_editable)
            TextButton(
              onPressed: _busy || _loading || _saved == null ? null : _save,
              child: Text(t('保存', 'Save')),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.local
                          ? t('当前本地空间', 'Current local space')
                          : t('全服务器共享', 'Shared across the server'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.local
                          ? t(
                              '只影响当前空间内的标签推荐。',
                              'Only affects recommendations in this local space.',
                            )
                          : t(
                              '保存后会影响所有用户的标签推荐。',
                              'Saving affects label recommendations for all users.',
                            ),
                    ),
                    if (!_editable)
                      Text(
                        t(
                          '仅管理员可以修改；可预览当前设置。',
                          'Only administrators can edit; preview remains available.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_saved == null)
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: Text(t('重试', 'Retry')),
                ),
            ],
            if (_loading || _busy)
              const Center(child: CircularProgressIndicator()),
            if (_saved != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('推荐策略', 'Strategy'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<LabelRecommendationStrategy>(
                        key: ValueKey(_strategy),
                        initialValue: _strategy,
                        isExpanded: true,
                        items: [
                          for (final value
                              in LabelRecommendationStrategy.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(_strategyName(value)),
                            ),
                        ],
                        onChanged: !_editable || _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  _change(() => _strategy = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.local &&
                                _strategy == LabelRecommendationStrategy.recent
                            ? t(
                                '本地旧数据没有关联时间，按最近90天源资源修改时间计算。',
                                'Legacy local labels have no association timestamps; uses resource updates from the last 90 days.',
                              )
                            : t(
                                '按所选策略计算真实标签推荐。',
                                'Uses real label counts for this strategy.',
                              ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _size,
                        enabled: _editable && !_busy,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _change(() {}),
                        decoration: InputDecoration(
                          labelText: t('推荐数量', 'Number of recommendations'),
                          helperText: '1—50',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('手动精选', 'Manual selection'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in _manual)
                            InputChip(
                              label: Text(name),
                              onDeleted: _editable && !_busy
                                  ? () => _change(() => _manual.remove(name))
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _editable && !_busy ? _choose : null,
                        icon: const Icon(Icons.add),
                        label: Text(t('添加标签', 'Add labels')),
                      ),
                      Text(
                        t(
                          '仅“手动精选”策略使用。',
                          'Used only for the manual selection strategy.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy || _previewing ? null : _generatePreview,
                child: Text(t('预览推荐', 'Preview recommendations')),
              ),
              Text(t('预览不会保存设置。', 'Preview does not save settings.')),
              if (_previewing) const Center(child: CircularProgressIndicator()),
              if (_preview != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('推荐预览', 'Preview'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_preview!.isEmpty)
                          Text(
                            t(
                              '当前策略暂无推荐',
                              'No recommendations for this strategy',
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final row in _preview!)
                              Chip(label: Text(row.name)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}
