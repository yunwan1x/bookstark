import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/image_dimensions.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/image_content.dart';

Future<(int, int)> nativeImageDimensions(Uint8List bytes) async {
  if (kIsWeb) return encodedImageDimensions(bytes);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w < 1 || h < 1) {
      throw const FormatException('图片尺寸无效 / Invalid image dimensions');
    }
    return (w, h);
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

class _PreparedImage {
  const _PreparedImage({this.svg, this.width = 0, this.height = 0});
  final NativeSvgData? svg;
  final int width, height;
}

/// Bounded native rendering shared by Markdown attachments and the image library.
/// No network loader is handed to the SVG renderer.
class NativeImage extends StatefulWidget {
  const NativeImage({
    super.key,
    required this.bytes,
    required this.label,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.maxDecodeSide = 2048,
    this.compact = false,
    this.english = false,
    this.onRetry,
  });
  final Uint8List bytes;
  final String label;
  final BoxFit fit;
  final double? width, height;
  final int maxDecodeSide;
  final bool compact, english;
  final VoidCallback? onRetry;
  @override
  State<NativeImage> createState() => _NativeImageState();
}

class _NativeImageState extends State<NativeImage> {
  late Future<_PreparedImage> _prepared;
  @override
  void initState() {
    super.initState();
    _prepared = _prepare();
  }

  @override
  void didUpdateWidget(covariant NativeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _prepared = _prepare();
  }

  Future<(int, int)> _dimensions(Uint8List bytes) async {
    final dimensions = await nativeImageDimensions(bytes);
    if (dimensions.$1 * dimensions.$2 > 64 * 1024 * 1024) {
      throw const FormatException(
        '图片解码尺寸超过64百万像素上限 / Image exceeds the 64 megapixel decode bound',
      );
    }
    return dimensions;
  }

  Future<_PreparedImage> _prepare() async {
    final bytes = widget.bytes;
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('图片超过读取上限 / Image exceeds read bound');
    }
    if (imageContentMime(bytes) == 'image/svg+xml') {
      final svg = prepareNativeSvg(bytes);
      var pixels = 0;
      for (final image in svg.embeddedImages) {
        final (width, height) = await _dimensions(image);
        pixels += width * height;
        if (pixels > 64 * 1024 * 1024) {
          throw const FormatException(
            'SVG内嵌图片总尺寸超过上限 / Embedded SVG raster images exceed the decode bound',
          );
        }
      }
      return _PreparedImage(svg: svg);
    }
    final (width, height) = await _dimensions(bytes);
    return _PreparedImage(width: width, height: height);
  }

  Widget _error(Object error) {
    final message =
        '${widget.label}: ${widget.english ? 'Image preview failed' : '图片预览失败'}\n$error';
    if (widget.compact) {
      return Tooltip(
        message: message,
        child: Semantics(
          label: message,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Color(0xff64748b)),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined),
        Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
        if (widget.onRetry != null)
          TextButton(
            onPressed: widget.onRetry,
            child: Text(widget.english ? 'Retry' : '重试'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PreparedImage>(
    future: _prepared,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error(snapshot.error!);
      if (!snapshot.hasData) {
        return SizedBox(
          width: widget.width,
          height: widget.height ?? 80,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      final prepared = snapshot.data!;
      if (prepared.svg != null) {
        return SvgPicture.memory(
          prepared.svg!.bytes,
          width: widget.width,
          height: widget.height ?? 200,
          fit: BoxFit.contain,
          semanticsLabel: widget.label,
          errorBuilder: (context, error, stack) => _error(error),
        );
      }
      final side = widget.maxDecodeSide.clamp(1, 4096);
      final scale = math.min(
        1.0,
        side / math.max(prepared.width, prepared.height),
      );
      return Image.memory(
        widget.bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: math.max(1, (prepared.width * scale).round()),
        cacheHeight: math.max(1, (prepared.height * scale).round()),
        semanticLabel: widget.label,
        errorBuilder: (context, error, stack) => _error(error),
      );
    },
  );
}
