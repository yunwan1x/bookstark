import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/spreadsheet_document.dart';
import '../../core/spreadsheet_calculation.dart';
import 'spreadsheet_grid.dart';

/// Editing surface only. Persistence belongs to the typed note controller;
/// absence of a successful commit must never be displayed as "saved".
class SpreadsheetEditor extends StatefulWidget {
  const SpreadsheetEditor({
    super.key,
    required this.document,
    required this.onChanged,
    this.readOnly = false,
    this.calculation,
  });
  final SpreadsheetDocument document;
  final SpreadsheetCalculationResult? calculation;
  final ValueChanged<SpreadsheetDocument> onChanged;
  final bool readOnly;
  @override
  State<SpreadsheetEditor> createState() => _SpreadsheetEditorState();
}

class _SpreadsheetEditorState extends State<SpreadsheetEditor> {
  late SpreadsheetDocument _document;
  late String _sheetId;
  SheetAddress _selected = const SheetAddress(0, 0);
  final _undo = <SpreadsheetDocument>[], _redo = <SpreadsheetDocument>[];
  final _formula = TextEditingController(), _formulaFocus = FocusNode();
  final _vertical = ScrollController(), _horizontal = ScrollController();
  bool _inputDirty = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _sheetId = (_visible.isEmpty ? _document.sheets.first : _visible.first).id;
    _syncInput();
  }

  List<SpreadsheetSheet> get _visible =>
      _document.sheets.where((s) => !s.hidden).toList();
  SpreadsheetSheet get _sheet => _document.sheet(_sheetId);
  @override
  void didUpdateWidget(SpreadsheetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document) &&
        !identical(widget.document, _document)) {
      _document = widget.document;
      _undo.clear();
      _redo.clear();
      if (!_visible.any((s) => s.id == _sheetId)) {
        _sheetId =
            (_visible.isEmpty ? _document.sheets.first : _visible.first).id;
      }
      _selected = const SheetAddress(0, 0);
      _syncInput();
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _formula.dispose();
    _formulaFocus.dispose();
    super.dispose();
  }

  void _syncInput() {
    final cell = _sheet.cell(_selected);
    _formula.text = cell.formula ?? cell.text;
    _inputDirty = false;
  }

  void _trimHistory() {
    var units = 0;
    for (final item in [..._undo, ..._redo]) {
      units += item.source.length;
    }
    // UTF-16 storage plus object overhead: keep snapshots bounded independently
    // of number of edits. The live document is retained separately.
    while (units > 5 * 1024 * 1024 || _undo.length + _redo.length > 40) {
      final history = _undo.isNotEmpty ? _undo : _redo;
      units -= history.removeAt(0).source.length;
    }
  }

  void _change(SpreadsheetDocument next, {bool history = true}) {
    if (identical(next, _document)) return;
    setState(() {
      if (history) {
        _undo.add(_document);
        _redo.clear();
        _trimHistory();
      }
      _document = next;
      _error = null;
      if (!_visible.any((s) => s.id == _sheetId)) {
        _sheetId =
            (_visible.isEmpty ? _document.sheets.first : _visible.first).id;
        _selected = const SheetAddress(0, 0);
      }
      _syncInput();
    });
    widget.onChanged(next);
  }

  void _attempt(SpreadsheetDocument Function() action) {
    try {
      _change(action());
    } on FormatException {
      setState(() => _error = '输入无效，请检查名称或单元格内容');
    } on UnsupportedError {
      setState(() => _error = '此操作需要公式或富文本兼容处理，原始内容已保留');
    }
  }

  // Until the native evaluator is connected, no scalar edit may invalidate
  // existing formula caches. Formula inputs are never saved as fake results.
  bool get _hasFormulas {
    for (final sheet in _document.sheets) {
      final matrix = sheet.raw['cellData'];
      if (matrix is! Map) continue;
      for (final row in matrix.values) {
        if (row is! Map) continue;
        for (final cell in row.values) {
          if (cell is Map && (cell['f'] != null || cell['si'] != null)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool get _canInput {
    final cell = _sheet.cell(_selected);
    return !widget.readOnly &&
        !_hasFormulas &&
        !cell.requiresRichTextEditor &&
        !cell.hasSharedFormula &&
        !cell.hasOpaqueInput;
  }

  void _commitInput() {
    if (!_inputDirty) return;
    if (!_canInput || _formula.text.startsWith('=')) {
      setState(() => _error = '公式计算尚未接线，此输入未应用');
      return;
    }
    final text = _formula.text;
    Object? value = text.isEmpty ? null : text;
    if (text.startsWith("'")) {
      value = text.substring(1);
    } else if (text.toUpperCase() == 'TRUE' || text.toUpperCase() == 'FALSE') {
      value = text.toUpperCase() == 'TRUE';
    } else if (RegExp(
      r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$',
    ).hasMatch(text)) {
      final number = num.tryParse(text);
      if (number != null && number.isFinite) value = number;
    }
    _attempt(() => _document.withCellValue(_sheetId, _selected, value));
    // Unchanged input still ends the explicit edit session.
    if (_sheet.cell(_selected).text == text) setState(_syncInput);
  }

  bool _leaveInput() {
    if (!_inputDirty) return true;
    _commitInput();
    return !_inputDirty;
  }

  void _select(SheetAddress address, {bool edit = false}) {
    if (!_leaveInput()) return;
    setState(() {
      _selected = address;
      _error = null;
      _syncInput();
    });
    if (edit && _canInput) _formulaFocus.requestFocus();
  }

  void _history(bool redo) {
    if (!_leaveInput()) return;
    final from = redo ? _redo : _undo, to = redo ? _undo : _redo;
    if (from.isEmpty) return;
    to.add(_document);
    _change(from.removeLast(), history: false);
  }

  Future<void> _locate() async {
    if (!_leaveInput()) return;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _SheetTextDialog(
        title: '定位单元格',
        label: '地址，例如 B4',
        initial: _selected.a1,
        action: '定位',
      ),
    );
    if (!mounted || value == null) return;
    try {
      final address = SheetAddress.parse(value.trim());
      _sheet.cell(address);
      _select(_sheet.mergeAt(address)?.anchor ?? address);
      if (_vertical.hasClients) {
        _vertical.jumpTo(
          SpreadsheetGrid.axisOffset(
            _sheet,
            _selected.row,
            true,
          ).clamp(0, _vertical.position.maxScrollExtent),
        );
      }
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(
          SpreadsheetGrid.axisOffset(
            _sheet,
            _selected.column,
            false,
          ).clamp(0, _horizontal.position.maxScrollExtent),
        );
      }
    } on FormatException {
      setState(() => _error = '地址不在当前工作表内');
    }
  }

  Future<void> _format() async {
    if (!_leaveInput()) return;
    final patch = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormatPanel(
        address: _selected.a1,
        style: _document.cellStyle(_sheetId, _selected),
      ),
    );
    if (!mounted || patch == null) return;
    _attempt(() => _document.withCellStyle(_sheetId, _selected, patch));
  }

  Future<void> _sheets() async {
    if (!_leaveInput()) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '工作表',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView(
                  children: _document.sheets
                      .map(
                        (sheet) => ListTile(
                          leading: Icon(
                            sheet.id == _sheetId
                                ? Icons.check_circle
                                : sheet.hidden
                                ? Icons.visibility_off_outlined
                                : Icons.table_chart_outlined,
                            color: sheet.id == _sheetId
                                ? SpreadsheetGrid.blue
                                : null,
                          ),
                          title: Text(sheet.name),
                          subtitle: sheet.hidden ? const Text('已隐藏') : null,
                          onTap: sheet.hidden
                              ? null
                              : () {
                                  setState(() {
                                    _sheetId = sheet.id;
                                    _selected = const SheetAddress(0, 0);
                                    _syncInput();
                                  });
                                  Navigator.pop(sheetContext);
                                },
                          trailing: widget.readOnly
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'rename') {
                                      final name = await _nameDialog(
                                        sheet.name,
                                      );
                                      if (mounted && name != null) {
                                        _attempt(
                                          () => _document.renameSheet(
                                            sheet.id,
                                            name,
                                          ),
                                        );
                                      }
                                    } else {
                                      _attempt(
                                        () => _document.setSheetHidden(
                                          sheet.id,
                                          !sheet.hidden,
                                        ),
                                      );
                                    }
                                    if (context.mounted) update(() {});
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名'),
                                    ),
                                    PopupMenuItem(
                                      value: 'hide',
                                      child: Text(sheet.hidden ? '取消隐藏' : '隐藏'),
                                    ),
                                  ],
                                ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (!widget.readOnly)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final name = await _nameDialog('');
                      if (!mounted || name == null) return;
                      final random = Random.secure();
                      final id =
                          'sheet_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
                      _attempt(
                        () => _document.addSheet(sheetId: id, name: name),
                      );
                      if (context.mounted) update(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('新建工作表'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _nameDialog(String name) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _SheetTextDialog(
        title: name.isEmpty ? '新建工作表' : '重命名工作表',
        label: '工作表名称',
        initial: name,
        action: '确定',
        maxLength: 31,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _visible.isEmpty
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('所有工作表均已隐藏，原始内容已保留'),
              TextButton(onPressed: _sheets, child: const Text('工作表管理')),
            ],
          ),
        )
      : Column(
          children: [
            if (!widget.readOnly)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '撤销',
                      onPressed: _undo.isEmpty ? null : () => _history(false),
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: '重做',
                      onPressed: _redo.isEmpty ? null : () => _history(true),
                      icon: const Icon(Icons.redo),
                    ),
                    TextButton.icon(
                      onPressed: _format,
                      icon: const Icon(Icons.tune),
                      label: const Text('格式'),
                    ),
                    if (_hasFormulas)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          '保留原公式 · 计算待接线',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    TextButton(onPressed: _locate, child: Text(_selected.a1)),
                    const Text(
                      'fx',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Color(0xff64748b),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('sheet-formula-input'),
                        controller: _formula,
                        focusNode: _formulaFocus,
                        readOnly: !_canInput,
                        onChanged: (_) => setState(() {
                          _inputDirty = true;
                          _error = null;
                        }),
                        onSubmitted: (_) => _commitInput(),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '输入单元格内容',
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_inputDirty) ...[
                      IconButton(
                        tooltip: '取消输入',
                        onPressed: () => setState(_syncInput),
                        icon: const Icon(Icons.close),
                      ),
                      IconButton(
                        tooltip: '应用输入',
                        onPressed: _commitInput,
                        icon: const Icon(
                          Icons.check,
                          color: SpreadsheetGrid.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Material(
                color: const Color(0xfffff4e5),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12)),
                ),
              ),
            Expanded(
              child: SpreadsheetGrid(
                verticalController: _vertical,
                horizontalController: _horizontal,
                document: _document,
                calculation: widget.calculation,
                sheetId: _sheetId,
                selected: _selected,
                onSelect: (a) => _select(a),
                onEdit: widget.readOnly ? null : (a) => _select(a, edit: true),
              ),
            ),
            SafeArea(
              top: false,
              child: ColoredBox(
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _visible
                              .map(
                                (sheet) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: TextButton(
                                    onPressed: () {
                                      if (!_leaveInput()) return;
                                      setState(() {
                                        _sheetId = sheet.id;
                                        _selected = const SheetAddress(0, 0);
                                        _syncInput();
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      backgroundColor: sheet.id == _sheetId
                                          ? const Color(0xffe8efff)
                                          : null,
                                    ),
                                    child: Text(sheet.name),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '工作表管理',
                      onPressed: _sheets,
                      icon: const Icon(Icons.view_list_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
}

class _FormatPanel extends StatefulWidget {
  const _FormatPanel({required this.address, required this.style});
  final String address;
  final Map<String, Object?> style;
  @override
  State<_FormatPanel> createState() => _FormatPanelState();
}

class _FormatPanelState extends State<_FormatPanel> {
  final _patch = <String, Object?>{};
  Object? _value(String key) =>
      _patch.containsKey(key) ? _patch[key] : widget.style[key];
  void _toggle(String key) =>
      setState(() => _patch[key] = _value(key) == 1 ? 0 : 1);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '单元格格式 · ${widget.address}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text(
                  'B',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                selected: _value('bl') == 1,
                onSelected: (_) => _toggle('bl'),
              ),
              FilterChip(
                label: const Text(
                  'I',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                selected: _value('it') == 1,
                onSelected: (_) => _toggle('it'),
              ),
              FilterChip(
                label: const Text(
                  'U',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
                selected:
                    _value('ul') is Map && (_value('ul') as Map)['s'] == 1,
                onSelected: (v) => setState(
                  () => _patch['ul'] = {
                    ...(_value('ul') is Map
                        ? Map<String, Object?>.from(_value('ul') as Map)
                        : <String, Object?>{}),
                    's': v ? 1 : 0,
                  },
                ),
              ),
              DropdownButton<num>(
                value: const [10, 12, 14, 16, 18, 24, 32].contains(_value('fs'))
                    ? _value('fs') as num
                    : null,
                hint: Text('${_value('fs') ?? 14}'),
                items: [10, 12, 14, 16, 18, 24, 32]
                    .map(
                      (n) => DropdownMenuItem<num>(value: n, child: Text('$n')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _patch['fs'] = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('对齐'),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 1; i <= 3; i++)
                ChoiceChip(
                  label: Icon(
                    [
                      Icons.format_align_left,
                      Icons.format_align_center,
                      Icons.format_align_right,
                    ][i - 1],
                  ),
                  selected: (_value('ht') ?? 1) == i,
                  onSelected: (_) => setState(() => _patch['ht'] = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('文字颜色'),
          _colors('cl'),
          const SizedBox(height: 16),
          const Text('填充颜色'),
          _colors('bg'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _patch),
                  child: const Text('应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _colors(String key) => Wrap(
    spacing: 8,
    children: [
      for (final hex in ['#1e293b', '#155af5', '#dc2626', '#e8efff', '#ffffff'])
        Semantics(
          label: '${key == 'cl' ? '文字' : '填充'} $hex',
          button: true,
          child: InkWell(
            onTap: () => setState(() => _patch[key] = {'rgb': hex}),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Color(
                  0xff000000 | int.parse(hex.substring(1), radix: 16),
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      _value(key) is Map && (_value(key) as Map)['rgb'] == hex
                      ? SpreadsheetGrid.blue
                      : const Color(0xffcbd5e1),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SheetTextDialog extends StatefulWidget {
  const _SheetTextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    this.maxLength,
  });
  final String title, label, initial, action;
  final int? maxLength;
  @override
  State<_SheetTextDialog> createState() => _SheetTextDialogState();
}

class _SheetTextDialogState extends State<_SheetTextDialog> {
  late final _input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _input,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text),
        child: Text(widget.action),
      ),
    ],
  );
}
