import 'package:flutter/widgets.dart';

/// Shared selection-preserving Markdown insertion for native editors.
void wrapMarkdown(
  TextEditingController controller,
  String before,
  String after,
) {
  final selection = controller.selection;
  final valid = selection.isValid && selection.end <= controller.text.length;
  final start = valid ? selection.start : controller.text.length;
  final end = valid ? selection.end : start;
  final selected = controller.text.substring(start, end);
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(start, end, '$before$selected$after'),
    selection: TextSelection(
      baseOffset: start + before.length,
      extentOffset: start + before.length + selected.length,
    ),
  );
}
