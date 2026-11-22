import 'speech/local_speech_provider_page.dart';
import 'speech/complex_reading_speech_capture.dart';
import '../core/complex_reading_protocol.dart';
import '../core/complex_editor_transport.dart';
// Prepared outside the frozen app. No repository or save capability.
import 'package:flutter/material.dart';

import '../core/documents_repository.dart';

import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';

import '../core/document_route_adapter.dart';

/// Root supplies existing authenticated native Markdown body and outer chapter
/// controls. This widget never invents a native complex editor or save writer.
class DocumentReadingSurface extends StatefulWidget {
  const DocumentReadingSurface({
    super.key,
    required this.route,
    required this.markdownBody,
    this.english = false,
    this.initialFraction = 0,
    this.onPartPosition,
    this.onExcerptCurrentPart,
    this.readingIdentity,
    this.initialReadingAnchor,
    this.onReadingAnchor,
    this.onExcerptSelectedText,
    this.onSpeakSelection,
  });
  final PreparedDocumentRoute route;
  final ComplexReadingIdentity? readingIdentity;
  final ComplexReadingAnchor? initialReadingAnchor;
  final Future<void> Function(ComplexReadingIdentity, ComplexReadingAnchor)?
  onReadingAnchor;
  final Future<void> Function(DocumentItem, String)? onExcerptSelectedText;
  final Future<void> Function(LocalSpeechSelection)? onSpeakSelection;
  final Widget Function(String source) markdownBody;
  final bool english;
  final double initialFraction;
  final Future<void> Function(DocumentItem item, double fraction)?
  onPartPosition;
  final Future<void> Function(DocumentItem item, String exactText)?
  onExcerptCurrentPart;
  @override
  State<DocumentReadingSurface> createState() => _DocumentReadingSurfaceState();
}

class _DocumentReadingSurfaceState extends State<DocumentReadingSurface> {
  late SourceChunks chunks;
  ComplexEditorTransport? readingTransport;
  int part = 0, epoch = 0;
  bool revealed = false, busy = false;
  String? error;
  String t(String zh, String en) => widget.english ? en : zh;

  void initialize() {
    epoch++;
    readingTransport = null;
    busy = false;
    chunks = SourceChunks(widget.route.source);
    final fraction = widget.initialFraction;
    if (!fraction.isFinite || fraction < 0 || fraction > 1) {
      throw const FormatException('Invalid reading fraction');
    }
    part = chunks.length < 2 ? 0 : (fraction * (chunks.length - 1)).floor();
    revealed = widget.route.editGate == DocumentEditGate.markdownTooLarge;
    error = null;
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void didUpdateWidget(covariant DocumentReadingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route.item.id != widget.route.item.id ||
        oldWidget.route.item.bookId != widget.route.item.bookId ||
        oldWidget.route.item.modifiedAt != widget.route.item.modifiedAt ||
        oldWidget.route.item.type != widget.route.item.type ||
        oldWidget.route.editGate != widget.route.editGate ||
        oldWidget.route.source != widget.route.source ||
        oldWidget.readingIdentity?.fullFingerprint !=
            widget.readingIdentity?.fullFingerprint) {
      initialize();
    }
  }

  Future<void> go(int next) async {
    if (busy || next < 0 || next >= chunks.length) return;
    final ownerEpoch = epoch, item = widget.route.item;
    setState(() {
      part = next;
      busy = true;
      error = null;
    });
    try {
      await widget.onPartPosition?.call(
        item,
        chunks.length < 2 ? 0 : next / (chunks.length - 1),
      );
    } catch (_) {
      if (mounted && epoch == ownerEpoch) {
        setState(
          () => error = t(
            '阅读位置未保存，请重试。',
            'Reading position was not saved. Retry.',
          ),
        );
      }
    } finally {
      if (mounted && epoch == ownerEpoch) setState(() => busy = false);
    }
  }

  Future<void> excerpt() async {
    if (busy || chunks.length == 0 || widget.onExcerptCurrentPart == null) {
      return;
    }
    final ownerEpoch = epoch, item = widget.route.item;
    final exactText = chunks.at(part);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onExcerptCurrentPart!(item, exactText);
    } catch (_) {
      if (mounted && epoch == ownerEpoch) {
        setState(() => error = t('摘录未完成，请重试。', 'Excerpt incomplete. Retry.'));
      }
    } finally {
      if (mounted && epoch == ownerEpoch) setState(() => busy = false);
    }
  }

  Future<void> jump() async {
    final ownerEpoch = epoch;
    final input = TextEditingController(text: '${part + 1}');
    try {
      final next = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('跳转到段', 'Go to part')),
          content: TextField(
            controller: input,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '1–${chunks.length}'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(input.text);
                if (value != null && value >= 1 && value <= chunks.length) {
                  Navigator.pop(context, value - 1);
                }
              },
              child: Text(t('跳转', 'Go')),
            ),
          ],
        ),
      );
      if (mounted && epoch == ownerEpoch && next != null) await go(next);
    } finally {
      input.dispose();
    }
  }

  Future<void> readingAction(String action) async {
    final transport = readingTransport, identity = widget.readingIdentity;
    if (busy || transport == null || identity == null) return;
    final ownerEpoch = epoch, item = widget.route.item;
    setState(() {
      busy = true;
      error = null;
    });
    bool current() =>
        mounted &&
        epoch == ownerEpoch &&
        identical(readingTransport, transport);
    try {
      if (action == 'speak') {
        final callback = widget.onSpeakSelection;
        if (callback == null) return;
        final selection = await captureComplexReadingSpeech(
          transport: transport,
          identity: identity,
          isCurrentSource: current,
        );
        if (!current() || !selection.current) return;
        await callback(selection);
      } else if (action == 'resume') {
        final saved = widget.initialReadingAnchor;
        if (saved == null) throw StateError('Reading anchor unavailable');
        await transport.restoreReading(saved);
      } else {
        final capture = await transport.captureReading(
          includeSelection: action == 'excerpt',
        );
        if (!current()) return;
        if (!capture.supported) {
          throw StateError('Reading operation unsupported');
        }
        if (action == 'excerpt') {
          if (capture.text.isEmpty) throw StateError('Select text first');
          await widget.onExcerptSelectedText?.call(item, capture.text);
        } else {
          final anchor = capture.anchor;
          if (anchor == null) throw StateError('Reading anchor unavailable');
          await widget.onReadingAnchor?.call(identity, anchor);
        }
      }
    } catch (_) {
      if (current()) {
        setState(
          () => error = t(
            '操作未完成。请确认已选中文字，或重试阅读位置。',
            'Action did not complete. Select text, or retry the reading position.',
          ),
        );
      }
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    readingTransport = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    if (route.mode == DocumentReadingMode.markdown) {
      return widget.markdownBody(route.source);
    }
    if (route.mode == DocumentReadingMode.complexWebView) {
      return LayoutBuilder(
        builder: (context, readingBox) => Column(
          children: [
            Expanded(
              child: ComplexEditorBrowser(
                document: route.document!,
                title: route.item.name,
                english: widget.english,
                readOnly: true,
                readingIdentity: widget.readingIdentity,
                onReady: (transport) async {
                  if (mounted) setState(() => readingTransport = transport);
                },
                onState: (state) {
                  if (!state.ready && mounted) {
                    setState(() => readingTransport = null);
                  }
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: readingBox.maxHeight * .4),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    if (error != null) Text(error!),
                    if (widget.readingIdentity == null ||
                        !{
                          'html',
                          'richdoc',
                          'spreadsheet',
                          'drawing',
                          'mindmap',
                          'presentation',
                        }.contains(route.item.type))
                      Text(
                        t(
                          '当前位置与摘录尚不可用；原文完整保留。',
                          'Reading position and excerpt unavailable. Original source retained.',
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (widget.initialReadingAnchor != null)
                            TextButton(
                              onPressed: busy || readingTransport == null
                                  ? null
                                  : () => readingAction('resume'),
                              child: Text(t('继续上次阅读', 'Resume reading')),
                            ),
                          if (widget.onReadingAnchor != null)
                            TextButton(
                              onPressed: busy || readingTransport == null
                                  ? null
                                  : () => readingAction('position'),
                              child: Text(t('保存阅读位置', 'Save reading position')),
                            ),
                          if (widget.onSpeakSelection != null)
                            TextButton(
                              onPressed: busy || readingTransport == null
                                  ? null
                                  : () => readingAction('speak'),
                              child: Text(
                                route.item.type == 'presentation'
                                    ? t(
                                        '捕获并朗读当前页',
                                        'Capture and read current slide',
                                      )
                                    : t(
                                        '捕获并朗读选区',
                                        'Capture and read selection',
                                      ),
                              ),
                            ),
                          if (widget.onExcerptSelectedText != null)
                            TextButton(
                              onPressed: busy || readingTransport == null
                                  ? null
                                  : () => readingAction('excerpt'),
                              child: Text(switch (route.item.type) {
                                'presentation' => t(
                                  '摘录当前幻灯片',
                                  'Excerpt current slide',
                                ),
                                'mindmap' => t(
                                  '摘录选中节点',
                                  'Excerpt selected nodes',
                                ),
                                'drawing' => t(
                                  '摘录选中元素',
                                  'Excerpt selected elements',
                                ),
                                'spreadsheet' => t(
                                  '摘录选中单元格',
                                  'Excerpt selected cells',
                                ),
                                _ => t('摘录选中文字', 'Excerpt selected text'),
                              }),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (!revealed) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                '当前格式无法预览；原文已保留，不会生成空文档。',
                'Preview unavailable. Original source is preserved.',
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => revealed = true),
              child: Text(t('查看完整原文（只读）', 'View full original (read only)')),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * .3),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(
                t(
                  '只读 · 全文完整保留，当前内容不可编辑。',
                  'Read only. Full source preserved; editing unavailable.',
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: ValueKey((route.item.bookId, route.item.id, part)),
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                chunks.length == 0 ? '' : chunks.at(part),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * .4),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    widget.english
                        ? 'Part ${chunks.length == 0 ? 0 : part + 1} / ${chunks.length}'
                        : '第 ${chunks.length == 0 ? 0 : part + 1} / ${chunks.length} 段',
                  ),
                  if (error != null) Text(error!),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy || part <= 0
                            ? null
                            : () => go(part - 1),
                        child: Text(t('上一段', 'Previous part')),
                      ),
                      OutlinedButton(
                        onPressed: busy || part + 1 >= chunks.length
                            ? null
                            : () => go(part + 1),
                        child: Text(t('下一段', 'Next part')),
                      ),
                      OutlinedButton(
                        onPressed: busy || chunks.length == 0 ? null : jump,
                        child: Text(t('跳转到段', 'Go to part')),
                      ),
                      if (widget.onExcerptCurrentPart != null)
                        OutlinedButton(
                          onPressed: busy || chunks.length == 0
                              ? null
                              : excerpt,
                          child: Text(t('摘录当前段', 'Excerpt current part')),
                        ),
                      const FilledButton(
                        onPressed: null,
                        child: Text('编辑 / Edit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
