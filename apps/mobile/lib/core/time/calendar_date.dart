import 'package:equatable/equatable.dart';

/// A day on the calendar, with no time and no timezone. Travels as YYYY-MM-DD.
final class CalendarDate extends Equatable implements Comparable<CalendarDate> {
  const new(this.year, this.month, this.day);

  factory fromDateTime(DateTime value) =>
      CalendarDate(value.year, value.month, value.day);

  /// Due dates are computed in America/Sao_Paulo, which has no DST since
  /// 2019, so a fixed UTC-3 offset matches the server.
  factory brazilToday(DateTime now) =>
      CalendarDate.fromDateTime(now.toUtc().subtract(const Duration(hours: 3)));

  factory parse(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) throw FormatException('Invalid date', iso);
    return CalendarDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  String get iso => '$year-${_two(month)}-${_two(day)}';

  /// dd/MM, the way a due date reads in a list.
  String get dayMonth => '${_two(day)}/${_two(month)}';

  /// dd/MM/yyyy.
  String get display => '$dayMonth/$year';

  CalendarDate addDays(int days) =>
      CalendarDate.fromDateTime(_utc.add(Duration(days: days)));

  int daysUntil(CalendarDate other) => other._utc.difference(_utc).inDays;

  bool isBefore(CalendarDate other) => compareTo(other) < 0;

  @override
  int compareTo(CalendarDate other) => _utc.compareTo(other._utc);

  @override
  List<Object?> get props => [year, month, day];

  @override
  String toString() => iso;

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// HH:mm of a moment, read in Brazil time like [CalendarDate.brazilToday].
String brazilTime(DateTime moment) {
  final local = moment.toUtc().subtract(const Duration(hours: 3));
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
