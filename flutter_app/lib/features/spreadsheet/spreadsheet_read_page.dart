import 'package:flutter/material.dart';
import '../../core/local_store.dart';
import '../../core/spreadsheet_document.dart';
import '../../core/spreadsheet_calculation.dart';
import '../../core/spreadsheet_calculator.dart';
import 'spreadsheet_editor.dart';

/// First typed read path. Writes are deliberately unavailable until the typed
/// persistence/recovery controller is connected; Markdown APIs are never used.
class LocalSpreadsheetReadPage extends StatefulWidget {
  const LocalSpreadsheetReadPage({
    super.key,
    required this.store,
    required this.id,
    required this.collection,
    this.english = false,
    this.calculator = calculateSpreadsheet,
  });
  final LocalStore store;
  final Future<SpreadsheetCalculationResult> Function(SpreadsheetDocument)
  calculator;
  final int id;
  final String collection;
  final bool english;
  @override
  State<LocalSpreadsheetReadPage> createState() =>
      _LocalSpreadsheetReadPageState();
}

class _LocalSpreadsheetReadPageState extends State<LocalSpreadsheetReadPage> {
  SpreadsheetDocument? _document;
  SpreadsheetCalculationResult? _result;
  String? _title, _error, _calculationError;
  bool _calculating = false, _loading = true;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _document = null;
      _result = null;
      _error = null;
      _title = null;
      _calculationError = null;
      _calculating = false;
    });
    try {
      final row = await widget.store.readNote(
        widget.id,
        collection: widget.collection,
      );
      if (!mounted || generation != _generation) return;
      if (row['id'] != widget.id ||
          row['collection'] != widget.collection ||
          row['editor_type'] != 'spreadsheet' ||
          row['title'] is! String ||
          row['content'] is! String) {
        throw const FormatException('Spreadsheet identity or type changed');
      }
      final document = SpreadsheetDocument.parse(row['content'] as String);
      setState(() {
        _loading = false;
        _document = document;
        _title = row['title'] as String;
        _calculating = true;
      });
      try {
        final result = await widget.calculator(document);
        if (!mounted || generation != _generation) return;
        setState(() {
          _result = result;
          _calculating = false;
          if (result.hasUnsupportedFormula) {
            _calculationError = t(
              '部分公式暂不支持，保留原始工作簿',
              'Some formulas are unsupported; original workbook preserved',
            );
          }
        });
      } catch (_) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _calculating = false;
          _calculationError = t(
            '暂时无法重算，显示已保存的计算缓存',
            'Recalculation unavailable; showing saved calculation caches',
          );
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = t(
          '表格无法读取或已更改，原始内容未修改',
          'Spreadsheet unavailable or changed; original content preserved',
        );
        _document = null;
        _title = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff1f5ff),
    appBar: AppBar(
      title: Text(t('表格', 'Spreadsheet')),
      actions: [
        IconButton(
          tooltip: t('刷新', 'Refresh'),
          onPressed: _loading || _calculating ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: Text(t('重试', 'Retry'))),
                ],
              ),
            ),
          )
        : _document == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  _title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text(t('本地空间', 'Local space'))),
                    Chip(label: Text(t('只读', 'Read only'))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _calculating
                      ? t(
                          '正在重算 · 网格暂为已保存缓存',
                          'Recalculating · grid shows saved caches',
                        )
                      : _calculationError ??
                            t(
                              '原生计算已更新 · 原始文件未修改',
                              'Native values updated · original file unchanged',
                            ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: SpreadsheetEditor(
                  document: _document!,
                  calculation: _result,
                  readOnly: true,
                  onChanged: (_) => throw StateError(
                    'Read-only spreadsheet attempted a write',
                  ),
                ),
              ),
            ],
          ),
  );
}
