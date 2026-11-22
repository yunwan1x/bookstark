import '../../widgets/background_fade_slider.dart';
import '../../core/app_theme.dart';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/background_repository.dart';
import '../../core/background_controller.dart';
import '../../widgets/background_surface.dart';

typedef BackgroundPicker = Future<BackgroundUpload?> Function();

class BackgroundPage extends StatefulWidget {
  const BackgroundPage({
    super.key,
    required this.repository,
    required this.preference,
    required this.onApplied,
    this.picker,
    this.english = false,
  });
  final BackgroundRepository repository;
  final BackgroundPreference preference;
  final Future<void> Function(BackgroundPreference, Uint8List?) onApplied;
  final BackgroundPicker? picker;
  final bool english;
  @override
  State<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends State<BackgroundPage> {
  late final _controller = BackgroundController(
    widget.repository,
    widget.preference,
  );
  late String _mode = widget.preference.mode;
  late bool _animated = widget.preference.animated;
  late double _fade = widget.preference.fade.toDouble();
  bool _remove = false,
      _picking = false,
      _leaving = false,
      _loadingImage = false;
  BackgroundUpload? _upload;
  Uint8List? _savedImage;
  String? _localError;
  String t(String zh, String en) => widget.english ? en : zh;
  BackgroundDraft get _draft => BackgroundDraft(
    mode: _mode,
    animated: _animated,
    fade: _fade.round(),
    remove: _remove,
    image: _upload,
  );
  bool get _dirty =>
      _mode != _controller.baseline.mode ||
      _animated != _controller.baseline.animated ||
      _fade.round() != _controller.baseline.fade ||
      _remove ||
      _upload != null;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _loadImage();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadImage() async {
    final hash = _controller.baseline.imageHash;
    if (hash.isEmpty) {
      return;
    }
    setState(() => _loadingImage = true);
    try {
      final bytes = await widget.repository.image(hash);
      if (mounted && hash == _controller.baseline.imageHash) {
        setState(() => _savedImage = bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = t(
            '私有背景图片暂时无法读取。',
            'The private background image cannot be read yet.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingImage = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _savedImage = null;
    _upload = null;
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) {
      return;
    }
    setState(() => _picking = true);
    try {
      BackgroundUpload? upload;
      if (widget.picker != null) {
        upload = await widget.picker!();
      } else {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Background image',
              extensions: ['png', 'jpg', 'jpeg', 'webp'],
              mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
            ),
          ],
        );
        if (file != null) {
          if (await file.length() > 5 * 1024 * 1024) {
            throw const FormatException('Image too large');
          }
          upload = BackgroundUpload(await file.readAsBytes());
        }
      }
      if (mounted && upload != null) {
        setState(() {
          _upload = upload;
          _remove = false;
          _mode = 'image';
          _localError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = t(
            '请选择最多5MB、2000万像素的PNG、JPG或WebP图片。',
            'Choose a PNG, JPG or WebP up to5MiB and20 megapixels.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _save() async {
    try {
      await _controller.save(_draft);
      await _applyConfirmed();
    } on FormatException {
      if (mounted) {
        setState(
          () => _localError = t(
            '请先选择有效图片和背景设置。',
            'Choose a valid image and background settings first.',
          ),
        );
      }
    }
  }

  Future<void> _applyConfirmed() async {
    if (!mounted || _controller.phase != BackgroundPhase.confirmed) {
      return;
    }
    final actual = _controller.baseline;
    if (_controller.verifiedImage != null) {
      _savedImage = _controller.verifiedImage;
    }
    if (actual.imageHash.isEmpty) {
      _savedImage = null;
    }
    setState(() {
      _upload = null;
      _remove = false;
      _localError = null;
      _mode = actual.mode;
      _animated = actual.animated;
      _fade = actual.fade.toDouble();
    });
    try {
      await widget.onApplied(actual, _controller.verifiedImage);
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = t(
            '账户设置已保存，应用背景暂未更新。',
            'Account settings were saved. The application background has not updated yet.',
          ),
        );
      }
    }
  }

  Future<void> _inspect() async {
    await _controller.inspect();
    await _applyConfirmed();
  }

  void _useObserved() {
    final value = _controller.useObserved();
    setState(() {
      _mode = value.mode;
      _animated = value.animated;
      _fade = value.fade.toDouble();
      _remove = false;
      _upload = null;
      _savedImage = null;
    });
    _loadImage();
  }

  Future<void> _leave() async {
    if (_leaving || _controller.busy || _picking) {
      return;
    }
    if (_dirty || _controller.unresolved) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('离开背景设置？', 'Leave background settings?'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    '未保存预览将丢弃；服务器可能已接受尚未确认的修改。',
                    'Unsaved previews will be discarded. The server may have accepted an unconfirmed change.',
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('取消', 'Cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('离开', 'Leave')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (leave != true) {
        return;
      }
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Widget _card(List<Widget> children) => Card(
    semanticContainer: false,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  String _status() => switch (_controller.phase) {
    BackgroundPhase.checking => t('正在读取核对…', 'Reading current settings…'),
    BackgroundPhase.saving => t('正在保存背景…', 'Saving background…'),
    BackgroundPhase.failed => t(
      '未能保存，请核对账户、图片和连接。',
      'Could not save. Check account, image and connection.',
    ),
    BackgroundPhase.unknown => t(
      '保存结果未知，不会自动重发图片。',
      'The save result is unknown. The image will not be resent automatically.',
    ),
    BackgroundPhase.unverified => t(
      '已收到背景回执，尚未完成实际读取核对。',
      'Background receipt received. Actual readback is incomplete.',
    ),
    BackgroundPhase.conflict => t(
      '服务器背景已变化或上传来源尚未确认。请先采用实际设置。',
      'The server background changed or the uploaded image is unconfirmed. Use the actual preferences first.',
    ),
    BackgroundPhase.confirmed => t(
      '实际背景设置已核对。',
      'Actual background preferences verified.',
    ),
    _ => t('仅保存后应用到当前账户。', 'Applied to this account only after saving.'),
  };
  @override
  Widget build(BuildContext context) {
    final c = _controller,
        editable = !_controller.busy && !_controller.unresolved && !_picking;
    final bytes = _upload?.bytes ?? (_remove ? null : _savedImage);
    final preview = BackgroundPreference(
      mode: _mode,
      animated: _animated,
      fade: _fade.round(),
      imageHash: _mode == 'image' ? 'preview' : '',
    );
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('背景设置', 'Background settings')),
          actions: [
            TextButton(
              onPressed: editable && c.phase != BackgroundPhase.conflict
                  ? _save
                  : null,
              child: Text(t('保存', 'Save')),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card([
                  _heading(t('本地预览', 'Local preview')),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackgroundSurface(
                      preference: preview,
                      image: bytes,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('第一章 阅读的力量', 'Chapter1 The power of reading'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              t(
                                '阅读，是一场与更大世界的对话。记录想法，建立自己的知识体系。',
                                'Reading opens a conversation with a wider world. Record ideas and build your knowledge.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_loadingImage)
                    Text(t('正在读取私有图片…', 'Reading private image…')),
                ]),
                _card([
                  _heading(t('背景样式', 'Background style')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in {
                        'solid': t('纯色', 'Solid'),
                        'dynamic': t('动态渐变', 'Animated gradient'),
                        'image': t('自定义图片', 'Custom image'),
                      }.entries)
                        Semantics(
                          button: true,
                          enabled: editable,
                          selected: _mode == entry.key,
                          label: entry.value,
                          excludeSemantics: true,
                          onTap: editable
                              ? () => setState(() => _mode = entry.key)
                              : null,
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _mode == entry.key,
                            onSelected: editable
                                ? (_) => setState(() => _mode = entry.key)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  if (_mode == 'dynamic')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('启用渐变动画', 'Enable gradient animation')),
                      subtitle: Text(
                        t(
                          '减少动态效果时暂停动画',
                          'Paused when reduced motion is enabled',
                        ),
                      ),
                      value: _animated,
                      onChanged: editable
                          ? (v) => setState(() => _animated = v)
                          : null,
                    ),
                ]),
                _card([
                  _heading(t('背景淡化', 'Background fade')),
                  Text(t('提高淡化程度，便于阅读', 'Increase fading for easier reading')),
                  BackgroundFadeSlider(
                    label: t('背景淡化', 'Background fade'),
                    value: _fade,
                    onChanged: editable
                        ? (v) => setState(() => _fade = v)
                        : null,
                  ),
                  Text('${_fade.round()}%'),
                ]),
                _card([
                  _heading(t('自定义图片', 'Custom image')),
                  OutlinedButton.icon(
                    onPressed: editable ? _pick : null,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(t('选择图片', 'Choose image')),
                  ),
                  const SizedBox(height: 12),
                  Text(t('PNG、JPG或WebP，最多5MB', 'PNG, JPG or WebP, up to5MiB')),
                  if (_upload != null)
                    Text(
                      t(
                        '已选择本地图片，尚未保存。',
                        'Local image selected. It is not saved yet.',
                      ),
                    ),
                  if (c.baseline.imageHash.isNotEmpty && !_remove)
                    TextButton(
                      onPressed: editable ? _loadImage : null,
                      child: Text(t('重新读取私有图片', 'Reload private image')),
                    ),
                ]),
                _card([
                  Text(_status()),
                  if (_localError != null) Text(_localError!),
                  if (c.unresolved)
                    TextButton(
                      onPressed: c.busy ? null : _inspect,
                      child: Text(
                        t('只读核对背景结果', 'Verify background without writing'),
                      ),
                    ),
                  if (c.phase == BackgroundPhase.conflict)
                    TextButton(
                      onPressed: _useObserved,
                      child: Text(t('采用服务器背景', 'Use server background')),
                    ),
                ]),
                FilledButton(
                  onPressed: editable && c.phase != BackgroundPhase.conflict
                      ? _save
                      : null,
                  child: Text(t('保存背景设置', 'Save background preferences')),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: editable
                      ? () => setState(() {
                          _mode = 'dynamic';
                          _animated = true;
                          _fade = 65;
                          _remove = true;
                          _upload = null;
                        })
                      : null,
                  child: Text(
                    t('恢复默认并移除图片', 'Restore defaults and remove image'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
