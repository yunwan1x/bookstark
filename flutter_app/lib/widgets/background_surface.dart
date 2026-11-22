import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/background_repository.dart';
import 'dart:ui' as ui;
import '../core/image_dimensions.dart';

class BackgroundSurface extends StatefulWidget {
  const BackgroundSurface({
    super.key,
    required this.preference,
    required this.child,
    this.image,
  });
  final BackgroundPreference preference;
  final Uint8List? image;
  final Widget child;
  @override
  State<BackgroundSurface> createState() => _BackgroundSurfaceState();
}

class _BackgroundSurfaceState extends State<BackgroundSurface>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  void _sync() {
    final moving =
        widget.preference.mode == 'dynamic' &&
        widget.preference.animated &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (moving && !_animation.isAnimating) {
      _animation.repeat(reverse: true);
    } else if (!moving) {
      _animation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BackgroundSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) => Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Color.lerp(
                    const Color(0xffe9f3ff),
                    Colors.white,
                    widget.preference.fade / 100,
                  )!,
                ),
                if (widget.preference.mode == 'dynamic')
                  CustomPaint(
                    painter: _BackgroundGradientPainter(
                      _animation.value,
                      widget.preference.fade,
                    ),
                  ),
                if (widget.preference.mode == 'image' &&
                    widget.image != null) ...[
                  _PrivateBackgroundRaster(bytes: widget.image!),
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.white.withValues(
                        alpha: widget.preference.fade / 100,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        child!,
      ],
    ),
    child: widget.child,
  );
}

class AccountBackgroundScope extends InheritedWidget {
  const AccountBackgroundScope({super.key, required super.child});
  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountBackgroundScope>() !=
      null;
  @override
  bool updateShouldNotify(AccountBackgroundScope oldWidget) => false;
}

// Account-private rasters own their decoded image. No shared ImageCache,
// network provider or disk cache retains the background after disposal.
class _PrivateBackgroundRaster extends StatefulWidget {
  const _PrivateBackgroundRaster({required this.bytes});
  final Uint8List bytes;
  @override
  State<_PrivateBackgroundRaster> createState() =>
      _PrivateBackgroundRasterState();
}

class _PrivateBackgroundRasterState extends State<_PrivateBackgroundRaster> {
  ui.Image? _image;
  int _generation = 0;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _PrivateBackgroundRaster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decode();
    }
  }

  Future<void> _decode() async {
    final generation = ++_generation;
    _image?.dispose();
    _image = null;
    _failed = false;
    try {
      final (width, height) = encodedImageDimensions(widget.bytes);
      if (width * height > 20000000) {
        throw const FormatException('Image exceeds pixel budget');
      }
      final scale = math.min(1.0, 2048 / math.max(width, height));
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
        allowUpscaling: false,
      );
      late ui.Image image;
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image != null
      ? RawImage(image: _image, fit: BoxFit.cover)
      : Center(
          child: Icon(
            _failed ? Icons.broken_image_outlined : Icons.image_outlined,
          ),
        );
}

// Bounded flat color bands avoid depending on a device gradient shader. The
// gradient moves only when motion is enabled; no raster texture is cached.
class _BackgroundGradientPainter extends CustomPainter {
  const _BackgroundGradientPainter(this.progress, this.fade);
  final double progress;
  final int fade;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint();
    const first = Color(0xffc5e4fc),
        middle = Color(0xffe2dcff),
        last = Color(0xffd4eff0);
    const bands = 128;
    for (var index = 0; index < bands; index++) {
      final position = ((index + .5) / bands * .85 + progress * .15).clamp(
        0.0,
        1.0,
      );
      final color = position < .5
          ? Color.lerp(first, middle, position * 2)!
          : Color.lerp(middle, last, (position - .5) * 2)!;
      paint.color = Color.lerp(color, Colors.white, fade / 100)!;
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          size.height * index / bands,
          size.width,
          size.height * (index + 1) / bands + .5,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundGradientPainter oldDelegate) =>
      progress != oldDelegate.progress || fade != oldDelegate.fade;
}
