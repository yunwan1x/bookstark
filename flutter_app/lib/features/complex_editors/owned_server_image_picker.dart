import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/owned_complex_server_images.dart';

Future<OwnedComplexServerImage?> chooseOwnedServerImage(
  BuildContext context, {
  required OwnedComplexServerImages library,
  bool english = false,
  bool protectedDocument = false,
}) => showDialog<OwnedComplexServerImage>(
  context: context,
  builder: (_) => _ServerImagePicker(
    library: library,
    english: english,
    protectedDocument: protectedDocument,
  ),
);

class _ServerImagePicker extends StatefulWidget {
  const _ServerImagePicker({
    required this.library,
    required this.english,
    required this.protectedDocument,
  });
  final OwnedComplexServerImages library;
  final bool english, protectedDocument;
  @override
  State<_ServerImagePicker> createState() => _ServerImagePickerState();
}

class _ServerImagePickerState extends State<_ServerImagePicker> {
  final _abort = Completer<void>();
  OwnedComplexServerImagePage? _page;
  OwnedComplexServerImage? _selected;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    unawaited(_load(1));
  }

  @override
  void dispose() {
    _generation++;
    _abort.complete();
    super.dispose();
  }

  Future<void> _load(int page) async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final result = await widget.library.read(
        page,
        abortTrigger: _abort.future,
      );
      if (!mounted ||
          generation != _generation ||
          !widget.library.lease.current) {
        return;
      }
      setState(() => _page = result);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = t(
            '图片列表暂不可用，未上传或插入图片。',
            'Server images unavailable. No image was uploaded or inserted.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t('服务器已有图片', 'Server images')),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t(
              '选择已有图片不会确认之前未知的上传结果。',
              'Selecting an existing image does not confirm an earlier unknown upload.',
            ),
          ),
          if (widget.protectedDocument)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t(
                  '服务器图片可通过地址访问，不受笔记密码保护。',
                  'Server images are accessible by address and are not protected by the note password.',
                ),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!),
            ),
          if (!_loading && _error == null && _page != null) ...[
            if (_page!.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  t('此页没有支持的图片。', 'No supported images on this page.'),
                ),
              ),
            RadioGroup<int>(
              groupValue: _selected?.id,
              onChanged: (id) {
                if (!mounted || !widget.library.lease.current) return;
                final matches = _page!.items
                    .where((image) => image.id == id)
                    .toList();
                if (id != null && matches.length != 1) return;
                setState(() => _selected = id == null ? null : matches.single);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final image in _page!.items)
                    RadioListTile<int>(
                      value: image.id,
                      title: Text(
                        image.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${image.width} × ${image.height} · ${(image.bytes + 1023) ~/ 1024} KB',
                      ),
                    ),
                ],
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: !_loading && (_page?.page ?? 1) > 1
                    ? () => _load(_page!.page - 1)
                    : null,
                child: Text(t('上一页', 'Previous')),
              ),
              Text(t('第${_page?.page ?? 1}页', 'Page ${_page?.page ?? 1}')),
              TextButton(
                onPressed: !_loading && _page?.hasNext == true
                    ? () => _load(_page!.page + 1)
                    : null,
                child: Text(t('下一页', 'Next')),
              ),
              if (_error != null)
                TextButton(
                  onPressed: _loading ? null : () => _load(_page?.page ?? 1),
                  child: Text(t('重试读取', 'Retry reading')),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed:
            !_loading &&
                _error == null &&
                _selected != null &&
                widget.library.lease.current
            ? () => Navigator.pop(context, _selected)
            : null,
        child: Text(t('插入选中图片', 'Insert selected image')),
      ),
    ],
  );
}
