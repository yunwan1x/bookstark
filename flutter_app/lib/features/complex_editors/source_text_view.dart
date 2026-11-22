import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'source_chunks.dart';

/// Plain recovery source retains its existing lazy list. Decorated reading
/// anchors index navigation directly at a chunk rather than laying out all
/// intervening variable-height paragraphs during a scrollbar drag.
class SourceTextView extends StatefulWidget {
  const SourceTextView({
    super.key,
    required this.source,
    this.decorated = false,
    this.english = false,
    this.controller,
  });

  final String source;
  final bool decorated;
  final bool english;

  /// Optional controller for the plain recovery list.
  final ScrollController? controller;

  @override
  State<SourceTextView> createState() => _SourceTextViewState();
}

class _SourceTextViewState extends State<SourceTextView> {
  late SourceChunks chunks = SourceChunks(widget.source);

  @override
  void didUpdateWidget(covariant SourceTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      chunks = SourceChunks(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.decorated && chunks.length > 0) {
      return _IndexedSourceView(chunks: chunks, english: widget.english);
    }
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.all(16),
      itemCount: chunks.length,
      itemBuilder: (_, index) => SelectableText(
        chunks.at(index),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}

class _IndexedSourceView extends StatefulWidget {
  const _IndexedSourceView({required this.chunks, required this.english});
  final SourceChunks chunks;
  final bool english;

  @override
  State<_IndexedSourceView> createState() => _IndexedSourceViewState();
}

class _IndexedSourceViewState extends State<_IndexedSourceView> {
  final _viewport = GlobalKey();
  Map<int, GlobalKey> _items = {};
  ScrollController _scroll = ScrollController(keepScrollOffset: false);
  final _retiredControllers = <ScrollController>{};
  final _progress = ValueNotifier<double>(0);
  final _dragPreview = ValueNotifier<double?>(null);
  int _anchor = 0, _epoch = 0, _visibleIndex = 0;
  bool _frameQueued = false;

  int get _count => widget.chunks.length;

  String _positionText(int index) => widget.english
      ? 'Part ${index + 1} / $_count'
      : '第 ${index + 1} / $_count 段';

  @override
  void didUpdateWidget(covariant _IndexedSourceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chunks.source, widget.chunks.source)) {
      _replaceAnchor(0);
    }
  }

  void _replaceAnchor(int index) {
    final previous = _scroll;
    _retiredControllers.add(previous);
    _scroll = ScrollController(keepScrollOffset: false);
    _anchor = index;
    _visibleIndex = index;
    _items = {};
    _epoch++;
    _progress.value = _fractionForIndex(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredControllers.remove(previous)) previous.dispose();
    });
    _scheduleVisible();
  }

  void _jumpTo(int index) {
    if (!mounted) return;
    setState(() => _replaceAnchor(index.clamp(0, _count - 1)));
  }

  double _fractionForIndex(int index) => _count <= 1 ? 0 : index / (_count - 1);

  int _indexForFraction(double fraction) =>
      (fraction.clamp(0, 1) * (_count - 1)).round();

  void _scheduleVisible() {
    if (!mounted || _frameQueued) return;
    _frameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (mounted) _refreshVisible();
    });
  }

  void _refreshVisible() {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final area = viewport.localToGlobal(Offset.zero) & viewport.size;
    int? first;
    Rect? firstRect;
    for (final entry in _items.entries) {
      final item = entry.value.currentContext?.findRenderObject();
      if (item is! RenderBox || !item.attached || !item.hasSize) continue;
      final rect = item.localToGlobal(Offset.zero) & item.size;
      if (rect.bottom <= area.top || rect.top >= area.bottom) continue;
      if (first == null || entry.key < first) {
        first = entry.key;
        firstRect = rect;
      }
    }
    if (first == null || firstRect == null) return;
    _visibleIndex = first;
    final within =
        ((area.top - firstRect.top) / math.max(1.0, firstRect.height)).clamp(
          0.0,
          1.0,
        );
    _progress.value = _count <= 1
        ? 0
        : ((first + within) / (_count - 1)).clamp(0.0, 1.0);
  }

  double _thumbExtent(double height) =>
      math.min(height, math.max(48.0, height / _count));

  double _dragFraction(double dy, double height) =>
      ((dy - _thumbExtent(height) / 2) /
              math.max(1.0, height - _thumbExtent(height)))
          .clamp(0.0, 1.0);

  Widget _item(int index) => _SourceChunkCard(
    key: _items.putIfAbsent(index, () => GlobalKey()),
    text: widget.chunks.at(index),
    index: index,
    count: _count,
    english: widget.english,
  );

  @override
  Widget build(BuildContext context) {
    _scheduleVisible();
    final center = ValueKey('source-center-$_epoch');
    return Stack(
      children: [
        Positioned.fill(
          child: SizedBox.expand(
            key: _viewport,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notice) {
                if (notice.depth == 0) _scheduleVisible();
                return false;
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: CustomScrollView(
                  key: ValueKey('source-window-$_epoch'),
                  controller: _scroll,
                  center: center,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _item(_anchor - index - 1),
                        childCount: _anchor,
                        addSemanticIndexes: false,
                      ),
                    ),
                    SliverList(
                      key: center,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _item(_anchor + index),
                        childCount: _count - _anchor,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: LayoutBuilder(
            builder: (context, bounds) => AnimatedBuilder(
              animation: Listenable.merge([_progress, _dragPreview]),
              builder: (context, _) {
                final fraction = _dragPreview.value ?? _progress.value;
                final index = _dragPreview.value == null
                    ? _visibleIndex
                    : _indexForFraction(fraction);
                final extent = _thumbExtent(bounds.maxHeight);
                return GestureDetector(
                  key: const ValueKey('source-index-scrollbar'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (event) {
                    _dragPreview.value = _dragFraction(
                      event.localPosition.dy,
                      bounds.maxHeight,
                    );
                  },
                  onVerticalDragUpdate: (event) {
                    _dragPreview.value = _dragFraction(
                      event.localPosition.dy,
                      bounds.maxHeight,
                    );
                  },
                  onVerticalDragEnd: (_) {
                    final target = _dragPreview.value;
                    _dragPreview.value = null;
                    if (target != null) _jumpTo(_indexForFraction(target));
                  },
                  onVerticalDragCancel: () => _dragPreview.value = null,
                  onTapUp: (event) => _jumpTo(
                    _indexForFraction(
                      _dragFraction(event.localPosition.dy, bounds.maxHeight),
                    ),
                  ),
                  child: Semantics(
                    label: widget.english ? 'Source position' : '原文位置',
                    value: _positionText(index),
                    increasedValue: index + 1 < _count
                        ? _positionText(index + 1)
                        : null,
                    decreasedValue: index > 0 ? _positionText(index - 1) : null,
                    onIncrease: index + 1 < _count
                        ? () => _jumpTo(index + 1)
                        : null,
                    onDecrease: index > 0 ? () => _jumpTo(index - 1) : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          right: 0,
                          top: fraction * (bounds.maxHeight - extent),
                          width: 8,
                          height: extent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xff2474dd),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in _retiredControllers) {
      controller.dispose();
    }
    _retiredControllers.clear();
    _progress.dispose();
    _dragPreview.dispose();
    super.dispose();
  }
}

class _SourceChunkCard extends StatelessWidget {
  const _SourceChunkCard({
    super.key,
    required this.text,
    required this.index,
    required this.count,
    required this.english,
  });
  final String text;
  final int index, count;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final heading = english
        ? 'Source · part ${index + 1} / $count'
        : '原文 · 第 ${index + 1} / $count 段';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        index == 0 ? 16 : 0,
        16,
        index + 1 == count ? 16 : 12,
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffd8e0e9)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    heading,
                    style: const TextStyle(
                      color: Color(0xff476f9e),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
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
