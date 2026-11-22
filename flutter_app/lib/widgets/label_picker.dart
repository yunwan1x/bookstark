import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/labels_repository.dart';

/// Selection stays local until the owning resource form is explicitly saved.
Future<List<String>?> showLabelPicker(
  BuildContext context, {
  required LabelsRepository repository,
  required List<String> selected,
  bool english = false,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _LabelPicker(
    repository: repository,
    selected: selected,
    english: english,
  ),
);

class _LabelPicker extends StatefulWidget {
  const _LabelPicker({
    required this.repository,
    required this.selected,
    required this.english,
  });
  final LabelsRepository repository;
  final List<String> selected;
  final bool english;
  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  final _input = TextEditingController();
  late final Set<String> _selected = widget.selected.toSet();
  List<String> _matches = [];
  String? _error;
  bool _loading = true, _more = false;
  int _page = 1, _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search({bool more = false}) async {
    final generation = ++_generation;
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.search(_input.text, page: page);
      if (!mounted || generation != _generation) return;
      setState(() {
        _matches = {...(more ? _matches : <String>[]), ...rows}.toList();
        _page = page;
        _more = rows.isNotEmpty;
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

  void _add() {
    final name = _input.text.trim();
    if (name.isEmpty ||
        utf8.encode(name).length > 100 ||
        name.contains(RegExp('[,，]'))) {
      setState(
        () => _error = t(
          '新标签需1—100字节且不含逗号',
          'New label: 1–100 UTF-8 bytes, no commas',
        ),
      );
      return;
    }
    setState(() {
      _selected.add(name);
      _error = null;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('添加标签', 'Choose labels')),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _input,
              decoration: InputDecoration(
                labelText: t('搜索或输入新标签', 'Search or enter a label'),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => _search(),
                  child: Text(t('搜索', 'Search')),
                ),
                TextButton(
                  onPressed: _add,
                  child: Text(t('使用新标签', 'Use new label')),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: _selected
                  .map(
                    (name) => InputChip(
                      label: Text(name),
                      onDeleted: () => setState(() => _selected.remove(name)),
                    ),
                  )
                  .toList(),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ..._matches.map(
              (name) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                value: _selected.contains(name),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(name);
                  } else {
                    _selected.remove(name);
                  }
                }),
              ),
            ),
            if (_more)
              TextButton(
                onPressed: _loading ? null : () => _search(more: true),
                child: Text(t('加载更多', 'Load more')),
              ),
            if (!_loading && _matches.isEmpty && _error == null)
              Text(t('没有匹配标签', 'No matching labels')),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selected.toList()),
        child: Text(t('应用', 'Apply')),
      ),
    ],
  );
}
