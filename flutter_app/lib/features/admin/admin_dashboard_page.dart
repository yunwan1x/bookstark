import 'package:flutter/material.dart';

import 'admin_dashboard_controller.dart';
import 'admin_dashboard_repository.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    required this.controller,
    required this.onReturn,
    this.english = false,
  });

  final AdminDashboardController controller;
  final VoidCallback onReturn;
  final bool english;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  AdminDashboardController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  String get _rangeLabel => t('时间范围', 'Time range');

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.initialize();
  }

  @override
  void didUpdateWidget(covariant AdminDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.clearForSessionExit();
      c.addListener(_changed);
      c.initialize();
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.clearForSessionExit();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(14) > 20
            ? 168
            : 72,
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            c.clearForSessionExit();
            widget.onReturn();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('访问统计', 'Dashboard'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              t('管理员 · 服务器空间', 'Administrator · Server space'),
              softWrap: true,
              maxLines: 3,
              overflow: TextOverflow.visible,
              style: const TextStyle(fontSize: 12, color: Color(0xff647084)),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('dashboard-refresh'),
            tooltip: t('刷新', 'Refresh'),
            onPressed: c.sessionRevoked ? null : c.refresh,
            icon: const Icon(Icons.refresh, color: Color(0xff2166ef)),
          ),
        ],
      ),
      body: SafeArea(
        child: c.sessionRevoked
            ? _permissionLost(colors)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _rangeSelector(),
                  const SizedBox(height: 16),
                  _metrics(),
                  const SizedBox(height: 16),
                  _trendCard(),
                  const SizedBox(height: 16),
                  _logsCard(),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _permissionLost(ColorScheme colors) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: colors.error),
          const SizedBox(height: 12),
          Text(
            t(
              '会话已失效或管理员权限已撤销。',
              'Your session expired or administrator access was revoked.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('dashboard-return'),
            onPressed: widget.onReturn,
            child: Text(t('返回', 'Return')),
          ),
        ],
      ),
    ),
  );

  Widget _rangeSelector() {
    final ranges = <(DashboardRange, String, String)>[
      (DashboardRange.hours24, '24小时', '24 hours'),
      (DashboardRange.days7, '7天', '7 days'),
      (DashboardRange.days30, '30天', '30 days'),
      (DashboardRange.days90, '90天', '90 days'),
    ];
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final entry in ranges)
          ChoiceChip(
            key: ValueKey('range-${entry.$1.queryValue}'),
            label: Text(t(entry.$2, entry.$3)),
            showCheckmark: false,
            selected: c.range == entry.$1,
            selectedColor: const Color(0xff2166ef),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: c.range == entry.$1
                  ? const Color(0xff2166ef)
                  : const Color(0xffcfd6e1),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            labelStyle: TextStyle(
              color: c.range == entry.$1
                  ? Colors.white
                  : const Color(0xff162238),
            ),
            onSelected: (_) => c.changeRange(entry.$1),
          ),
      ],
    );
    final label = Text(
      _rangeLabel,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return Tooltip(
      key: const ValueKey('dashboard-range-semantics'),
      message: t(
        '范围包含服务器起始日全天；UV按日累计，不是整个区间去重。',
        'Ranges include the full server start date; UV is summed daily rather than deduplicated over the period.',
      ),
      child: Semantics(
        container: true,
        label: _rangeLabel,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 340 &&
                MediaQuery.textScalerOf(context).scale(14) <= 18 &&
                !widget.english) {
              return Row(
                children: [
                  label,
                  const SizedBox(width: 12),
                  Expanded(child: chips),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 8), chips],
            );
          },
        ),
      ),
    );
  }

  String _formatCount(int? value) => value == null
      ? ''
      : value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]!},',
        );

  Widget _metrics() => LayoutBuilder(
    builder: (context, constraints) {
      final longest = [
        _formatCount(c.stats.value?.totalVisits).length,
        _formatCount(c.stats.value?.uniqueIps).length,
      ].reduce((a, b) => a > b ? a : b);
      final horizontal =
          constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(14) <= 18 &&
          longest <= 8;
      final a = _metricCard(
        title: t('总访问', 'Total visits'),
        semanticTitle: t('总访问（PV）', 'Total visits (PV)'),
        unit: 'PV',
        value: c.stats.value?.totalVisits,
        section: c.stats,
        retry: c.retryStats,
        retryKey: const ValueKey('dashboard-stats-retry-total'),
        key: const ValueKey('dashboard-stats'),
      );
      final b = _metricCard(
        title: t('每日 UV 累计', 'Daily UV summed'),
        semanticTitle: t('独立 IP（每日 UV 累计）', 'Unique IPs (daily UV summed)'),
        unit: t('按日相加', 'Summed by day'),
        value: c.stats.value?.uniqueIps,
        section: c.stats,
        retry: c.retryStats,
        retryKey: const ValueKey('dashboard-stats-retry-unique'),
        key: const ValueKey('dashboard-unique-ips'),
      );
      if (horizontal) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, const SizedBox(height: 12), b],
      );
    },
  );

  Widget _metricCard({
    required Key key,
    required String title,
    required String semanticTitle,
    required String unit,
    required int? value,
    required DashboardSection<DashboardStats> section,
    required Future<void> Function() retry,
    required Key retryKey,
  }) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Container(
      key: key,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffe5f0ff), Color(0xffedf6ff)],
        ),
        border: Border.all(color: const Color(0xffd2dce8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: switch (section.state) {
        DashboardLoadState.loading || DashboardLoadState.idle => const SizedBox(
          height: 84,
          child: Center(child: CircularProgressIndicator()),
        ),
        DashboardLoadState.failed => _retryRow(
          t('加载失败', 'Load failed'),
          retry,
          buttonKey: retryKey,
        ),
        DashboardLoadState.loaded => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: semanticTitle,
              excludeSemantics: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatCount(value),
              style: const TextStyle(
                fontSize: 34,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: Color(0xff101f38),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unit,
              style: const TextStyle(fontSize: 13, color: Color(0xff647084)),
            ),
          ],
        ),
      },
    ),
  );

  Widget _trendCard() => Card(
    key: const ValueKey('dashboard-trend'),
    margin: EdgeInsets.zero,
    color: Colors.white,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xffd2d9e3)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                t('访问趋势', 'Visit trend'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              );
              final legend = Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _legend(t('访问量', 'Page views'), const Color(0xff2166ef)),
                  _legend(t('日 UV', 'Daily UV'), const Color(0xff2dc2d3)),
                ],
              );
              if (constraints.maxWidth >= 300 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18) {
                return Row(
                  children: [
                    title,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: legend,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 8), legend],
              );
            },
          ),
          const SizedBox(height: 12),
          switch (c.trend.state) {
            DashboardLoadState.loading ||
            DashboardLoadState.idle => const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
            DashboardLoadState.failed => _retryRow(
              t('趋势加载失败', 'Trend failed to load'),
              c.retryTrend,
              buttonKey: const ValueKey('dashboard-trend-retry'),
            ),
            DashboardLoadState.loaded => _trendContent(
              c.trend.value ?? const [],
            ),
          },
        ],
      ),
    ),
  );

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 18, height: 3, color: color),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xff536174)),
        ),
      ),
    ],
  );

  Widget _trendContent(List<DashboardTrendPoint> points) {
    if (points.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(child: Text(t('暂无趋势数据', 'No trend data'))),
      );
    }
    return _TrendReader(points: points, english: widget.english);
  }

  Widget _logsCard() => Column(
    key: const ValueKey('dashboard-logs'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        t('最近访问', 'Recent visits'),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        t(
          '按最近访问时间排序 · 每个 IP 和用户的最近摘要',
          'Sorted by latest visit · latest summary per IP and member',
        ),
        style: const TextStyle(fontSize: 12, color: Color(0xff647084)),
      ),
      const SizedBox(height: 12),
      Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xffd2d9e3)),
        ),
        child: switch (c.logs.state) {
          DashboardLoadState.loading ||
          DashboardLoadState.idle => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          DashboardLoadState.failed => Padding(
            padding: const EdgeInsets.all(16),
            child: _retryRow(
              t('最近访问加载失败', 'Recent visits failed to load'),
              c.retryLogs,
              buttonKey: const ValueKey('dashboard-logs-retry'),
            ),
          ),
          DashboardLoadState.loaded => _logContent(c.logs.value!),
        },
      ),
    ],
  );

  Widget _logContent(DashboardLogPage page) {
    if (page.page > page.totalPages) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              t('此页已超出当前记录范围。', 'This page is outside the current results.'),
              key: const ValueKey('dashboard-logs-page-out-of-range'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('dashboard-logs-first-page'),
              onPressed: () => c.loadLogsPage(1),
              child: Text(t('返回第 1 页', 'Return to page 1')),
            ),
          ],
        ),
      );
    }
    if (page.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(t('暂无访问记录', 'No visit records'))),
      );
    }
    return Column(
      children: [
        for (final row in page.items) _logCard(row),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('dashboard-previous'),
              onPressed: page.page > 1
                  ? () => c.loadLogsPage(page.page - 1)
                  : null,
              child: Text(t('上一页', 'Previous')),
            ),
            Text(
              t(
                '第 ${page.page} / ${page.totalPages} 页',
                'Page ${page.page} of ${page.totalPages}',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff2166ef),
              ),
              key: const ValueKey('dashboard-next'),
              onPressed: page.page < page.totalPages
                  ? () => c.loadLogsPage(page.page + 1)
                  : null,
              child: Text(t('下一页', 'Next')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _logCard(DashboardVisitLog row) {
    final time = row.visitTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${time.year == DateTime.now().year ? '' : '${time.year}/'}${two(time.month)}/${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
    final account = Text(
      row.anonymous ? t('游客', 'Guest') : row.account,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );
    final stamp = Tooltip(
      message: time.toIso8601String(),
      child: Text(
        date,
        style: const TextStyle(fontSize: 12, color: Color(0xff647084)),
      ),
    );
    return Container(
      key: ValueKey('visit-${row.visitId}'),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xffe0e5ed))),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 300 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: account),
                    const SizedBox(width: 12),
                    stamp,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [account, const SizedBox(height: 4), stamp],
              );
            },
          ),
          const SizedBox(height: 4),
          SelectableText(
            row.ip,
            key: ValueKey('visit-ip-${row.visitId}'),
            style: const TextStyle(fontSize: 13, color: Color(0xff647084)),
          ),
          const SizedBox(height: 2),
          SelectableText(
            row.path,
            key: ValueKey('visit-path-${row.visitId}'),
            style: const TextStyle(fontSize: 13, color: Color(0xff647084)),
          ),
        ],
      ),
    );
  }

  Widget _retryRow(
    String message,
    Future<void> Function() retry, {
    required Key buttonKey,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(message),
      const SizedBox(height: 8),
      OutlinedButton(
        key: buttonKey,
        onPressed: () => retry(),
        child: Text(t('重试', 'Retry')),
      ),
    ],
  );
}

class _TrendReader extends StatefulWidget {
  const _TrendReader({required this.points, required this.english});
  final List<DashboardTrendPoint> points;
  final bool english;

  @override
  State<_TrendReader> createState() => _TrendReaderState();
}

class _TrendReaderState extends State<_TrendReader> {
  String? _selected;

  @override
  void didUpdateWidget(covariant _TrendReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.points.any((point) => point.bucketLabel == _selected)) {
      _selected = widget.points.isEmpty ? null : widget.points.last.bucketLabel;
    }
  }

  String t(String zh, String en) => widget.english ? en : zh;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    _selected ??= points.last.bucketLabel;
    final selected = points.firstWhere(
      (point) => point.bucketLabel == _selected,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: t(
            '访问趋势折线图，蓝色为访问量，青色为每日独立 IP。',
            'Visit trend chart. Blue is page views; teal is daily unique IPs.',
          ),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: DashboardTrendPainter(points),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('dashboard-daily-detail-toggle'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          backgroundColor: const Color(0xffeef6ff),
          collapsedBackgroundColor: const Color(0xffeef6ff),
          title: Text(
            t('按日汇总', 'Daily totals'),
            style: const TextStyle(fontSize: 13, color: Color(0xff647084)),
          ),
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const ValueKey('trend-day-reader'),
              initialValue: _selected,
              decoration: InputDecoration(
                labelText: t('逐日查看数据', 'Read daily values'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final point in points)
                  DropdownMenuItem(
                    value: point.bucketLabel,
                    child: Text(point.bucketLabel),
                  ),
              ],
              onChanged: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              label:
                  '${selected.bucketLabel}: ${selected.pageViews} PV, ${selected.uniqueIps} daily UV',
              child: Text(
                '${selected.bucketLabel} · ${selected.pageViews} PV · ${selected.uniqueIps} UV',
                key: const ValueKey('trend-selected-values'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A common numeric axis keeps the relative magnitude of PV and UV truthful.
class DashboardTrendPainter extends CustomPainter {
  DashboardTrendPainter(this.points) : _scale = _axis(points);
  final List<DashboardTrendPoint> points;
  final ({int maximum, int step}) _scale;
  int get maximum => _scale.maximum;
  static ({int maximum, int step}) _axis(List<DashboardTrendPoint> points) {
    var result = 1;
    for (final point in points) {
      if (point.pageViews > result) result = point.pageViews;
      if (point.uniqueIps > result) result = point.uniqueIps;
    }
    var unit = 1;
    while (unit * 10 <= result / 5) {
      unit *= 10;
    }
    final normalized = result / (5 * unit);
    final factor = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 5
        ? 5
        : 10;
    final step = unit * factor;
    return (maximum: ((result + step - 1) ~/ step) * step, step: step);
  }

  Offset pointOffset(Rect rect, int index, int value) => Offset(
    points.length <= 1
        ? rect.center.dx
        : rect.left + rect.width * index / (points.length - 1),
    rect.bottom - rect.height * value.clamp(0, maximum) / maximum,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 100 || size.height < 80) return;
    final label = _text(maximum.toString())..layout();
    final left = (label.width + 10).clamp(32.0, size.width / 3);
    final rect = Rect.fromLTRB(left, 16, size.width - 8, size.height - 30);
    final grid = Paint()
      ..color = const Color(0xffd7dde5)
      ..strokeWidth = 1;
    final intervals = maximum ~/ _scale.step;
    for (var i = 0; i <= intervals; i++) {
      final value = maximum - i * _scale.step;
      final y = rect.top + rect.height * i / intervals;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      final tick = _text(value.toString())..layout(maxWidth: left - 6);
      tick.paint(
        canvas,
        Offset(rect.left - tick.width - 6, y - tick.height / 2),
      );
    }
    _drawLine(
      canvas,
      rect,
      points.map((p) => p.pageViews).toList(),
      const Color(0xff2166ef),
    );
    _drawLine(
      canvas,
      rect,
      points.map((p) => p.uniqueIps).toList(),
      const Color(0xff2dc2d3),
    );
    final step = points.length <= 7 ? 1 : (points.length / 6).ceil();
    for (var i = 0; i < points.length; i++) {
      if (i % step != 0 && i != points.length - 1) continue;
      final raw = points[i].bucketLabel;
      final text = raw.length >= 10
          ? raw.substring(5, 10).replaceAll('-', '/')
          : raw;
      final tick = _text(text)..layout(maxWidth: rect.width / 3);
      final x = pointOffset(rect, i, 0).dx;
      tick.paint(
        canvas,
        Offset(
          (x - tick.width / 2).clamp(0.0, size.width - tick.width),
          rect.bottom + 8,
        ),
      );
    }
  }

  void _drawLine(Canvas canvas, Rect rect, List<int> values, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final offset = pointOffset(rect, i, values[i]);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(path, paint);
    for (var i = 0; i < values.length; i++) {
      final offset = pointOffset(rect, i, values[i]);
      canvas.drawCircle(offset, 3, Paint()..color = Colors.white);
      canvas.drawCircle(
        offset,
        3,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  TextPainter _text(String value) => TextPainter(
    text: TextSpan(
      text: value,
      style: const TextStyle(fontSize: 10, color: Color(0xff657183)),
    ),
    textDirection: TextDirection.ltr,
  );
  @override
  bool shouldRepaint(covariant DashboardTrendPainter oldDelegate) =>
      !identical(oldDelegate.points, points);
}
