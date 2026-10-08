import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const day = CalendarDate(2026, 3, 9);

  test('formats and parses', () {
    expect(day.iso, '2026-03-09');
    expect(day.dayMonth, '09/03');
    expect(day.display, '09/03/2026');
    expect(day.toString(), '2026-03-09');
    expect(CalendarDate.parse('2026-03-09'), day);
    expect(() => CalendarDate.parse('2026/03/09'), throwsFormatException);
  });

  test('does calendar arithmetic', () {
    expect(day.addDays(-9), const CalendarDate(2026, 2, 28));
    expect(day.daysUntil(day.addDays(3)), 3);
    expect(day.isBefore(day.addDays(1)), isTrue);
    expect(day.isBefore(day), isFalse);
  });

  test('today and the time of day follow Brazil', () {
    final lateUtc = DateTime.utc(2026, 3, 10, 1, 30);

    expect(CalendarDate.brazilToday(lateUtc), day);
    expect(brazilTime(lateUtc), '22:30');
  });

  test('clocks', () {
    final fixed = FixedClock(DateTime.utc(2026));

    expect(fixed.now(), DateTime.utc(2026));
    expect(const SystemClock().now(), isA<DateTime>());
  });
}
