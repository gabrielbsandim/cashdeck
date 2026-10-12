import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/assets/application/assets_use_cases.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../asset_builders.dart';

final class MockAssetsRepository extends Mock implements AssetsRepository;

const _home = AssetDraft(
  kind: AssetKind.property,
  name: 'Apartamento',
  acquiredOn: CalendarDate(2025, 6, 10),
  value: Money(50_000_000),
);

void main() {
  late MockAssetsRepository repository;
  final clock = FixedClock(testNow);

  setUpAll(() {
    registerFallbackValue(const Money(0));
    registerFallbackValue(_home);
    registerFallbackValue(const CalendarDate(2026, 1, 1));
  });

  setUp(() => repository = MockAssetsRepository());

  test('each use case forwards to the repository', () async {
    when(repository.list).thenAnswer((_) async => Ok(summaryOf([testAsset])));
    when(() => repository.create(_home))
        .thenAnswer((_) async => const Ok(testAsset));
    when(() => repository.revalue('asset-1', const Money(1)))
        .thenAnswer((_) async => const Ok(testAsset));
    when(() => repository.markSold('asset-1', const CalendarDate(2026, 10, 8)))
        .thenAnswer((_) async => const Ok(testAsset));
    when(() => repository.delete('asset-1'))
        .thenAnswer((_) async => const Ok(null));

    expect(await ListAssets(repository)(), isA<Ok<AssetsSummary>>());
    expect(await CreateAsset(repository, clock)(_home), const Ok(testAsset));
    expect(
      await RevalueAsset(repository)('asset-1', const Money(1)),
      const Ok(testAsset),
    );
    expect(
      await MarkAssetSold(repository, clock)('asset-1'),
      const Ok(testAsset),
    );
    expect(await DeleteAsset(repository)('asset-1'), isA<Ok<void>>());
  });

  test(
    'a draft with a problem or a value of zero never reaches the server',
    () async {
      final unnamed = await CreateAsset(repository, clock)(
        const AssetDraft(
          kind: AssetKind.property,
          acquiredOn: CalendarDate(2025, 6, 10),
          value: Money(1),
        ),
      );
      expect((unnamed as Err).failure, const UnexpectedFailure());
      final zero = await RevalueAsset(repository)('asset-1', const Money(0));
      expect((zero as Err).failure, const UnexpectedFailure());
      verifyNever(() => repository.create(any()));
      verifyNever(() => repository.revalue(any(), any()));
    },
  );
}
