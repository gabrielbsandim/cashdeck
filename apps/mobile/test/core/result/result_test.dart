import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('results compare by value', () {
    expect(const Ok(1), const Ok(1));
    expect(const Err<int>(ServerFailure()), const Err<int>(ServerFailure()));
    expect(const Ok(1), isNot(const Ok(2)));
  });
}
