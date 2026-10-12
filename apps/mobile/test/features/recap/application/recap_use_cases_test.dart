import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/recap/application/recap_use_cases.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../recap_builders.dart';

final class MockRecapRepository extends Mock implements RecapRepository;

const _today = CalendarDate(2026, 10, 8);

void main() {
  late MockRecapRepository repository;
  late GetMonthlyRecap getRecap;

  setUpAll(() {
    registerFallbackValue(const YearMonth(2026, 1));
    registerFallbackValue(EntityKind.personal);
  });

  setUp(() {
    repository = MockRecapRepository();
    getRecap = GetMonthlyRecap(repository);
  });

  test('asks for a closed month of an entity in the given language', () async {
    final recap = plainRecap();
    when(
      () => repository.get(
        const YearMonth(2026, 9),
        locale: 'en',
        entity: EntityKind.personal,
      ),
    ).thenAnswer((_) async => Ok(recap));
    when(
      () => repository.get(
        const YearMonth(2026, 9),
        locale: 'pt',
        entity: EntityKind.company,
      ),
    ).thenAnswer((_) async => Ok(recap));

    expect(await getRecap('2026-09', today: _today, locale: 'en'), Ok(recap));
    expect(
      await getRecap(
        '2026-09',
        today: _today,
        locale: 'pt',
        entity: EntityKind.company,
      ),
      Ok(recap),
    );
  });

  test('never asks for an open or malformed month', () async {
    for (final month in ['2026-10', '2026-13', 'setembro']) {
      expect(
        await getRecap(month, today: _today, locale: 'pt'),
        const Err<MonthlyRecap>(NotFoundFailure()),
      );
    }
    verifyNever(
      () => repository.get(
        any(),
        locale: any(named: 'locale'),
        entity: any(named: 'entity'),
      ),
    );
  });
}
