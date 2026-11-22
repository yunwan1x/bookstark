import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import '../../core/spreadsheet_document.dart';
import '../../core/spreadsheet_calculation.dart';

/// A native, virtualized view of the original sparse workbook. Every covered
/// vicinity returns identical merge metadata, including an offscreen anchor.
class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({
    super.key,
    required this.document,
    required this.sheetId,
    required this.selected,
    required this.onSelect,
    this.onEdit,
    this.calculation,
    this.verticalController,
    this.horizontalController,
  });
  final SpreadsheetDocument document;
  final SpreadsheetCalculationResult? calculation;
  final String sheetId;
  final SheetAddress selected;
  final ValueChanged<SheetAddress> onSelect;
  final ValueChanged<SheetAddress>? onEdit;
  final ScrollController? verticalController, horizontalController;
  static const blue = Color(0xff155af5), line = Color(0xffdfe5ee);

  static double axisExtent(SpreadsheetSheet sheet, int index, bool row) {
    if (index == 0) return row ? 36 : 46;
    final data = sheet.raw[row ? 'rowData' : 'columnData'];
    final entry = data is Map ? data['${index - 1}'] : null;
    if (entry is Map && (entry['hd'] == 1 || entry['hd'] == true)) return 0;
    final value = entry is Map ? entry[row ? 'h' : 'w'] : null;
    final fallback = sheet.raw[row ? 'defaultRowHeight' : 'defaultColumnWidth'];
    final extent = value is num && value.isFinite && value > 0
        ? value.toDouble()
        : fallback is num && fallback.isFinite && fallback > 0
        ? fallback.toDouble()
        : row
        ? 32.0
        : 100.0;
    // Preserve the saved dimension; constrain only pathological rendering sizes.
    return extent.clamp(1.0, 10000.0);
  }

  /// Calculate a distant cell offset from sparse dimension overrides, without
  /// enumerating a million rows or instantiating their cells.
  static double axisOffset(SpreadsheetSheet sheet, int index, bool row) {
    if (index <= 0) return 0;
    final data = sheet.raw[row ? 'rowData' : 'columnData'];
    final empty = row ? 'defaultRowHeight' : 'defaultColumnWidth';
    final fallback = sheet.raw[empty];
    final base =
        (fallback is num && fallback.isFinite && fallback > 0
                ? fallback.toDouble()
                : row
                ? 32.0
                : 100.0)
            .clamp(1.0, 10000.0);
    var result = base * index;
    if (data is Map) {
      for (final key in data.keys) {
        final dimension = int.tryParse(key.toString());
        if (dimension != null && dimension >= 0 && dimension < index) {
          result += axisExtent(sheet, dimension + 1, row) - base;
        }
      }
    }
    return result;
  }

  static int _fittingFreeze(
    SpreadsheetSheet sheet,
    int requested,
    bool row,
    double available,
  ) {
    var used = axisExtent(sheet, 0, row);
    for (var i = 0; i < requested; i++) {
      used += axisExtent(sheet, i + 1, row);
      if (used > available - 64 || i >= 255) return 0;
    }
    return requested;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = document.sheet(sheetId);
    // A merged cell cannot straddle a pinned boundary in TableView. Fall back
    // to pinning only headers for that axis rather than splitting the cell.
    final rowFreeze =
        sheet.merges.any(
          (m) => m.startRow < sheet.frozenRows && m.endRow >= sheet.frozenRows,
        )
        ? 0
        : sheet.frozenRows;
    final colFreeze =
        sheet.merges.any(
          (m) =>
              m.startColumn < sheet.frozenColumns &&
              m.endColumn >= sheet.frozenColumns,
        )
        ? 0
        : sheet.frozenColumns;
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) => TableView.builder(
          key: ValueKey(sheetId),
          diagonalDragBehavior: DiagonalDragBehavior.free,
          verticalDetails: ScrollableDetails.vertical(
            controller: verticalController,
          ),
          horizontalDetails: ScrollableDetails.horizontal(
            controller: horizontalController,
          ),
          pinnedRowCount:
              _fittingFreeze(sheet, rowFreeze, true, constraints.maxHeight) + 1,
          pinnedColumnCount:
              _fittingFreeze(sheet, colFreeze, false, constraints.maxWidth) + 1,
          rowCount: sheet.rowCount + 1,
          columnCount: sheet.columnCount + 1,
          rowBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(axisExtent(sheet, index, true)),
          ),
          columnBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(axisExtent(sheet, index, false)),
          ),
          cellBuilder: (context, vicinity) {
            if (vicinity.row == 0 || vicinity.column == 0) {
              final label = vicinity.row == 0 && vicinity.column == 0
                  ? ''
                  : vicinity.row == 0
                  ? SheetAddress.columnName(vicinity.column - 1)
                  : '${vicinity.row}';
              final active = vicinity.row == 0
                  ? vicinity.column == selected.column + 1
                  : vicinity.row == selected.row + 1;
              return TableViewCell(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xffe8efff)
                        : const Color(0xfff7f9fc),
                    border: const Border(
                      right: BorderSide(color: line),
                      bottom: BorderSide(color: line),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: active ? blue : const Color(0xff64748b),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            final address = SheetAddress(vicinity.row - 1, vicinity.column - 1);
            final merge = sheet.mergeAt(address);
            final anchor = merge?.anchor ?? address;
            final cell = sheet.cell(anchor),
                style = document.cellStyle(sheetId, anchor);
            final isSelected =
                selected == anchor || (merge?.contains(selected) ?? false);
            final alignment = switch (style['ht']) {
              2 => Alignment.center,
              3 => Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
            final fontSize = style['fs'];
            final computed = identical(calculation?.document, document)
                ? calculation?.at(sheetId, anchor)
                : null;
            final computedValue = computed?.value;
            final label = computed == null
                ? cell.text
                : computedValue == null
                ? ''
                : computedValue is bool
                ? (computedValue ? 'TRUE' : 'FALSE')
                : computedValue is num &&
                      computedValue.abs() < 1e15 &&
                      computedValue == computedValue.roundToDouble()
                ? computedValue.toInt().toString()
                : computedValue.toString();
            return TableViewCell(
              rowMergeStart: merge == null ? null : merge.startRow + 1,
              rowMergeSpan: merge == null
                  ? null
                  : merge.endRow - merge.startRow + 1,
              columnMergeStart: merge == null ? null : merge.startColumn + 1,
              columnMergeSpan: merge == null
                  ? null
                  : merge.endColumn - merge.startColumn + 1,
              child: Semantics(
                label: '${anchor.a1}${label.isEmpty ? '' : ', $label'}',
                selected: isSelected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(anchor),
                  onDoubleTap: onEdit == null ? null : () => onEdit!(anchor),
                  child: Container(
                    alignment: alignment,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _color(style['bg']) ?? Colors.white,
                      border: isSelected
                          ? Border.all(color: blue, width: 2)
                          : const Border(
                              right: BorderSide(color: line),
                              bottom: BorderSide(color: line),
                            ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: _color(style['cl']) ?? const Color(0xff1e293b),
                        fontSize: fontSize is num && fontSize.isFinite
                            ? fontSize.toDouble().clamp(6, 96)
                            : 14,
                        fontWeight: style['bl'] == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontStyle: style['it'] == 1
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration:
                            style['ul'] is Map && (style['ul'] as Map)['s'] == 1
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static Color? _color(Object? value) {
    final rgb = value is Map ? value['rgb'] : value;
    if (rgb is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(rgb)) {
      return null;
    }
    return Color(0xff000000 | int.parse(rgb.substring(1), radix: 16));
  }
}
