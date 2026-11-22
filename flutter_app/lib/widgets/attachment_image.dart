import 'native_image.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/attachments.dart';

class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.repository,
    required this.uri,
    required this.label,
    this.english = false,
    this.onShare,
  });
  final AttachmentRepository repository;
  final Uri uri;
  final String label;
  final bool english;
  final Future<void> Function(Uint8List bytes)? onShare;
  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _image = widget.repository.read(widget.uri, maxBytes: 16 * 1024 * 1024);
  }

  @override
  void didUpdateWidget(covariant AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uri != oldWidget.uri ||
        widget.repository != oldWidget.repository) {
      _load();
    }
  }

  Future<void> _open(Uint8List bytes) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            tooltip: widget.english ? 'Close' : '关闭',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (widget.onShare != null)
              IconButton(
                tooltip: widget.english ? 'Share image' : '分享图片',
                onPressed: () => widget.onShare!(bytes),
                icon: const Icon(Icons.share),
              ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 8,
                child: NativeImage(
                  bytes: bytes,
                  label: widget.label,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  maxDecodeSide: 4096,
                  english: widget.english,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label),
            Text(widget.english ? 'Image failed to load' : '图片加载失败'),
            TextButton(
              onPressed: () => setState(_load),
              child: Text(widget.english ? 'Retry' : '重试'),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final bytes = snapshot.data!;
      return Semantics(
        label: widget.label,
        button: true,
        child: InkWell(
          onTap: () => _open(bytes),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: NativeImage(
              bytes: bytes,
              label: widget.label,
              maxDecodeSide: 1024,
              english: widget.english,
              onRetry: () => setState(_load),
            ),
          ),
        ),
      );
    },
  );
}
