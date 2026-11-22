import 'package:flutter/material.dart';
import '../../core/label_management_repository.dart';

Future<List<ManagedLabel>?> chooseLabels(
  BuildContext context, {
  required LabelManagementRepository repository,
  required String title,
  Set<int> exclude = const {},
  List<ManagedLabel> initial = const [],
  int maximum = 50,
  bool english = false,
}) => showDialog<List<ManagedLabel>>(
  context: context,
  builder: (_) => _Picker(
    repository: repository,
    title: title,
    exclude: exclude,
    initial: initial,
    maximum: maximum,
    english: english,
  ),
);

class _Picker extends StatefulWidget {
  const _Picker({
    required this.repository,
    required this.title,
    required this.exclude,
    required this.initial,
    required this.maximum,
    required this.english,
  });
  final LabelManagementRepository repository;
  final String title;
  final Set<int> exclude;
  final List<ManagedLabel> initial;
  final int maximum;
  final bool english;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _search = TextEditingController();
  late final _selected = {for (final item in widget.initial) item.id: item};
  List<ManagedLabel> _rows = [];
  bool _loading = true, _more = false;
  int _page = 0, _generation = 0;
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
      final result = await widget.repository.list(
        LabelManagementQuery(keyword: _keyword, page: more ? _page + 1 : 1),
      );
      if (!mounted || generation != _generation) return;
      final rows = more ? [..._rows, ...result.items] : result.items;
      if (rows.map((row) => row.id).toSet().length != rows.length ||
          (result.hasMore && result.items.isEmpty)) {
        throw const FormatException('Label list changed');
      }
      setState(() {
        _rows = rows;
        _page = result.page;
        _more = result.hasMore;
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: t('搜索标签', 'Search labels'),
              suffixIcon: IconButton(
                tooltip: t('搜索', 'Search'),
                onPressed: () {
                  _keyword = _search.text;
                  _load();
                },
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) {
              _keyword = _search.text;
              _load();
            },
          ),
          const SizedBox(height: 12),
          Text(
            t(
              '已选择${_selected.length}项 · 最多${widget.maximum}项',
              '${_selected.length} selected · maximum ${widget.maximum}',
            ),
          ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: () => _load(), child: Text(t('重试', 'Retry'))),
          ],
          for (final row in _rows)
            if (!widget.exclude.contains(row.id))
              CheckboxListTile(
                title: Text(row.name),
                value: _selected.containsKey(row.id),
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            if (_selected.length >= widget.maximum) {
                              _error = t('已达到选择上限', 'Selection limit reached');
                              return;
                            }
                            _selected[row.id] = row;
                          } else {
                            _selected.remove(row.id);
                          }
                          _error = null;
                        });
                      },
              ),
          if (_more)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: Text(t('加载更多', 'Load more')),
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: _loading || _error != null
            ? null
            : () => Navigator.pop(context, _selected.values.toList()),
        child: Text(t('确认选择', 'Use selection')),
      ),
    ],
  );
}
