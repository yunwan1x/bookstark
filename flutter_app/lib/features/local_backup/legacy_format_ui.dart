import 'package:flutter/material.dart';
import '../../core/local_legacy_format_selection.dart';
import 'local_backup_scaffold.dart';

const legacyBlue = Color(0xff0050f5);
const legacyInk = Color(0xff0c192e);

ThemeData legacyFormatTheme(ThemeData base) => base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    primary: legacyBlue,
    onPrimary: Colors.white,
    surface: Colors.white,
  ),
  textTheme: base.textTheme
      .apply(bodyColor: legacyInk, displayColor: legacyInk)
      .copyWith(
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 16,
          color: legacyInk,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          color: legacyInk,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 14,
          color: legacyInk,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
  appBarTheme: base.appBarTheme.copyWith(
    titleTextStyle: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: legacyInk,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      side: const BorderSide(color: legacyBlue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

String legacyFormatName(LegacyContentFormat value, bool english) =>
    switch (value) {
      LegacyContentFormat.markdown => 'Markdown',
      LegacyContentFormat.html => english ? 'HTML page' : 'HTML 网页',
      LegacyContentFormat.spreadsheet => english ? 'Spreadsheet' : '表格',
      LegacyContentFormat.drawing => english ? 'Drawing' : '画板',
      LegacyContentFormat.mindmap => english ? 'Mind map' : '思维导图',
      LegacyContentFormat.richdoc => english ? 'Rich document' : '富文档',
      LegacyContentFormat.presentation => english ? 'Presentation' : '演示文稿',
    };

class LegacyFormatFrame extends StatelessWidget {
  const LegacyFormatFrame({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.onBack,
    this.scrollIdentity,
  });
  final String title;
  final List<Widget> content, actions;
  final VoidCallback? onBack;
  final Object? scrollIdentity;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: legacyFormatTheme(base),
      child: LocalBackupScaffold(
        title: title,
        content: content,
        actions: actions,
        onBack: onBack,
        scrollIdentity: scrollIdentity,
        wrapTitle: true,
      ),
    );
  }
}

class LegacyFormatInfo extends StatelessWidget {
  const LegacyFormatInfo(this.text, {super.key, this.checked = false});
  final String text;
  final bool checked;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xffe5efff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          checked ? Icons.check_circle : Icons.info_outline,
          color: legacyBlue,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class LegacyFormatDropdown extends StatelessWidget {
  const LegacyFormatDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.english,
  });
  final LegacyContentFormat? value;
  final ValueChanged<LegacyContentFormat?> onChanged;
  final bool english;
  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<LegacyContentFormat>(
        initialValue: value,
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(
          labelText: english ? 'Content format' : '内容格式',
          border: const OutlineInputBorder(),
        ),
        hint: Text(english ? 'Choose a format' : '请选择格式'),
        items: [
          for (final format in LegacyContentFormat.values)
            DropdownMenuItem(
              value: format,
              child: Text(legacyFormatName(format, english)),
            ),
        ],
        onChanged: onChanged,
      );
}
