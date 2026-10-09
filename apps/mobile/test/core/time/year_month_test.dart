import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses, prints and steps across years', () {
    final october = YearMonth.parse('2026-10');
    expect(october.iso, '2026-10');
    expect(october.toString(), '2026-10');
    expect(october.add(3), const YearMonth(2027, 1));
    expect(october.add(-10), const YearMonth(2025, 12));
    expect(october.firstDay, const CalendarDate(2026, 10, 1));
    expect(october.dayCount, 31);
    expect(const YearMonth(2028, 2).dayCount, 29);
    expect(YearMonth.of(const CalendarDate(2026, 10, 8)), october);
    expect(october.contains(const CalendarDate(2026, 10, 31)), isTrue);
    expect(october.contains(const CalendarDate(2026, 11, 1)), isFalse);
    expect(october.compareTo(october.add(1)), lessThan(0));
  });

  test('rejects anything but YYYY-MM', () {
    expect(() => YearMonth.parse('2026-13'), throwsFormatException);
    expect(() => YearMonth.parse('2026-1'), throwsFormatException);
    expect(() => YearMonth.parse('2026-00'), throwsFormatException);
  });
}
