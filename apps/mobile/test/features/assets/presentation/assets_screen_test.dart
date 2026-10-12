import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/assets/assets_providers.dart';
import 'package:cashdeck/features/assets/data/fake_assets_repository.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/assets/presentation/asset_editor.dart';
import 'package:cashdeck/features/assets/presentation/assets_screen.dart';
import 'package:cashdeck/features/assets/presentation/vehicle_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../application/assets_use_cases_test.dart' show MockAssetsRepository;
import '../asset_builders.dart';

const double _height = 2400;

Future<void> _type(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _act(WidgetTester tester, String id, Key action) async {
  await _tap(tester, find.byKey(AssetsScreen.menuKey(id)));
  await _tap(tester, find.byKey(action));
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Money(0));
    registerFallbackValue(
      AssetDraft(kind: AssetKind.other, acquiredOn: testAsset.acquiredOn),
    );
  });

  testWidgets('shows each good with its loan and the totals', (tester) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);

    expect(find.byKey(AssetsScreen.cardKey('asset-home')), findsOneWidget);
    expect(find.byKey(AssetsScreen.cardKey('asset-car')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AssetsScreen.totalKey),
        matching: find.text(MoneyFormat.format(const Money(70_950_000))),
      ),
      findsOneWidget,
    );
    expect(find.text('Banco Exemplo 1001'), findsOneWidget);
    expect(find.text(l10n.assetsEquity), findsWidgets);
    expect(find.textContaining('12.7%'), findsOneWidget);
    expect(find.textContaining('Tabela FIPE'), findsOneWidget);
  });

  testWidgets('adds a property bought with a loan', (tester) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);
    await _tap(tester, find.byKey(AssetsScreen.addKey));

    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetNameMissing), findsOneWidget);
    await _type(tester, AssetEditor.nameKey, 'Apartamento alugado');
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetValueMissing), findsOneWidget);

    await _type(tester, AssetEditor.valueKey, '45000000');
    await _tap(tester, find.byKey(AssetEditor.acquiredKey));
    await _tap(tester, find.text('Cancelar'));
    await _tap(tester, find.byKey(AssetEditor.acquiredKey));
    await _tap(tester, find.text('OK'));
    await _tap(tester, find.byKey(AssetEditor.loanKey));
    await _tap(tester, find.text('Banco Exemplo 1001').last);
    await _tap(tester, find.byKey(AssetEditor.saveKey));

    expect(find.text(l10n.assetAdded), findsOneWidget);
    expect(find.text('Apartamento alugado'), findsOneWidget);
  });

  testWidgets('adds a vehicle picked by brand, year and model', (tester) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);
    await _tap(tester, find.byKey(AssetsScreen.addKey));
    await _tap(tester, find.text(l10n.assetKindVehicle));
    expect(find.byKey(AssetEditor.valueKey), findsNothing);
    expect(find.text(l10n.assetNameOptional), findsOneWidget);

    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetVehicleMissing), findsOneWidget);
    await _tap(tester, find.byKey(AssetEditor.modelYearKey));
    expect(find.byKey(VehicleOptionsSheet.searchKey), findsNothing);

    await _tap(tester, find.text(l10n.vehicleMotorcycle));
    await _tap(tester, find.byKey(AssetEditor.brandKey));
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await _tap(tester, find.byKey(AssetEditor.brandKey));
    await _type(tester, VehicleOptionsSheet.searchKey, 'zzz');
    expect(find.text(l10n.vehicleNoMatch), findsOneWidget);
    await _type(tester, VehicleOptionsSheet.searchKey, 'outra');
    expect(find.byKey(VehicleOptionsSheet.optionKey('1')), findsNothing);
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('2')));
    expect(find.text('Outra Marca'), findsOneWidget);

    await _tap(tester, find.byKey(AssetEditor.modelYearKey));
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await _tap(tester, find.byKey(AssetEditor.modelYearKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('2026')));
    await _tap(tester, find.byKey(AssetEditor.modelKey));
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await _tap(tester, find.byKey(AssetEditor.modelKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('10')));
    expect(find.textContaining('001210-5'), findsOneWidget);

    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text('FIPE 001210-5'), findsOneWidget);
    expect(find.text(MoneyFormat.format(fakeFipePrice)), findsWidgets);
  });

  testWidgets('a vehicle can be valued by hand instead', (tester) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);
    await _tap(tester, find.byKey(AssetsScreen.addKey));
    await _tap(tester, find.text(l10n.assetKindVehicle));
    await _tap(tester, find.byKey(AssetEditor.fipeKey));
    expect(find.byKey(AssetEditor.brandKey), findsNothing);

    await _type(tester, AssetEditor.nameKey, 'Moto antiga');
    await _type(tester, AssetEditor.valueKey, '1500000');
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text('Moto antiga'), findsOneWidget);
  });

  testWidgets('revalues, marks sold and deletes', (tester) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);

    await _act(tester, 'asset-home', AssetsScreen.revalueKey);
    await _type(tester, AssetsScreen.revalueAmountKey, '0');
    await _tap(tester, find.byKey(AssetsScreen.revalueSaveKey));
    expect(find.byKey(AssetsScreen.revalueAmountKey), findsOneWidget);
    await _type(tester, AssetsScreen.revalueAmountKey, '65000000');
    await _tap(tester, find.byKey(AssetsScreen.revalueSaveKey));
    expect(find.text(l10n.assetRevalued), findsOneWidget);
    expect(
      find.text(MoneyFormat.format(const Money(65_000_000))),
      findsWidgets,
    );

    await _act(tester, 'asset-car', AssetsScreen.soldKey);
    await _tap(tester, find.text(l10n.cancelButton));
    await _act(tester, 'asset-car', AssetsScreen.soldKey);
    await _tap(tester, find.byKey(AssetsScreen.confirmKey));
    expect(find.text(l10n.assetMarkedSold), findsOneWidget);
    expect(find.textContaining('Vendido em'), findsOneWidget);

    await _tap(tester, find.byKey(AssetsScreen.menuKey('asset-car')));
    expect(find.byKey(AssetsScreen.revalueKey), findsNothing);
    await _tap(tester, find.byKey(AssetsScreen.deleteKey));
    await _tap(tester, find.byKey(AssetsScreen.confirmKey));
    await _act(tester, 'asset-home', AssetsScreen.deleteKey);
    await _tap(tester, find.text(l10n.cancelButton));
    await _act(tester, 'asset-home', AssetsScreen.deleteKey);
    await _tap(tester, find.byKey(AssetsScreen.confirmKey));

    expect(find.text(l10n.assetDeleted), findsOneWidget);
    expect(find.text(l10n.assetsEmptyTitle), findsOneWidget);
    await _tap(tester, find.text(l10n.assetAdd).last);
    expect(find.byKey(AssetEditor.saveKey), findsOneWidget);
  });

  testWidgets('a failed load retries and a refused good says why', (
    tester,
  ) async {
    final repository = MockAssetsRepository();
    when(repository.list).thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.create(any())).thenAnswer(
      (_) async => const Err(ValidationFailure('FIPE vehicle not found')),
    );
    await pumpRoute(
      tester,
      AppRoutes.assets,
      screenHeight: _height,
      overrides: [assetsRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.byType(CdErrorState), findsOneWidget);
    await _tap(tester, find.byKey(CdErrorState.retryKey));
    verify(repository.list).called(2);

    when(repository.list).thenAnswer((_) async => Ok(summaryOf([testAsset])));
    await _tap(tester, find.byKey(CdErrorState.retryKey));
    var brandsFail = true;
    when(() => repository.brands(VehicleType.car)).thenAnswer(
      (_) async => brandsFail
          ? const Err(NetworkFailure())
          : const Ok([VehicleOption(code: '1', name: 'Marca Exemplo')]),
    );
    when(() => repository.years(VehicleType.car, '1')).thenAnswer(
      (_) async => const Ok([VehicleOption(code: '2022', name: '2022')]),
    );
    when(() => repository.models(VehicleType.car, '1', 2022))
        .thenAnswer((_) async => const Ok([testModel]));
    var priceFails = true;
    when(() => repository.price(VehicleType.car, '1', testModel)).thenAnswer(
      (_) async => priceFails
          ? const Err(NotFoundFailure())
          : const Ok(testCatalogVehicle),
    );

    await _tap(tester, find.byKey(AssetsScreen.addKey));
    await _tap(tester, find.text(l10n.assetKindVehicle));
    await _tap(tester, find.byKey(AssetEditor.brandKey));
    brandsFail = false;
    await _tap(tester, find.byKey(VehicleOptionsSheet.retryKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('1')));
    await _tap(tester, find.byKey(AssetEditor.modelYearKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('2022')));
    await _tap(tester, find.byKey(AssetEditor.modelKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('10')));
    expect(find.byKey(AssetEditor.errorKey), findsOneWidget);
    expect(find.byKey(AssetEditor.previewKey), findsNothing);

    priceFails = false;
    await _tap(tester, find.byKey(AssetEditor.modelKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('10')));
    expect(find.byKey(AssetEditor.previewKey), findsOneWidget);
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text('FIPE vehicle not found'), findsOneWidget);
  });
}
