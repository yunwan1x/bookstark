import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'admin_settings_l10n.dart';

/// Shared form chrome follows the saved admin prototypes.
AppBar adminSettingsAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  required bool dirty,
  required VoidCallback onReturn,
  String backLabel = '返回',
  String dirtyLabel = '未保存',
  List<Widget> actions = const [],
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final width = MediaQuery.sizeOf(context).width;
  final rightBadge = dirty && width >= 360 && scaler.scale(14) <= 19;
  final available = math.max(
    80.0,
    width - 88 - actions.length * 48 - (rightBadge ? 78 : 0),
  );
  const titleStyle = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: Color(0xff0e1b3d),
  );
  final painter = TextPainter(
    text: TextSpan(text: adminSettingsText(context, title), style: titleStyle),
    textDirection: Directionality.of(context),
    textScaler: scaler,
  )..layout(maxWidth: available);
  final titleLines = math.max(1, painter.computeLineMetrics().length);
  const subtitleStyle = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.normal,
    color: Color(0xff596780),
  );
  final subtitlePainter = subtitle == null
      ? null
      : (TextPainter(
          text: TextSpan(
            text: adminSettingsText(context, subtitle),
            style: subtitleStyle,
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: available));
  final subtitleLines = subtitlePainter == null
      ? 1
      : math.max(1, subtitlePainter.computeLineMetrics().length);
  final subtitleHeight = subtitlePainter == null
      ? 0.0
      : subtitlePainter.height + 4;
  final below = dirty && !rightBadge;
  final height = math.max(
    72.0,
    painter.height + subtitleHeight + 24 + (below ? scaler.scale(14) + 18 : 0),
  );
  painter.dispose();
  subtitlePainter?.dispose();
  Widget badge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xff1555ef)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      dirtyLabel,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0xff1555ef),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  return AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: height,
    titleSpacing: 16,
    leadingWidth: 56,
    leading: IconButton(
      tooltip: adminSettingsText(context, backLabel),
      onPressed: onReturn,
      icon: const Icon(Icons.arrow_back),
    ),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle,
          softWrap: true,
          maxLines: titleLines,
          overflow: TextOverflow.visible,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: subtitleStyle,
            softWrap: true,
            maxLines: subtitleLines,
            overflow: TextOverflow.visible,
          ),
        ],
        if (below) ...[const SizedBox(height: 6), badge()],
      ],
    ),
    actions: [
      if (rightBadge)
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(child: badge()),
        ),
      ...actions,
    ],
  );
}

class AdminSettingsField extends StatelessWidget {
  const AdminSettingsField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.helper,
    this.style,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.minLines = 1,
    this.maxLines = 1,
  });
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool enabled, obscureText;
  final ValueChanged<String> onChanged;
  final String? helper;
  final TextStyle? style;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final int minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xff0e1b3d),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: adminSettingsText(context, label),
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            obscureText: obscureText,
            style: style,
            minLines: minLines,
            maxLines: maxLines,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            onChanged: onChanged,
            decoration: InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.never,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xff94a3b8)),
              ),
              helperText: helper == null
                  ? null
                  : adminSettingsText(context, helper!),
              helperMaxLines: 4,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminSettingsLink extends StatelessWidget {
  const AdminSettingsLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffd6dfed)),
      ),
      child: ListTile(
        minTileHeight: 72,
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xffedf4ff),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xff1555ef)),
        ),
        title: Text(
          adminSettingsText(context, title),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}

class AdminSettingsChoice extends StatelessWidget {
  const AdminSettingsChoice({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    required this.revision,
    this.hintLabel = '请选择',
    this.unknownLabel = '保留当前值；只有明确选择后才更改。',
  });
  final Key fieldKey;
  final String label;
  final String? value;
  final Map<String, String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final int revision;
  final String hintLabel, unknownLabel;
  @override
  Widget build(BuildContext context) {
    final choices = Map<String, String>.of(options);
    final current = value;
    final unknown =
        current != null && current.isNotEmpty && !choices.containsKey(current);
    if (unknown) choices[current] = current;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xff0e1b3d),
            ),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: ValueKey(revision),
            child: DropdownButtonFormField<String>(
              key: fieldKey,
              initialValue: current != null && choices.containsKey(current)
                  ? current
                  : null,
              isExpanded: true,
              isDense: false,
              itemHeight: null,
              hint: Text(adminSettingsText(context, hintLabel)),
              items: [
                for (final entry in choices.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) onChanged(value);
                    }
                  : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xff94a3b8)),
                ),
                helperText: unknown
                    ? adminSettingsText(context, unknownLabel)
                    : null,
                helperMaxLines: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
