import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Native PDFium rendering with explicit page controls, no embedded browser.
class NativePdf extends StatefulWidget {
  const NativePdf({
    super.key,
    required this.sourceName,
    this.bytes,
    this.filePath,
    this.english = false,
  }) : assert((bytes == null) != (filePath == null));
  final String sourceName;
  final Uint8List? bytes;
  final String? filePath;
  final bool english;
  @override
  State<NativePdf> createState() => _NativePdfState();
}

class _NativePdfState extends State<NativePdf> {
  PdfDocument? _document;
  ui.Image? _image;
  PdfPageRenderCancellationToken? _token;
  Future<void>? _renderTask;
  Timer? _timer;
  final _number = TextEditingController(text: '1');
  final _transform = TransformationController();
  int _generation = 0, _page = 1;
  bool _loading = true, _textMode = false;
  String? _error, _text;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant NativePdf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.filePath != widget.filePath ||
        oldWidget.sourceName != widget.sourceName) {
      _open();
    }
  }

  void _release(ui.Image? image) {
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _token?.cancel();
    final doc = _document;
    _document = null;
    final work = _renderTask;
    unawaited(() async {
      try {
        await work;
      } catch (_) {}
      await doc?.dispose();
    }());
    _release(_image);
    _number.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<String?> _password() async {
    if (!mounted) return null;
    final value = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('输入PDF密码', 'PDF password')),
          content: TextField(
            controller: value,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: t('密码', 'Password')),
            onSubmitted: (text) => Navigator.pop(context, text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value.text),
              child: Text(t('打开', 'Open')),
            ),
          ],
        ),
      );
    } finally {
      value.dispose();
    }
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _token?.cancel();
    _timer?.cancel();
    final oldImage = _image;
    _image = null;
    _release(oldImage);
    final previous = _document;
    _document = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _text = null;
      });
    }
    try {
      try {
        await _renderTask;
      } catch (_) {}
      await previous?.dispose();
      if (!mounted || generation != _generation) return;
      await pdfrxFlutterInitialize();
      final doc = widget.bytes != null
          ? await PdfDocument.openData(
              widget.bytes!,
              sourceName: widget.sourceName,
              passwordProvider: _password,
            )
          : await PdfDocument.openFile(
              widget.filePath!,
              passwordProvider: _password,
            );
      if (!mounted || generation != _generation) {
        await doc.dispose();
        return;
      }
      if (doc.pages.isEmpty) {
        await doc.dispose();
        throw const FormatException('PDF has no pages');
      }
      _document = doc;
      _page = 1;
      _number.text = '1';
      await _render();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _render() {
    final task = _renderPage();
    _renderTask = task;
    return task;
  }

  Future<void> _renderPage() async {
    final doc = _document;
    if (doc == null) return;
    final generation = _generation, pageNumber = _page;
    final page = doc.pages[pageNumber - 1];
    _token?.cancel();
    final token = page.createCancellationToken();
    _token = token;
    final oldImage = _image;
    setState(() {
      _loading = true;
      _error = null;
      _text = null;
      _image = null;
    });
    _release(oldImage);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 30), () {
      token.cancel();
      if (mounted && generation == _generation) {
        setState(
          () => _error = t(
            '页面渲染耗时较长，正在停止。',
            'Page rendering is taking too long; stopping.',
          ),
        );
      }
    });
    ui.Image? image;
    try {
      if (page.width <= 0 ||
          page.height <= 0 ||
          !page.width.isFinite ||
          !page.height.isFinite) {
        throw const FormatException('Invalid PDF page dimensions');
      }
      final scale = math.min(2.0, 2048 / math.max(page.width, page.height));
      final width = math.max(1, (page.width * scale).round()),
          height = math.max(1, (page.height * scale).round());
      final raster = await page.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xffffffff,
        cancellationToken: token,
      );
      if (raster == null) {
        throw StateError(t('页面渲染已停止，请重试。', 'Page rendering stopped; retry.'));
      }
      try {
        image = await raster.createImage(pixelSizeThreshold: 2048);
      } finally {
        raster.dispose();
      }
      String? text;
      if (_textMode) {
        text = (await page.loadText())?.fullText;
        if (text != null && text.length > 100000) {
          text =
              '${text.substring(0, 100000)}\n${t('本页文本过长，仅展示前100000字符。', 'Page text is too long; showing the first 100000 characters.')}';
        }
      }
      if (!mounted || generation != _generation || pageNumber != _page) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _image = image;
        _text = text;
        _loading = false;
        _transform.value = Matrix4.identity();
      });
      _release(old);
    } catch (error) {
      image?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    } finally {
      if (identical(_token, token)) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void _go(int number) {
    final doc = _document;
    if (_loading || doc == null) return;
    if (number < 1 || number > doc.pages.length) {
      _number.text = '$_page';
      return;
    }
    setState(() => _page = number);
    _number.text = '$number';
    _render();
  }

  @override
  Widget build(BuildContext context) {
    final count = _document?.pages.length;
    return ColoredBox(
      color: const Color(0xffe2e8f0),
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _error != null
                  ? Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () =>
                                        _document == null ? _open() : _render(),
                              child: Text(t('重试', 'Retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _textMode
                  ? SingleChildScrollView(
                      child: SelectableText(
                        _text ?? t('正在读取本页文本…', 'Reading page text…'),
                      ),
                    )
                  : _image == null
                  ? Center(child: Text(t('正在打开PDF…', 'Opening PDF…')))
                  : LayoutBuilder(
                      builder: (context, constraints) => InteractiveViewer(
                        transformationController: _transform,
                        minScale: 0.5,
                        maxScale: 8,
                        child: Semantics(
                          image: true,
                          label: t(
                            'PDF第$_page页，共$count页',
                            'PDF page $_page of $count',
                          ),
                          child: RawImage(
                            image: _image,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 4,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                IconButton(
                  tooltip: t('上一页', 'Previous page'),
                  onPressed: _loading || _page <= 1
                      ? null
                      : () => _go(_page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _number,
                    enabled: !_loading && count != null,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.all(12),
                      labelText: t('页码', 'Page'),
                    ),
                    onSubmitted: (value) => _go(int.tryParse(value) ?? _page),
                  ),
                ),
                Text('/ ${count ?? '—'}'),
                IconButton(
                  tooltip: t('下一页', 'Next page'),
                  onPressed: _loading || count == null || _page >= count
                      ? null
                      : () => _go(_page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: t('适合页面', 'Fit page'),
                  onPressed: _image == null
                      ? null
                      : () => _transform.value = Matrix4.identity(),
                  icon: const Icon(Icons.fit_screen),
                ),
                IconButton(
                  tooltip: _textMode
                      ? t('查看页面', 'View page')
                      : t('查看本页文本', 'Read page text'),
                  onPressed: _loading || count == null
                      ? null
                      : () {
                          setState(() => _textMode = !_textMode);
                          _render();
                        },
                  icon: Icon(
                    _textMode
                        ? Icons.image_outlined
                        : Icons.text_snippet_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
