import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';

/// The recap of a month that closed; one still open or malformed never
/// reaches the server.
final class GetMonthlyRecap {
  const new(this._repository);

  final RecapRepository _repository;

  Future<Result<MonthlyRecap>> call(
    String month, {
    required CalendarDate today,
    required String locale,
  }) {
    final parsed = _parse(month);
    if (parsed == null || parsed.compareTo(lastClosedMonth(today)) > 0) {
      return Future.value(const Err(NotFoundFailure()));
    }
    return _repository.get(parsed, locale: locale);
  }

  YearMonth? _parse(String month) {
    try {
      return YearMonth.parse(month);
    } on FormatException {
      return null;
    }
  }
}
