import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// A calendar month, as the API writes it: `2026-10`.
final class YearMonth extends Equatable implements Comparable<YearMonth> {
  const new(this.year, this.month);

  factory of(CalendarDate date) => YearMonth(date.year, date.month);

  factory parse(String iso) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(iso);
    final month = int.tryParse(match?.group(2) ?? '') ?? 0;
    if (match == null || month < 1 || month > 12) {
      throw FormatException('Expected YYYY-MM', iso);
    }
    return YearMonth(int.parse(match.group(1)!), month);
  }

  final int year;
  final int month;

  String get iso => '$year-${month.toString().padLeft(2, '0')}';

  YearMonth add(int months) {
    final index = year * 12 + month - 1 + months;
    return YearMonth(index ~/ 12, index % 12 + 1);
  }

  CalendarDate get firstDay => CalendarDate(year, month, 1);

  int get dayCount => DateTime.utc(year, month + 1, 0).day;

  bool contains(CalendarDate date) => date.year == year && date.month == month;

  @override
  int compareTo(YearMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  List<Object?> get props => [year, month];

  @override
  String toString() => iso;
}
