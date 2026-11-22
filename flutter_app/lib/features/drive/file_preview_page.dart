import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/attachments.dart';
import '../../core/drive_attachments.dart';
import '../../core/drive_download.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';
import '../../core/file_export.dart';
import '../../core/image_content.dart';
import '../../widgets/bookstark_markdown.dart';
import '../../widgets/native_image.dart';
import '../../widgets/native_pdf.dart';
import '../../widgets/native_media.dart';
import '../images/image_format.dart';

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.repository,
    required this.file,
    this.english = false,
    this.beforePlay,
    this.download,
    this.save,
    this.share,
  });
  final DriveRepository repository;
  final DriveNode file;
  final bool english;
  final Future<void> Function()? beforePlay;
  final Future<DriveDownloadedFile> Function(
    AttachmentCancellation cancellation,
    void Function(int, int) progress,
  )?
  download;
  final Future<FileExportOutcome> Function(DriveDownloadedFile)? save;
  final Future<void> Function(DriveDownloadedFile)? share;
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final _attachments = DriveAttachments(
    widget.repository,
    directory: driveParent(widget.file.path),
  );
  AttachmentCancellation? _cancellation;
  DriveDownloadedFile? _cache;
  Future<void>? _action;
  Future<Uint8List>? _imageBytes;
  String? _kind, _text, _error, _mime;
  bool _loading = true, _busy = false;
  int _received = 0, _generation = 0;
  DateTime? _lastProgress;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _cancellation?.cancel();
    _attachments.close();
    final cache = _cache;
    final action = _action;
    unawaited(() async {
      try {
        await action;
      } catch (_) {}
      try {
        await cache?.close();
      } catch (_) {}
    }());
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancel = AttachmentCancellation();
    _cancellation = cancel;
    final previous = _cache;
    _cache = null;
    _imageBytes = null;
    setState(() {
      _loading = true;
      _received = 0;
      _error = null;
      _kind = null;
      _text = null;
    });
    try {
      await previous?.close();
      void progress(int count, int total) {
        if (!mounted || generation != _generation) return;
        final now = DateTime.now();
        if (_lastProgress != null &&
            now.difference(_lastProgress!).inMilliseconds < 100 &&
            count < total) {
          return;
        }
        _lastProgress = now;
        setState(() => _received = count);
      }

      final cache =
          await (widget.download?.call(cancel, progress) ??
              downloadDriveFile(
                widget.repository,
                widget.file,
                cancellation: cancel,
                onReceived: progress,
              ));
      if (!mounted || generation != _generation) {
        await cache.close();
        return;
      }
      _cache = cache;
      final header = BytesBuilder(copy: false);
      await for (final chunk in cache.file.openRead(
        0,
        cache.size.clamp(0, 4096),
      )) {
        header.add(chunk);
        if (header.length > 4096) {
          throw const FormatException('Invalid preview header read');
        }
      }
      final bytes = header.takeBytes(),
          mime = cache.node.mime.split(';').first.toLowerCase();
      var kind = 'binary';
      String? text;
      if (imageContentMime(bytes) != null && cache.size <= 64 * 1024 * 1024) {
        kind = 'image';
        _imageBytes = cache.file.readAsBytes();
      } else if (bytes.length >= 5 &&
          ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-') {
        kind = 'pdf';
      } else if (mime.startsWith('audio/')) {
        kind = 'audio';
      } else if (mime.startsWith('video/')) {
        kind = 'video';
      } else if (cache.size <= maxDriveTextBytes) {
        try {
          final raw = await cache.file.readAsBytes();
          text = DriveText.decode(cache.node, raw).content;
          kind =
              cache.node.name.toLowerCase().endsWith('.md') ||
                  mime.contains('markdown')
              ? 'markdown'
              : 'text';
        } on FormatException {
          /* Binary data remains downloadable. */
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _kind = kind;
        _mime =
            imageContentMime(bytes) ??
            (kind == 'pdf' ? 'application/pdf' : cache.node.mime);
        _text = text;
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _run(Future<void> Function(DriveDownloadedFile) work) {
    final cache = _cache;
    if (_busy || cache == null) return Future.value();
    final action = () async {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await work(cache);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }();
    _action = action;
    return action;
  }

  Future<void> _save() => _run((file) async {
    final result =
        await (widget.save?.call(file) ??
            const SystemFileExporter().save(file));
    if (!mounted || result == FileExportOutcome.cancelled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == FileExportOutcome.saved
              ? t('已保存到所选位置', 'Saved to the selected location')
              : t(
                  '已交给浏览器下载，请查看浏览器完成情况。',
                  'Download handed to the browser; check browser completion.',
                ),
        ),
      ),
    );
  });
  Future<void> _share() => _run((file) async {
    if (widget.share != null) {
      await widget.share!(file);
      return;
    }
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await SharePlus.instance.share(
      ShareParams(
        files: [file.file],
        fileNameOverrides: [file.node.name],
        sharePositionOrigin: origin,
      ),
    );
  });
  Widget _preview() {
    final cache = _cache;
    if (cache == null) return const SizedBox();
    final height = (MediaQuery.sizeOf(context).height * .55).clamp(
      280.0,
      560.0,
    );
    switch (_kind) {
      case 'pdf':
        return SizedBox(
          height: height,
          child: NativePdf(
            bytes: cache.memory,
            filePath: cache.memory == null ? cache.file.path : null,
            sourceName: '${cache.node.id}:${cache.hash}',
            english: widget.english,
          ),
        );
      case 'image':
        return SizedBox(
          height: height.clamp(180, 360),
          child: FutureBuilder<Uint8List>(
            future: _imageBytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(t('图片读取失败，请重试。', 'Image failed to load; retry.')),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return LayoutBuilder(
                builder: (context, constraints) => InteractiveViewer(
                  minScale: .5,
                  maxScale: 8,
                  child: NativeImage(
                    bytes: snapshot.data!,
                    label: cache.node.name,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    maxDecodeSide: 4096,
                    english: widget.english,
                    onRetry: _load,
                  ),
                ),
              );
            },
          ),
        );
      case 'audio':
      case 'video':
        return NativeMedia(
          path: cache.file.path,
          audioOnly: _kind == 'audio',
          english: widget.english,
          beforePlay: widget.beforePlay,
        );
      case 'markdown':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: BookstarkMarkdown(
            data: _text ?? '',
            attachments: _attachments,
            english: widget.english,
          ),
        );
      case 'text':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _text ?? '',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                t(
                  '此文件暂不能在应用内预览，可保存或分享原文件。',
                  'This file cannot be previewed in the app. Save or share the original file.',
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = _cache, node = cache?.node ?? widget.file;
    return Scaffold(
      appBar: AppBar(
        title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: t('分享文件', 'Share file'),
            onPressed: _busy || cache == null ? null : _share,
            icon: const Icon(Icons.share),
          ),
          IconButton(
            tooltip: t('重新读取文件', 'Reload file'),
            onPressed: _busy || _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              node.path,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) ...[
              LinearProgressIndicator(
                value: node.size > 0
                    ? (_received / node.size).clamp(0, 1)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '正在读取 ${imageSizeLabel(_received)} / ${imageSizeLabel(node.size)}',
                  'Reading ${imageSizeLabel(_received)} / ${imageSizeLabel(node.size)}',
                ),
              ),
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: Text(t('停止读取', 'Stop reading')),
              ),
            ] else if (_kind != null)
              Card(clipBehavior: Clip.antiAlias, child: _preview()),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(t('重试读取', 'Retry loading')),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_mime ?? node.mime} · ${imageSizeLabel(node.size)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      node.isPublic
                          ? t('公开文件', 'Public file')
                          : t('私人文件', 'Private file'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        '修改时间：${node.modified.isEmpty ? '未知' : node.modified}',
                        'Modified: ${node.modified.isEmpty ? 'Unknown' : node.modified}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (cache != null) ...[
              const SizedBox(height: 12),
              Text(
                t(
                  '预览使用应用临时缓存，不修改原文件。',
                  'Preview uses the app temporary cache without modifying the original file.',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (widget.save != null ||
                      const SystemFileExporter().supported)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(t('保存到设备', 'Save to device')),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share),
                    label: Text(t('分享文件', 'Share file')),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
