import 'package:flutter/material.dart';

import '../../core/note_list_query.dart';

Future<NoteListQuery?> showNoteFilterSheet(
  BuildContext context, {
  required NoteListQuery initial,
  required NoteListCapabilities capabilities,
  bool english = false,
}) => showModalBottomSheet<NoteListQuery>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .95,
  ),
  builder: (_) => NoteFilterSheet(
    initial: initial,
    capabilities: capabilities,
    english: english,
  ),
);

/// A staged immutable query. Only Apply returns a replacement; reset/typing
/// cannot mutate the caller's query, and Back/barrier dismiss returns null.
class NoteFilterSheet extends StatefulWidget {
  const NoteFilterSheet({
    super.key,
    required this.initial,
    required this.capabilities,
    this.english = false,
  });
  final NoteListQuery initial;
  final NoteListCapabilities capabilities;
  final bool english;
  @override
  State<NoteFilterSheet> createState() => _NoteFilterSheetState();
}

class _NoteFilterSheetState extends State<NoteFilterSheet> {
  late final TextEditingController _label;
  late NoteListQuery _staged;
  String? _error;
  bool _choosingDate = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _staged = widget.initial;
    _label = TextEditingController(text: _staged.label);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _staged = NoteListQuery(
        collection: widget.initial.collection,
        keyword: widget.initial.keyword,
      );
      _label.clear();
      _error = null;
    });
  }

  Future<void> _date() async {
    if (_choosingDate) return;
    _choosingDate = true;
    try {
      final selected = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_staged.createdDate) ?? DateTime.now(),
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
      );
      if (mounted && selected != null) {
        setState(
          () => _staged = _staged.copyWith(
            createdDate:
                '${selected.year.toString().padLeft(4, '0')}-'
                '${selected.month.toString().padLeft(2, '0')}-'
                '${selected.day.toString().padLeft(2, '0')}',
          ),
        );
      }
    } finally {
      _choosingDate = false;
    }
  }

  void _apply() {
    final query = _staged.copyWith(label: _label.text);
    try {
      query.requireSupported(widget.capabilities);
      Navigator.pop(context, query);
    } catch (_) {
      setState(() => _error = t('请核对筛选条件后重试', 'Check the filters and retry.'));
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
  @override
  Widget build(BuildContext context) {
    final capabilities = widget.capabilities;
    return SingleChildScrollView(
      key: const Key('note-filter-scroll'),
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('筛选笔记', 'Filter notes'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: t('返回', 'Back'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (capabilities.labels) ...[
            _heading(t('标签', 'Label')),
            TextField(
              key: const Key('note-filter-label'),
              controller: _label,
              decoration: InputDecoration(
                hintText: t('全部标签', 'All labels'),
                helperText: t('按完整标签名称筛选', 'Filter by the exact label name'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (capabilities.createdDate) ...[
            _heading(t('创建日期', 'Created on')),
            OutlinedButton.icon(
              key: const Key('note-filter-date'),
              onPressed: _date,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _staged.createdDate.isEmpty
                    ? t('不限日期', 'Any date')
                    : _staged.createdDate,
              ),
            ),
            if (_staged.createdDate.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(
                    () => _staged = _staged.copyWith(createdDate: ''),
                  ),
                  child: Text(t('清除日期', 'Clear date')),
                ),
              ),
          ],
          if (capabilities.pinned) ...[
            _heading(t('置顶', 'Pinned')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in NotePinFilter.values)
                  ChoiceChip(
                    key: ValueKey('note-filter-pin-${value.name}'),
                    label: Text(switch (value) {
                      NotePinFilter.all => t('全部', 'All'),
                      NotePinFilter.pinned => t('已置顶', 'Pinned'),
                      NotePinFilter.unpinned => t('未置顶', 'Not pinned'),
                    }),
                    selected: _staged.pin == value,
                    onSelected: (_) =>
                        setState(() => _staged = _staged.copyWith(pin: value)),
                  ),
              ],
            ),
          ],
          if (capabilities.visibility) ...[
            _heading(t('可见性', 'Visibility')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in NoteVisibilityFilter.values)
                  ChoiceChip(
                    key: ValueKey('note-filter-visibility-${value.name}'),
                    label: Text(switch (value) {
                      NoteVisibilityFilter.all => t('全部', 'All'),
                      NoteVisibilityFilter.private => t('私有', 'Private'),
                      NoteVisibilityFilter.public => t('公开', 'Public'),
                    }),
                    selected: _staged.visibility == value,
                    onSelected: (_) => setState(
                      () => _staged = _staged.copyWith(visibility: value),
                    ),
                  ),
              ],
            ),
          ],
          if (capabilities.hasCode) ...[
            _heading(t('内容', 'Content')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: const Key('note-filter-code'),
              value: _staged.hasCode,
              title: Text(t('仅含代码', 'Only items containing code')),
              subtitle: Text(
                t('按现有代码标记筛选', 'Uses the existing code-marker filter'),
              ),
              onChanged: (value) =>
                  setState(() => _staged = _staged.copyWith(hasCode: value)),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          // All actions remain in the same scroll surface when the keyboard or
          // large text leaves too little room for a fixed footer.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('返回', 'Back')),
              ),
              OutlinedButton(onPressed: _reset, child: Text(t('重置', 'Reset'))),
              FilledButton(
                key: const Key('note-filter-apply'),
                onPressed: _apply,
                child: Text(t('应用筛选', 'Apply filters')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
