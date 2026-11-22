import 'package:flutter/material.dart';
import '../core/tasks_repository.dart';

class MonthActivityGrid extends StatelessWidget {
  const MonthActivityGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.counts,
    required this.countLabel,
    this.dayKeyPrefix = 'activity-day',
    this.minimumYear = 1,
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
  final Map<String, int> counts;
  final String Function(int count) countLabel;
  final String dayKeyPrefix;
  final int minimumYear;
  final ValueChanged<DateTime> onDay;
  final VoidCallback onPrevious, onNext;
  final bool english, loading, countsUnavailable, enabled;
  String t(String zh, String en) => english ? en : zh;
  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = DateTime(month.year, month.month).weekday - 1;
    final dayCounts = counts;
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed:
                      !enabled ||
                          (month.year == minimumYear && month.month == 1)
                      ? null
                      : onPrevious,
                  tooltip: t('上个月', 'Previous month'),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      !enabled || (month.year == 9999 && month.month == 12)
                      ? null
                      : onNext,
                  tooltip: t('下个月', 'Next month'),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final day
                    in english
                        ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                        : ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = constraints.maxWidth / 7;
                final desiredCircle = scale.scale(14) * 1.8;
                final maxCircle = (cellWidth - 4)
                    .clamp(0, double.infinity)
                    .toDouble();
                final circle = (desiredCircle < 32 ? 32.0 : desiredCircle)
                    .clamp(0, maxCircle)
                    .toDouble();
                final cellHeight = (circle + scale.scale(11) + 4)
                    .clamp(48, double.infinity)
                    .toDouble();
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  childAspectRatio: cellWidth / cellHeight,
                  children: [
                    for (var index = 0; index < 42; index++)
                      if (index < offset || index >= offset + days)
                        const SizedBox.shrink()
                      else
                        Builder(
                          builder: (context) {
                            final date = DateTime(
                              month.year,
                              month.month,
                              index - offset + 1,
                            );
                            final value = taskDate(date);
                            final count = dayCounts[value];
                            final active = value == selected;
                            return Semantics(
                              button: true,
                              excludeSemantics: true,
                              onTap: enabled ? () => onDay(date) : null,
                              selected: active,
                              label:
                                  '${MaterialLocalizations.of(context).formatFullDate(date)}, ${countsUnavailable
                                      ? t('计数不可用', 'Counts unavailable')
                                      : loading
                                      ? t('计数加载中', 'counts loading')
                                      : countLabel(count ?? 0)}',
                              child: InkWell(
                                key: Key('$dayKeyPrefix:$value'),
                                onTap: enabled ? () => onDay(date) : null,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: circle,
                                      height: circle,
                                      alignment: Alignment.center,
                                      decoration: active
                                          ? BoxDecoration(
                                              color: theme.colorScheme.primary,
                                              shape: BoxShape.circle,
                                            )
                                          : null,
                                      child: Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: active
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: scale.scale(11) + 4,
                                      child:
                                          !loading &&
                                              !countsUnavailable &&
                                              count != null &&
                                              count > 0
                                          ? Text(
                                              count > 99 ? '99+' : '$count',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
