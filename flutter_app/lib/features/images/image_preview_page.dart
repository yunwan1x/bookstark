import 'dart:async';
import 'image_library_owner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api_client.dart';
import '../../core/attachments.dart';
import '../../core/image_content.dart';
import '../../core/images_repository.dart';
import '../../core/local_images_repository.dart';
import '../../widgets/native_image.dart';
import 'image_format.dart';

class ImagePreviewOutcome {
  const ImagePreviewOutcome({this.removal, this.needsVerification = false});
  final ImageRemovalResult? removal;
  final bool needsVerification;
}

String imageShareName(String name, String mime) {
  final extension = switch (mime) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/svg+xml' => 'svg',
    _ => null,
  };
  final safe = attachmentName(name.isEmpty ? 'image' : name);
  if (extension == null) return safe;
  final current = RegExp(
    r'\.([^.]+)$',
  ).firstMatch(safe)?.group(1)?.toLowerCase();
  if (current == extension || (extension == 'jpg' && current == 'jpeg')) {
    return safe;
  }
  return '${safe.replaceFirst(RegExp(r'\.[^.]+$'), '')}.$extension';
}

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({
    super.key,
    required this.repository,
    required this.image,
    this.english = false,
    this.share,
    this.owner,
  });
  final ImagesRepository repository;
  final ImageLibraryOwner? owner;
  final ManagedImage image;
  final bool english;
  final Future<void> Function(Uint8List bytes, String fileName)? share;
  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late Future<Uint8List> _bytes;
  int _epoch = 0;
  bool get _current => mounted && (widget.owner?.isCurrent ?? true);
  bool _busy = false,
      _deleting = false,
      _needsVerification = false,
      _leaveAllowed = false,
      _askingLeave = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    widget.owner?.addListener(_ownerChanged);
    _reload();
  }

  void _ownerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ImagePreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.owner, widget.owner) ||
        oldWidget.image.id != widget.image.id ||
        oldWidget.image.uri != widget.image.uri) {
      oldWidget.owner?.removeListener(_ownerChanged);
      widget.owner?.addListener(_ownerChanged);
      _epoch++;
      _busy = _deleting = _needsVerification = false;
      _error = null;
      if (_current) _reload();
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.owner?.removeListener(_ownerChanged);
    super.dispose();
  }

  Future<T> _work<T>(Future<T> Function() work) =>
      widget.owner?.run(work) ?? Future<T>.sync(work);

  void _reload({bool force = false}) {
    if (!_current) return;
    final repository = widget.repository, image = widget.image;
    _bytes = _work(() => repository.bytes(image.uri, reload: force));
  }

  Future<void> _copy(bool markdown) async {
    final epoch = _epoch;
    final repository = widget.repository;
    final image = widget.image;
    bool current() =>
        _current && epoch == _epoch && identical(repository, widget.repository);
    if (!mounted || !current()) return;

    try {
      await Clipboard.setData(
        ClipboardData(
          text: markdown
              ? markdownAttachment(image.name, image.uri, image: true)
              : image.uri.toString(),
        ),
      );
      if (mounted && current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('已复制', 'Copied'))));
      }
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
    }
  }

  Future<void> _share() async {
    final epoch = _epoch;
    final repository = widget.repository;
    final image = widget.image;
    bool current() =>
        _current && epoch == _epoch && identical(repository, widget.repository);
    if (!mounted || !current()) return;

    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile file;
      final String name;
      if (repository is LocalImagesRepository && widget.share == null) {
        file = await _work(() => (repository).localShareFile(image));
        name = imageShareName(widget.image.name, widget.image.mime);
      } else {
        final data = await _bytes;
        if (!mounted || !current()) return;
        name = imageShareName(
          widget.image.name,
          imageContentMime(data) ?? widget.image.mime,
        );
        if (widget.share != null) {
          await widget.share!(data, name);
          return;
        }
        file = XFile.fromData(
          data,
          mimeType: imageContentMime(data) ?? widget.image.mime,
        );
      }
      if (!mounted || !current()) return;
      final box = context.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [name],
          sharePositionOrigin: origin,
        ),
      );
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final epoch = _epoch;
    final repository = widget.repository;
    final image = widget.image;
    bool current() =>
        _current && epoch == _epoch && identical(repository, widget.repository);
    if (!mounted || !current()) return;

    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('删除图片？', 'Delete image?')),
        content: Text(
          t(
            '引用此图片的内容可能无法显示。公开链接的已有缓存可能继续可访问。',
            'Content referencing this image may stop displaying it. Existing caches of public links may remain accessible.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !current()) return;
    setState(() {
      _busy = true;
      _deleting = true;
      _error = null;
    });
    try {
      final result = await _work(() => repository.remove(image));
      if (mounted && current()) {
        setState(() => _leaveAllowed = true);
        Navigator.pop(
          context,
          ImagePreviewOutcome(
            removal: result,
            needsVerification: !result.recordRemoved,
          ),
        );
      }
    } catch (error) {
      if (mounted && current()) {
        setState(() {
          _error = error.toString();
          _needsVerification =
              !(error is ApiFailure &&
                  {400, 401, 403, 405}.contains(error.status));
        });
      }
    } finally {
      if (mounted && current()) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    final epoch = _epoch;
    final repository = widget.repository;
    final image = widget.image;
    bool current() =>
        _current && epoch == _epoch && identical(repository, widget.repository);
    if (!mounted || !current()) return;

    if (_busy) return;
    setState(() {
      _busy = true;
      _deleting = true;
      _error = null;
    });
    try {
      final result = await _work(() => repository.verifyRemoval(image));
      if (!mounted || !current()) return;
      if (result.recordRemoved) {
        setState(() => _leaveAllowed = true);
        Navigator.pop(context, ImagePreviewOutcome(removal: result));
      } else {
        setState(() {
          _needsVerification = false;
          _error = t(
            '图片记录仍存在，可检查后重新删除。',
            'The image record still exists; review before deleting again.',
          );
        });
      }
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
    } finally {
      if (mounted && current()) {
        setState(() {
          _busy = false;
          _deleting = false;
        });
      }
    }
  }

  Future<void> _leave() async {
    if (!_current) {
      Navigator.maybePop(context);
      return;
    }
    final epoch = _epoch;
    if (_askingLeave) return;
    if (_deleting) {
      _askingLeave = true;
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('离开预览？', 'Leave preview?')),
          content: Text(
            t(
              '删除请求可能仍在处理，离开不会撤回已经提交的请求。',
              'Deletion may still be processing. Leaving does not retract a submitted request.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续等待', 'Keep waiting')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('离开', 'Leave')),
            ),
          ],
        ),
      );
      _askingLeave = false;
      if (leave != true || (!_current || epoch != _epoch)) return;
    }
    if (!mounted) return;
    setState(() => _leaveAllowed = true);
    Navigator.pop(
      context,
      ImagePreviewOutcome(needsVerification: _deleting || _needsVerification),
    );
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(value),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(value)),
          ],
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return Scaffold(
        appBar: AppBar(title: Text(t('空间已切换', 'Space changed'))),
        body: Center(
          child: Text(
            t(
              '此预览已关闭。请返回当前空间。',
              'This preview is closed. Return to the current space.',
            ),
          ),
        ),
      );
    }
    final image = widget.image;
    final local = !widget.repository.publicLinks;
    return PopScope(
      canPop: _leaveAllowed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('关闭', 'Close'),
            onPressed: _leave,
            icon: const Icon(Icons.close),
          ),
          title: Text(image.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: t('分享图片文件', 'Share image file'),
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.share),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              if (_needsVerification)
                OutlinedButton(
                  onPressed: _busy ? null : _verify,
                  child: Text(t('核对删除结果', 'Verify deletion result')),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    height: (MediaQuery.sizeOf(context).width * 0.65).clamp(
                      120,
                      320,
                    ),
                    child: FutureBuilder<Uint8List>(
                      key: ValueKey(_epoch),
                      future: _bytes,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t('图片读取失败', 'Image failed to load')),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _reload(force: true)),
                                  child: Text(t('重试', 'Retry')),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return LayoutBuilder(
                          builder: (context, constraints) => InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 8,
                            child: NativeImage(
                              bytes: snapshot.data!,
                              label: image.name,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              maxDecodeSide: 4096,
                              english: widget.english,
                              onRetry: () =>
                                  setState(() => _reload(force: true)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t('双指缩放 · 拖动查看', 'Pinch to zoom · Drag to pan'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('图片信息', 'Image information'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _info(t('文件名', 'File name'), image.name),
                      const Divider(),
                      _info(
                        t('尺寸', 'Dimensions'),
                        image.knownDimensions
                            ? '${image.width}×${image.height}'
                            : t('尺寸未知', 'Dimensions unknown'),
                      ),
                      const Divider(),
                      _info(t('文件大小', 'File size'), imageSizeLabel(image.size)),
                      const Divider(),
                      _info(
                        t('分类', 'Category'),
                        imageCategoryLabel(
                          image.category,
                          english: widget.english,
                        ),
                      ),
                      const Divider(),
                      _info(
                        local
                            ? t('本地保存时间', 'Local save time')
                            : t('上传时间', 'Uploaded'),
                        image.createdOn.isEmpty ||
                                image.createdOn.startsWith('0001')
                            ? t('未知', 'Unknown')
                            : image.createdOn,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        local
                            ? t(
                                '本地引用，仅本空间可用',
                                'Local reference, usable only in this space',
                              )
                            : t('图片链接公开', 'Image link is public'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        image.uri.toString(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _copy(false),
                            icon: const Icon(Icons.copy),
                            label: Text(
                              local
                                  ? t('复制本地引用', 'Copy local reference')
                                  : t('复制链接', 'Copy link'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _copy(true),
                            icon: const Icon(Icons.copy),
                            label: Text(t('复制Markdown', 'Copy Markdown')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : _needsVerification
                    ? _verify
                    : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  _needsVerification
                      ? t('先核对删除结果', 'Verify deletion first')
                      : t('删除图片', 'Delete image'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  '删除可能使文档中的图片引用失效。',
                  'Deletion may break image references in your content.',
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
