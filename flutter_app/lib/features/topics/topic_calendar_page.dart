import 'package:flutter/material.dart';
import '../../core/topics_repository.dart';
import '../../core/tasks_repository.dart';
import '../../widgets/month_activity_grid.dart';

class TopicCalendarPage extends StatefulWidget {
  const TopicCalendarPage({
    super.key,
    required this.repository,
    this.selectedDate = '',
    this.english = false,
    this.clock,
  });
  final TopicsRepository repository;
  final String selectedDate;
  final bool english;
  final DateTime Function()? clock;
  @override
  State<TopicCalendarPage> createState() => _TopicCalendarPageState();
}

class _TopicCalendarPageState extends State<TopicCalendarPage> {
  late DateTime _month;
  late String _selected;
  List<TopicDailyCount> _counts = [];
  bool _loading = true;
  String? _error;
  int _generation = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    final selected = validTaskDate(widget.selectedDate)
        ? DateTime.parse(widget.selectedDate)
        : (widget.clock ?? DateTime.now)();
    final initial = selected.year < 1970
        ? DateTime(1970)
        : selected.year > 9999
        ? DateTime(9999, 12, 31)
        : selected;
    _month = DateTime(initial.year, initial.month);
    _selected = taskDate(initial);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final month = _month;
    setState(() {
      _loading = true;
      _error = null;
      _counts = [];
    });
    try {
      final counts = await widget.repository.dailyCounts(
        month.year,
        month.month,
      );
      if (counts.any(
            (day) => !day.date.startsWith(
              '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-',
            ),
          ) ||
          counts.map((day) => day.date).toSet().length != counts.length) {
        throw const FormatException('Invalid calendar month response');
      }
      if (mounted && generation == _generation) {
        setState(() => _counts = counts);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    if (next.year < 1970 || next.year > 9999) return;
    _month = next;
    _selected = taskDate(next);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TopicDailyCount? selected;
    for (final day in _counts) {
      if (day.date == _selected) selected = day;
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('主题日历', 'Topic calendar'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MonthActivityGrid(
              month: _month,
              selected: _selected,
              counts: {for (final day in _counts) day.date: day.total},
              countLabel: (count) => t('$count项活动', '$count activities'),
              dayKeyPrefix: 'topic-day',
              minimumYear: 1970,
              onDay: (date) => setState(() => _selected = taskDate(date)),
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
              english: widget.english,
              loading: _loading,
              countsUnavailable: _error != null,
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              t('按修改与新增活动统计。', 'Counts modifications and newly added items.'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _load,
                child: Text(t('重试活动计数', 'Retry activity counts')),
              ),
            ] else if (!_loading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t(
                          '$_selected · ${selected?.total ?? 0}项活动',
                          '$_selected · ${selected?.total ?? 0} activities',
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            label: Text(
                              t(
                                '主题${selected?.topics ?? 0}',
                                '${selected?.topics ?? 0} topics',
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              t(
                                '小结${selected?.summaries ?? 0}',
                                '${selected?.summaries ?? 0} summaries',
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              t(
                                '资料${selected?.resources ?? 0}',
                                '${selected?.resources ?? 0} resources',
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              t(
                                '任务${selected?.tasks ?? 0}',
                                '${selected?.tasks ?? 0} tasks',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () => Navigator.pop(context, _selected),
              child: Text(t('筛选此日期', 'Filter by this date')),
            ),
          ],
        ),
      ),
    );
  }
}
