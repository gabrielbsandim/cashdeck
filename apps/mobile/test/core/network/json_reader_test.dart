import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = <String, dynamic>{
    'text': 'a',
    'number': 3,
    'map': <String, dynamic>{'k': 1},
    'maps': [
      <String, dynamic>{'k': 1},
    ],
    'strings': ['a', 'b'],
    'date': '2026-10-08',
    'at': '2026-10-08T12:00:00Z',
    'badAt': 'later',
    'null': null,
  };
  final throwsFormat = throwsA(isA<FormatException>());

  test('reads each type', () {
    expect(readString(json, 'text'), 'a');
    expect(readOptionalString(json, 'text'), 'a');
    expect(readOptionalString(json, 'null'), isNull);
    expect(readInt(json, 'number'), 3);
    expect(readMap(json, 'map'), {'k': 1});
    expect(readMapList(json, 'maps'), hasLength(1));
    expect(readMapList(json, 'missing'), isEmpty);
    expect(readStringList(json, 'strings'), ['a', 'b']);
    expect(readStringList(json, 'missing'), isEmpty);
    expect(readDate(json, 'date'), const CalendarDate(2026, 10, 8));
    expect(readDateTime(json, 'at'), DateTime.utc(2026, 10, 8, 12));
  });

  test('rejects the wrong shape', () {
    expect(() => readString(json, 'number'), throwsFormat);
    expect(() => readOptionalString(json, 'number'), throwsFormat);
    expect(() => readInt(json, 'text'), throwsFormat);
    expect(() => readMap(json, 'text'), throwsFormat);
    expect(() => readMapList(json, 'strings'), throwsFormat);
    expect(() => readStringList(json, 'maps'), throwsFormat);
    expect(() => readDateTime(json, 'badAt'), throwsFormat);
  });

  test('unwraps the data envelope', () {
    expect(unwrapData({'data': 1}), 1);
    expect(() => unwrapData({'other': 1}), throwsFormat);
    expect(() => unwrapData('text'), throwsFormat);
    expect(asJsonMap(<String, dynamic>{'a': 1}), {'a': 1});
    expect(() => asJsonMap(1), throwsFormat);
    expect(asJsonMapList([<String, dynamic>{}]), hasLength(1));
    expect(() => asJsonMapList([1]), throwsFormat);
  });
}
