import 'package:flutter/material.dart';
import '../../core/tasks_repository.dart';
import '../../widgets/month_activity_grid.dart';

/// Keep task-specific labels and keys while sharing the native month layout.
class TaskMonthGrid extends StatelessWidget {
  const TaskMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.counts,
    required this.onDay,
    required this.onPrevious,
    required this.onNext,
    this.english = false,
    this.loading = false,
    this.countsUnavailable = false,
    this.enabled = true,
  });
  final DateTime month;
  final String selected;
  final List<TaskDailyCount> counts;
  final ValueChanged<DateTime> onDay;
  final VoidCallback onPrevious, onNext;
  final bool english, loading, countsUnavailable, enabled;
  @override
  Widget build(BuildContext context) => MonthActivityGrid(
    month: month,
    selected: selected,
    counts: {for (final count in counts) count.date: count.total},
    countLabel: (count) => english ? '$count modified tasks' : '修改$count条',
    dayKeyPrefix: 'task-day',
    onDay: onDay,
    onPrevious: onPrevious,
    onNext: onNext,
    english: english,
    loading: loading,
    countsUnavailable: countsUnavailable,
    enabled: enabled,
  );
}
