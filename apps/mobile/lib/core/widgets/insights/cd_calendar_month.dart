import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:flutter/material.dart';

/// A month in seven columns from Sunday, up to three status dots per day.
/// Today has a ring; the selected day a filled primary circle.
class CdCalendarMonth extends StatelessWidget {
  const new({
    required this.month,
    required this.weekdays,
    required this.today,
    this.dots = const {},
    this.selected,
    this.onSelect,
    super.key,
  });

  static Key dayKey(int day) => Key('cd-calendar-day-$day');

  final YearMonth month;

  /// Seven initials from Sunday, such as `D S T Q Q S S`.
  final List<String> weekdays;
  final CalendarDate today;
  final Map<int, List<Color>> dots;
  final CalendarDate? selected;
  final ValueChanged<CalendarDate>? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lead = DateTime.utc(month.year, month.month).weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 1; day <= month.dayCount; day++) _day(context, day),
    ];
    final rows = <Widget>[];
    for (var start = 0; start < cells.length; start += 7) {
      final week = cells.sublist(
        start,
        start + 7 > cells.length ? cells.length : start + 7,
      );
      rows.add(
        Row(
          children: [
            for (final cell in week) Expanded(child: cell),
            for (var i = week.length; i < 7; i++) const Spacer(),
          ],
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            for (final weekday in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...rows,
      ],
    );
  }

  Widget _day(BuildContext context, int day) {
    final palette = context.palette;
    final date = CalendarDate(month.year, month.month, day);
    final isToday = date == today;
    final isSelected = date == selected;
    final marks = (dots[day] ?? const <Color>[]).take(3).toList();
    final background = isSelected ? palette.primary : Colors.transparent;
    final foreground = isSelected ? palette.onPrimary : palette.onSurface;
    return Semantics(
      button: onSelect != null,
      selected: isSelected,
      label: '$day',
      excludeSemantics: true,
      child: InkWell(
        key: dayKey(day),
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onSelect == null ? null : () => onSelect!(date),
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: isToday && !isSelected
                      ? Border.all(color: palette.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '$day',
                  style: AppTextStyles.bodyMd.copyWith(
                    fontWeight: isToday || isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (index, color) in marks.indexed) ...[
                      if (index > 0) const SizedBox(width: 2),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
