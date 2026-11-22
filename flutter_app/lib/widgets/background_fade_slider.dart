import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _FadeIntent extends Intent {
  const _FadeIntent(this.amount, {this.absolute = false});
  final int amount;
  final bool absolute;
}

/// A bounded native slider with explicit keyboard and accessibility focus.
/// It owns no overlay, so its semantic hit region stays inside the control.
class BackgroundFadeSlider extends StatefulWidget {
  const BackgroundFadeSlider({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  @override
  State<BackgroundFadeSlider> createState() => _BackgroundFadeSliderState();
}

class _BackgroundFadeSliderState extends State<BackgroundFadeSlider> {
  final _focus = FocusNode(debugLabel: 'Background fade');
  bool _highlight = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focused);
  }

  void _focused() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focused);
    _focus.dispose();
    super.dispose();
  }

  void _change(int amount, {bool absolute = false}) => widget.onChanged?.call(
    (absolute ? amount.toDouble() : widget.value + amount).clamp(0.0, 100.0),
  );
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return FocusableActionDetector(
      focusNode: _focus,
      enabled: enabled,
      includeFocusSemantics: false,
      onShowFocusHighlight: (highlight) =>
          setState(() => _highlight = highlight),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _FadeIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown): _FadeIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _FadeIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _FadeIntent(1),
        SingleActivator(LogicalKeyboardKey.pageDown): _FadeIntent(-10),
        SingleActivator(LogicalKeyboardKey.pageUp): _FadeIntent(10),
        SingleActivator(LogicalKeyboardKey.home): _FadeIntent(
          0,
          absolute: true,
        ),
        SingleActivator(LogicalKeyboardKey.end): _FadeIntent(
          100,
          absolute: true,
        ),
      },
      actions: {
        _FadeIntent: CallbackAction<_FadeIntent>(
          onInvoke: (intent) {
            if (enabled) {
              _change(intent.amount, absolute: intent.absolute);
            }
            return null;
          },
        ),
      },
      child: Semantics(
        label: widget.label,
        slider: true,
        enabled: enabled,
        focusable: enabled,
        focused: _focus.hasFocus,
        value: '${widget.value.round()}%',
        increasedValue: '${(widget.value + 1).clamp(0, 100).round()}%',
        decreasedValue: '${(widget.value - 1).clamp(0, 100).round()}%',
        onIncrease: enabled ? () => _change(1) : null,
        onDecrease: enabled ? () => _change(-1) : null,
        onDidGainAccessibilityFocus: enabled ? _focus.requestFocus : null,
        onFocus: enabled ? _focus.requestFocus : null,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: enabled ? (_) => _focus.requestFocus() : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _highlight
                    ? const Color(0xff2563eb)
                    : Colors.transparent,
              ),
            ),
            child: SizedBox(
              height: 56,
              child: CupertinoSlider(
                value: widget.value,
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: const Color(0xff2563eb),
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
