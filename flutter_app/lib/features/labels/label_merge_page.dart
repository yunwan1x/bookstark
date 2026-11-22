import 'package:flutter/material.dart';
import '../../core/label_management_repository.dart';
import 'label_picker_dialog.dart';

class LabelMergePage extends StatefulWidget {
  const LabelMergePage({
    super.key,
    required this.repository,
    required this.target,
    this.english = false,
    this.local = false,
  });
  final LabelManagementRepository repository;
  final ManagedLabel target;
  final bool english, local;
  @override
  State<LabelMergePage> createState() => _LabelMergePageState();
}

class _LabelMergePageState extends State<LabelMergePage> {
  late ManagedLabel _target = widget.target;
  final _selected = <int, ManagedLabel>{};
  final _search = TextEditingController();
  List<ManagedLabel> _rows = [];
  int _page = 0, _generation = 0;
  bool _loading = true,
      _busy = false,
      _more = false,
      _needsVerify = false,
      _allowLeave = false;
  String _keyword = '';
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.list(
        LabelManagementQuery(keyword: _keyword, page: more ? _page + 1 : 1),
      );
      if (!mounted || generation != _generation) return;
      final rows = more ? [..._rows, ...page.items] : page.items;
      if (rows.map((item) => item.id).toSet().length != rows.length ||
          (page.hasMore && page.items.isEmpty)) {
        throw const FormatException('Labels changed; reload');
      }
      setState(() {
        _rows = rows;
        _page = page.page;
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeTarget() async {
    final picked = await chooseLabels(
      context,
      repository: widget.repository,
      title: t('选择保留的目标标签', 'Choose target to retain'),
      maximum: 1,
      english: widget.english,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _target = picked.single;
      _selected.remove(_target.id);
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final target = await widget.repository.read(_target.id);
      final present = <int, ManagedLabel>{};
      var index = 1;
      while (true) {
        final page = await widget.repository.list(
          LabelManagementQuery(page: index),
        );
        for (final item in page.items) {
          if (_selected.containsKey(item.id)) present[item.id] = item;
        }
        if (!page.hasMore) break;
        if (page.items.isEmpty) {
          throw const FormatException('Invalid label page');
        }
        index++;
      }
      if (!mounted) return;
      final missing = _selected.keys
          .where((id) => !present.containsKey(id))
          .length;
      setState(() {
        _target = target.label;
        _selected.removeWhere((id, _) => !present.containsKey(id));
        _selected.addAll(present);
        _needsVerify = false;
        _error = missing > 0
            ? t(
                '$missing个源标签已不存在，请返回目标详情核对关联；未自动确认上次合并成功。',
                '$missing source labels are unavailable. Inspect target associations; previous merge is unconfirmed.',
              )
            : t(
                '目标和源标签仍存在，请检查后再提交。',
                'Target and sources still exist; review before submitting again.',
              );
      });
      await _load();
      // Keep the verification outcome visible after the list refresh.
      if (mounted) {
        setState(
          () => _error = missing > 0
              ? t(
                  '$missing个源标签已不存在，请核对目标关联。',
                  '$missing source labels are unavailable; inspect target associations.',
                )
              : t(
                  '已重新核对，请检查后再提交。',
                  'Verified again; review before submitting.',
                ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    if (_busy ||
        _loading ||
        _needsVerify ||
        !widget.repository.canManage ||
        _selected.isEmpty) {
      return;
    }
    final target = _target, sources = List<ManagedLabel>.of(_selected.values);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('确认合并标签？', 'Confirm label merge?')),
        content: Text(
          t(
            '将${sources.length}个源标签合并至“${target.name}”。源标签会永久移除，源资源保留。影响${widget.local ? '本地空间' : '全服务器'}。',
            'Merge ${sources.length} source labels into “${target.name}”. Source labels are permanently removed; resources remain. Affects ${widget.local ? 'this space' : 'the whole server'}.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('确认合并', 'Merge')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.merge(
        target.id,
        sources.map((item) => item.id).toList(),
      );
      if (mounted) {
        setState(() => _allowLeave = true);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _needsVerify = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_selected.isNotEmpty || _needsVerify) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('离开标签合并？', 'Leave label merge?')),
          content: Text(
            _needsVerify
                ? t(
                    '上次提交结果尚未核对，返回后请先检查目标关联。',
                    'Previous submission is unverified; inspect the target before retrying.',
                  )
                : t(
                    '选择尚未提交，离开将放弃选择。',
                    'Selections have not been submitted and will be discarded.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续选择', 'Keep selecting')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('离开', 'Leave')),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _allowLeave = true);
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(t('合并标签', 'Merge labels'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xffeff6ff),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t(
                    '合并会移除源标签，关联资源归入目标标签。源资源保留。',
                    'Merging removes source labels and moves associations into the target. Resources are retained.',
                  ),
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
                      t('保留的目标标签', 'Target label to retain'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(_target.name),
                          avatar: const Icon(Icons.sell_outlined),
                        ),
                        TextButton(
                          onPressed: _busy || _needsVerify
                              ? null
                              : _changeTarget,
                          child: Text(t('换一个', 'Change')),
                        ),
                      ],
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('待合并的源标签', 'Source labels to merge'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        '已选择${_selected.length}项 · 最多100项',
                        '${_selected.length} selected · maximum 100',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in _selected.values)
                          InputChip(
                            label: Text(item.name),
                            onDeleted: _busy || _needsVerify
                                ? null
                                : () =>
                                      setState(() => _selected.remove(item.id)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      enabled: !_busy && !_needsVerify,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: t('搜索源标签', 'Search source labels'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: t('搜索', 'Search'),
                          onPressed: _busy || _needsVerify
                              ? null
                              : () {
                                  _keyword = _search.text;
                                  _load();
                                },
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                      onSubmitted: (_) {
                        _keyword = _search.text;
                        _load();
                      },
                    ),
                    for (final item in _rows)
                      if (item.id != _target.id)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          value: _selected.containsKey(item.id),
                          onChanged:
                              _busy ||
                                  _loading ||
                                  _needsVerify ||
                                  !widget.repository.canManage
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      if (_selected.length >= 100) {
                                        _error = t(
                                          '最多选择100个源标签',
                                          'Choose at most 100 sources',
                                        );
                                        return;
                                      }
                                      _selected[item.id] = item;
                                    } else {
                                      _selected.remove(item.id);
                                    }
                                  });
                                },
                        ),
                    if (_more)
                      TextButton(
                        onPressed: _busy || _loading || _needsVerify
                            ? null
                            : () => _load(more: true),
                        child: Text(t('加载更多', 'Load more')),
                      ),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_needsVerify)
              OutlinedButton(
                onPressed: _busy ? null : _verify,
                child: Text(t('重新核对目标和源标签', 'Verify target and source labels')),
              ),
            if (!widget.repository.canManage)
              Text(t('仅管理员可以合并标签', 'Only administrators can merge labels')),
            const SizedBox(height: 24),
            Text(
              t(
                '确认后将执行一次服务器事务。',
                'Confirmation submits one server transaction.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  _busy ||
                      _loading ||
                      _needsVerify ||
                      _selected.isEmpty ||
                      !widget.repository.canManage
                  ? null
                  : _merge,
              child: Text(t('检查并合并', 'Review and merge')),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    ),
  );
}
