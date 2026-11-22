import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/native_owned_image_picker.dart';
import '../../core/attachments.dart';
import 'image_library_owner.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/image_upload_controller.dart';
import '../../core/images_repository.dart';
import 'image_format.dart';

class ImageUploadOutcome {
  const ImageUploadOutcome(this.confirmed, {this.needsVerification = false});
  final int confirmed;
  final bool needsVerification;
}

class ImageUploadPage extends StatefulWidget {
  const ImageUploadPage({
    super.key,
    required this.repository,
    this.english = false,
    this.initialFiles = const [],
    this.pickFiles,
    this.owner,
  });
  final ImagesRepository repository;
  final ImageLibraryOwner? owner;
  final bool english;
  final List<XFile> initialFiles;
  final Future<List<XFile>> Function()? pickFiles;
  @override
  State<ImageUploadPage> createState() => _ImageUploadPageState();
}

class _ImageUploadPageState extends State<ImageUploadPage> {
  late ImageUploadController _queue;
  NativeOwnedImagePicker? _nativePicker;
  VoidCallback? _removePickerBarrier;
  final _releasedImages = <XFile>{};
  Future<void> _retirePicker() async {
    final picker = _nativePicker;
    final removeBarrier = _removePickerBarrier;
    if (picker == null) return;
    await picker.retire();
    removeBarrier?.call();
    if (identical(picker, _nativePicker)) _removePickerBarrier = null;
  }

  void _retirePickerOnExit() {
    unawaited(
      _retirePicker().catchError((Object _) {
        // Native capability is revoked before cleanup. The owner's barrier stays
        // registered on failure, so Root never silently activates a new scope.
      }),
    );
  }

  Future<List<XFile>> _pickDefault(bool Function() current) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final picker = _nativePicker ??= NativeOwnedImagePicker(
        isCurrent: current,
      );
      if (_removePickerBarrier == null && widget.owner != null) {
        _removePickerBarrier = widget.owner!.addRetirementBarrier(
          picker.retire,
        );
      }
      return picker.pick();
    }
    return openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: t('图片', 'Images'),
          extensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'],
          mimeTypes: const [
            'image/jpeg',
            'image/png',
            'image/gif',
            'image/webp',
            'image/svg+xml',
          ],
        ),
      ],
    );
  }

  Future<void> _releaseImage(XFile file) async {
    final epoch = _epoch;
    final picker = _nativePicker;
    if (picker == null || !picker.owns(file) || !_releasedImages.add(file)) {
      return;
    }
    try {
      await picker.release(file);
    } catch (error) {
      _releasedImages.remove(file);
      if (mounted &&
          _current &&
          epoch == _epoch &&
          identical(picker, _nativePicker)) {
        setState(() => _error = error.toString());
      }
    }
  }

  int _epoch = 0;
  bool get _current => mounted && (widget.owner?.isCurrent ?? true);
  bool _choosing = false, _allowLeave = false, _abandonedUncertain = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _queue = _newQueue();
    widget.owner?.addListener(_ownerChanged);
    _queue.addListener(_changed);
    if (widget.initialFiles.isNotEmpty) _initial();
  }

  @override
  void dispose() {
    _epoch++;
    _retirePickerOnExit();
    widget.owner?.removeListener(_ownerChanged);
    _queue.removeListener(_changed);
    _queue.dispose();
    super.dispose();
  }

  ImageUploadController _newQueue() {
    final epoch = _epoch;
    final repository = widget.repository;
    return ImageUploadController(
      _UploadRepository(
        repository,
        widget.owner,
        () =>
            _current &&
            epoch == _epoch &&
            identical(repository, widget.repository),
      ),
    );
  }

  void _ownerChanged() {
    if (!_current) {
      _queue.stop();
      _retirePickerOnExit();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ImageUploadPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.owner, widget.owner)) {
      _epoch++;
      final oldPicker = _nativePicker;
      final removeOldBarrier = _removePickerBarrier;
      _nativePicker = null;
      _removePickerBarrier = null;
      _releasedImages.clear();
      if (oldPicker != null) {
        unawaited(
          oldPicker.retire().then(
            (_) => removeOldBarrier?.call(),
            onError: (Object _) {},
          ),
        );
      }
      oldWidget.owner?.removeListener(_ownerChanged);
      _queue.removeListener(_changed);
      _queue.dispose();
      _queue = _newQueue();
      widget.owner?.addListener(_ownerChanged);
      _queue.addListener(_changed);
      _choosing = _allowLeave = _abandonedUncertain = false;
      _error = null;
    }
  }

  void _changed() {
    for (final entry in _queue.entries) {
      if (entry.completed) unawaited(_releaseImage(entry.file));
    }
    if (mounted) setState(() {});
  }

  Future<void> _initial() async {
    final epoch = _epoch, queue = _queue;
    bool current() => _current && epoch == _epoch && identical(queue, _queue);
    if (!current()) return;

    setState(() => _choosing = true);
    try {
      await queue.addFiles(widget.initialFiles);
    } finally {
      if (current()) setState(() => _choosing = false);
    }
  }

  Future<void> _pick() async {
    final epoch = _epoch, queue = _queue;
    bool current() => _current && epoch == _epoch && identical(queue, _queue);
    if (!current()) return;

    if (queue.running || _choosing) return;
    setState(() {
      _choosing = true;
      _error = null;
    });
    try {
      final files = await (widget.pickFiles?.call() ?? _pickDefault(current));
      if (current() && files.isNotEmpty) await queue.addFiles(files);
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
    } finally {
      if (current()) setState(() => _choosing = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _remove(ImageUploadEntry entry) async {
    final epoch = _epoch, queue = _queue;
    bool current() => _current && epoch == _epoch && identical(queue, _queue);
    if (!current()) return;

    if (entry.state == ImageUploadState.uncertain) {
      if (!await _confirm(
            t('移除此未确认项？', 'Remove unconfirmed item?'),
            t(
              '只移除队列项，不会删除服务器或本地空间可能已保存的图片。',
              'Only removes the queue entry; a possibly saved image is retained.',
            ),
            t('移除队列项', 'Remove entry'),
          ) ||
          !current()) {
        return;
      }
      _abandonedUncertain = true;
    }
    queue.remove(entry, abandonUncertain: true);
    if (!queue.entries.contains(entry)) await _releaseImage(entry.file);
  }

  Future<void> _retransmit(ImageUploadEntry entry) async {
    final epoch = _epoch, queue = _queue;
    bool current() => _current && epoch == _epoch && identical(queue, _queue);
    if (!current()) return;

    if (!await _confirm(
          t('明确重新上传？', 'Explicitly upload again?'),
          t(
            '当前尚未查到相同哈希，但前次请求可能仍在处理。重新上传仍可能产生重复条目。',
            'The hash has not been found yet, but the previous request may still be processing. Uploading again may create a duplicate.',
          ),
          t('重新加入待上传', 'Queue again'),
        ) ||
        !current()) {
      return;
    }
    queue.allowExplicitRetransmission(entry);
  }

  Future<void> _leave() async {
    if (!_current) {
      Navigator.maybePop(context);
      return;
    }
    final epoch = _epoch;
    final incomplete =
        _queue.running || _queue.pendingCount > 0 || _queue.uncertainCount > 0;
    if (incomplete) {
      if (!await _confirm(
            t('离开上传队列？', 'Leave upload queue?'),
            t(
              '待处理选择将被放弃。已提交的请求可能仍保存图片，返回后可刷新图片库核对。',
              'Pending selections are discarded. Submitted requests may still save images; refresh the library to verify.',
            ),
            t('离开', 'Leave'),
          ) ||
          (!_current || epoch != _epoch)) {
        return;
      }
    }
    if (!mounted) return;
    final result = ImageUploadOutcome(
      _queue.confirmedCount,
      needsVerification:
          _abandonedUncertain || _queue.running || _queue.uncertainCount > 0,
    );
    _queue.stop();
    setState(() => _allowLeave = true);
    Navigator.pop(context, result);
  }

  String _stateLabel(ImageUploadEntry entry) => switch (entry.state) {
    ImageUploadState.pending => t('待上传', 'Pending'),
    ImageUploadState.preparing => t('正在准备图片', 'Preparing image'),
    ImageUploadState.checking => t('正在核对已有图片', 'Checking existing images'),
    ImageUploadState.uploading => t(
      '${widget.repository.publicLinks ? '已发送' : '已写入'}${imageSizeLabel(entry.sent)} / ${imageSizeLabel(entry.sourceSize)}',
      '${widget.repository.publicLinks ? 'Sent' : 'Written'} ${imageSizeLabel(entry.sent)} / ${imageSizeLabel(entry.sourceSize)}',
    ),
    ImageUploadState.confirmed => t('已确认', 'Confirmed'),
    ImageUploadState.reused => t('已复用已有图片', 'Existing image reused'),
    ImageUploadState.failed => t('处理失败', 'Failed'),
    ImageUploadState.uncertain =>
      entry.verifying
          ? t('正在核对结果', 'Verifying result')
          : t('结果未确认', 'Unconfirmed'),
  };
  Widget _entry(ImageUploadEntry entry) {
    final completed = entry.completed;
    return Card(
      key: ValueKey('image-upload-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  completed
                      ? Icons.check_circle_outline
                      : entry.file.name.toLowerCase().endsWith('.svg')
                      ? Icons.code
                      : Icons.image_outlined,
                  color: completed
                      ? const Color(0xff15803d)
                      : const Color(0xff2563eb),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.file.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${imageSizeLabel(entry.sourceSize, english: widget.english)} · ${_stateLabel(entry)}',
                      ),
                      Text(
                        imageCategoryLabel(
                          entry.category.name,
                          english: widget.english,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('移除队列项', 'Remove entry'),
                  onPressed: _queue.running ? null : () => _remove(entry),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (entry.result != null) ...[
              const SizedBox(height: 8),
              Text(
                t(
                  '已确认文件：${entry.result!.name} · ${imageSizeLabel(entry.result!.size)}',
                  'Confirmed file: ${entry.result!.name} · ${imageSizeLabel(entry.result!.size)}',
                ),
              ),
            ],
            if (entry.error != null) ...[
              const SizedBox(height: 8),
              Text(
                entry.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (entry.state == ImageUploadState.failed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _queue.running
                      ? null
                      : () => _queue.retryRejected(entry),
                  child: Text(t('重新加入待处理', 'Queue for retry')),
                ),
              ),
            if (entry.state == ImageUploadState.uncertain)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _queue.running
                        ? null
                        : () => _queue.verify(entry),
                    child: Text(t('核对结果', 'Verify result')),
                  ),
                  if (entry.verifiedMissing)
                    TextButton(
                      onPressed: _queue.running
                          ? null
                          : () => _retransmit(entry),
                      child: Text(t('明确重新上传', 'Upload again explicitly')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return Scaffold(
        appBar: AppBar(title: Text(t('空间已切换', 'Space changed'))),
        body: Center(
          child: Text(
            t(
              '上传队列已关闭。已提交请求仍需核对。',
              'Upload queue closed. Submitted requests may need verification.',
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop:
          _allowLeave ||
          (!_queue.running &&
              _queue.pendingCount == 0 &&
              _queue.uncertainCount == 0),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.repository.publicLinks
                ? t('上传图片', 'Upload images')
                : t('添加图片', 'Add images'),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xffeff6ff),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.repository.publicLinks
                            ? t('图片链接公开', 'Image links are public')
                            : t('仅保存在当前本地空间', 'Saved only in this local space'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.repository.publicLinks
                            ? t(
                                '上传后会进入服务器图片库。',
                                'Uploads enter the server image library.',
                              )
                            : t(
                                '不会自动上传到服务器。',
                                'Nothing is automatically uploaded to a server.',
                              ),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('图片分类', 'Image category'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ImageCategory>(
                        key: ValueKey(_queue.category),
                        initialValue: _queue.category,
                        isExpanded: true,
                        items: [
                          for (final category in ImageCategory.values)
                            DropdownMenuItem(
                              value: category,
                              child: Text(
                                imageCategoryLabel(
                                  category.name,
                                  english: widget.english,
                                ),
                              ),
                            ),
                        ],
                        onChanged: _queue.running || _choosing
                            ? null
                            : (value) {
                                if (value != null) _queue.setCategory(value);
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(
                          '已开始处理的项目保留原分类。',
                          'Started items retain their original category.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _queue.running || _choosing ? null : _pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(t('选择图片（可多选）', 'Choose images (multiple)')),
              ),
              if (_choosing) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 24),
              Text(
                t(
                  '待处理${_queue.pendingCount}项 · 已确认${_queue.confirmedCount}项',
                  '${_queue.pendingCount} pending · ${_queue.confirmedCount} confirmed',
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in _queue.entries) _entry(entry),
              if (_queue.entries.isEmpty)
                Text(t('请选择要保存的图片。', 'Choose images to save.')),
              const SizedBox(height: 24),
              Card(
                color: const Color(0xfff1f5f9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.repository.publicLinks
                        ? t(
                            '静态图可能转为WebP，相同内容可能复用已有图片。',
                            'Static images may become WebP; identical content may reuse an existing image.',
                          )
                        : t(
                            '本地保留原文件，相同内容可复用已有图片。',
                            'Local images retain original bytes; identical content may be reused.',
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  '字节发送完成不等于保存成功，以实际确认结果为准。',
                  'Sending all bytes does not confirm a save; actual results determine completion.',
                ),
              ),
              const SizedBox(height: 24),
              if (_queue.running) ...[
                OutlinedButton(
                  onPressed: _queue.stopping ? null : _queue.stop,
                  child: Text(
                    _queue.stopping
                        ? t('已请求停止', 'Stop requested')
                        : t('停止处理', 'Stop processing'),
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                FilledButton(
                  onPressed: _choosing || _queue.pendingCount == 0
                      ? null
                      : _queue.start,
                  child: Text(
                    t(
                      '开始处理${_queue.pendingCount}项',
                      'Process ${_queue.pendingCount} items',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _leave,
                child: Text(t('返回图片库', 'Return to image library')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Upload-only facade; preview keeps the real LocalImagesRepository type.
/// Tracks individual transport work, never file-picker or human route futures.
class _UploadRepository extends ImagesRepository {
  _UploadRepository(this.delegate, this.owner, this.isCurrent);
  final ImagesRepository delegate;
  final ImageLibraryOwner? owner;
  final bool Function() isCurrent;
  Future<T> _call<T>(Future<T> Function() work) async {
    if (!isCurrent() || !(owner?.isCurrent ?? true)) {
      throw StateError('Image upload owner retired');
    }
    final result = await (owner?.run(work) ?? Future<T>.sync(work));
    if (!isCurrent() || !(owner?.isCurrent ?? true)) {
      throw StateError('Image upload owner retired');
    }
    return result;
  }

  @override
  bool get publicLinks => delegate.publicLinks;
  @override
  Future<ImagesPageResult> list(ImagesQuery query) =>
      _call(() => delegate.list(query));
  @override
  Future<UploadedImageReference?> byHash(String hash) =>
      _call(() => delegate.byHash(hash));
  @override
  Future<UploadedImageReference> upload(
    ImageUploadPayload payload, {
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) => _call(
    () => delegate.upload(
      payload,
      cancellation: cancellation,
      onSent: (sent, total) {
        if (isCurrent() && (owner?.isCurrent ?? true)) {
          onSent?.call(sent, total);
        }
      },
    ),
  );
  @override
  Future<ImageRemovalResult> remove(ManagedImage item) =>
      _call(() => delegate.remove(item));
  @override
  Future<ImageRemovalResult> verifyRemoval(ManagedImage item) =>
      _call(() => delegate.verifyRemoval(item));
  @override
  Future<Uint8List> bytes(
    Uri uri, {
    int maxBytes = maxImageTransferBytes,
    bool reload = false,
  }) => _call(() => delegate.bytes(uri, maxBytes: maxBytes, reload: reload));
}
