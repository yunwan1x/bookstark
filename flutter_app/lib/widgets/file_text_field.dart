import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Native editable text with logical line numbers aligned to wrapped lines.
class FileTextField extends StatefulWidget {
  const FileTextField({
    super.key,
    required this.controller,
    required this.undoController,
    this.enabled = true,
    this.english = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final UndoHistoryController undoController;
  final bool enabled, english;
  final ValueChanged<String>? onChanged;
  @override
  State<FileTextField> createState() => _FileTextFieldState();
}

class _FileTextFieldState extends State<FileTextField> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final style = Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0,
        );
        const strut = StrutStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
          forceStrutHeight: true,
        );
        final scaler = MediaQuery.textScalerOf(context),
            direction = Directionality.of(context);
        final lines = '\n'.allMatches(value.text).length + 1;
        final gutter = math.max(
          40.0,
          scaler.scale(14) * .65 * lines.toString().length + 16,
        );
        final width = math.max(1.0, constraints.maxWidth - gutter - 24);
        final layout = TextPainter(
          text: TextSpan(
            text: value.text.isEmpty ? ' ' : value.text,
            style: style,
          ),
          textDirection: direction,
          textScaler: scaler,
          strutStyle: strut,
        )..layout(maxWidth: width);
        final metrics = layout.computeLineMetrics();
        final height = math.max(constraints.maxHeight, layout.height + 24);
        layout.dispose();
        return Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.enabled ? () => _focus.requestFocus() : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: gutter,
                      height: height,
                      child: CustomPaint(
                        painter: _LineGutter(
                          metrics,
                          style.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          scaler,
                          direction,
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('file-content-input'),
                        controller: widget.controller,
                        onChanged: widget.onChanged,
                        undoController: widget.undoController,
                        focusNode: _focus,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: style,
                        strutStyle: strut,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(12),
                          hintText: widget.english ? 'File contents' : '文件内容',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _LineGutter extends CustomPainter {
  const _LineGutter(
    this.metrics,
    this.style,
    this.scaler,
    this.direction,
    this.background,
  );
  final List<ui.LineMetrics> metrics;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final Color background;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final clip = canvas.getLocalClipBounds();
    var number = 1, newLogical = true;
    for (final line in metrics) {
      final top = line.baseline - line.ascent + 12,
          bottom = line.baseline + line.descent + 12;
      if (newLogical && bottom >= clip.top && top <= clip.bottom) {
        final text = TextPainter(
          text: TextSpan(text: '$number', style: style),
          textScaler: scaler,
          textDirection: direction,
        )..layout();
        text.paint(
          canvas,
          Offset(
            size.width - text.width - 8,
            line.baseline +
                12 -
                text.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
        );
        text.dispose();
      }
      if (line.hardBreak) {
        number++;
        newLogical = true;
      } else {
        newLogical = false;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineGutter oldDelegate) =>
      metrics != oldDelegate.metrics ||
      style != oldDelegate.style ||
      scaler != oldDelegate.scaler ||
      direction != oldDelegate.direction ||
      background != oldDelegate.background;
}
