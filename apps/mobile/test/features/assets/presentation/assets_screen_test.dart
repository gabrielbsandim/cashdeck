import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
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

  testWidgets('edits a car to another model and renames the home', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);

    await _act(tester, 'asset-car', AssetsScreen.editKey);
    expect(find.byKey(AssetEditor.kindKey), findsNothing);
    expect(find.text('Modelo atual: FIPE 001234-5'), findsOneWidget);
    await _tap(tester, find.byKey(AssetEditor.brandKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('1')));
    await _tap(tester, find.byKey(AssetEditor.modelYearKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('2026')));
    await _tap(tester, find.byKey(AssetEditor.modelKey));
    await _tap(tester, find.byKey(VehicleOptionsSheet.optionKey('11')));
    expect(find.byKey(AssetEditor.currentKey), findsNothing);
    expect(find.text('Sedan Exemplo 2.0 Turbo'), findsWidgets);
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetEdited), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AssetsScreen.cardKey('asset-car')),
        matching: find.text('Sedan Exemplo 2.0 Turbo'),
      ),
      findsOneWidget,
    );

    await _act(tester, 'asset-home', AssetsScreen.editKey);
    await _type(tester, AssetEditor.nameKey, 'Casa');
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Banco Exemplo 1001'), findsOneWidget);
  });

  testWidgets('sends the tenant the charge with the building bill', (
    tester,
  ) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.assets,
      screenHeight: _height,
    );
    final sharer = app.read(fileSharerProvider) as FakeFileSharer;

    expect(find.text('Consumo de gás'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AssetsScreen.rentTotalKey),
        matching: find.text(MoneyFormat.format(const Money(169_870))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AssetsScreen.rentResultKey),
        matching: find.text(MoneyFormat.format(const Money(3_429))),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.rentInstallment), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AssetsScreen.rentReceivedKey),
        matching: find.textContaining(l10n.rentReceivedOn('')),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.rentNotReceived), findsNothing);

    await _tap(tester, find.byKey(AssetsScreen.rentSendKey));

    expect(sharer.files.single.name, 'boleto.pdf');
    final caption = sharer.captions.single ?? '';
    expect(caption, contains(r'Consumo de gás: R$'));
    expect(caption, contains(MoneyFormat.format(const Money(169_870))));
  });

  testWidgets('a rent with no bill yet, no PDF or a failed download', (
    tester,
  ) async {
    final repository = MockAssetsRepository();
    final unattached = RentCharge(
      billId: testCharge.billId,
      dueDate: testCharge.dueDate,
      billTotal: testCharge.billTotal,
      passedOn: testCharge.passedOn,
      total: testCharge.total,
      ownerCost: testCharge.ownerCost,
      result: testCharge.result,
    );
    Asset rented(String id, RentCharge? charge) => Asset(
      id: id,
      entity: testAsset.entity,
      kind: AssetKind.property,
      name: 'Apto $id',
      acquiredOn: testAsset.acquiredOn,
      value: testAsset.value,
      valuedOn: testAsset.valuedOn,
      change: testAsset.change,
      equity: testAsset.equity,
      rental: AssetRental(
        rent: testRental.rent,
        passThrough: testRental.passThrough,
        billFrom: testRental.billFrom,
        charge: charge,
      ),
    );
    when(repository.list).thenAnswer(
      (_) async => Ok(
        summaryOf([
          rented('a', null),
          rented('b', unattached),
          rented('c', testCharge),
        ]),
      ),
    );
    when(() => repository.rentBill(testCharge))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final app = await pumpRoute(
      tester,
      AppRoutes.assets,
      screenHeight: 3200,
      overrides: [assetsRepositoryProvider.overrideWithValue(repository)],
    );
    final sharer = app.read(fileSharerProvider) as FakeFileSharer;

    expect(find.text(l10n.rentChargeNoBill), findsOneWidget);
    expect(find.text(l10n.rentNotReceived), findsNWidgets(2));
    await _tap(tester, find.byKey(AssetsScreen.rentSendKey).first);
    expect(sharer.texts.single, contains('Consumo de gás'));
    await _tap(tester, find.byKey(AssetsScreen.rentSendKey).last);
    expect(sharer.files, isEmpty);
    expect(find.text(l10n.rentChargeSend), findsWidgets);
  });

  testWidgets('rents a property out and checks the rental fields', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.assets, screenHeight: _height);
    await _tap(tester, find.byKey(AssetsScreen.addKey));
    await _type(tester, AssetEditor.nameKey, 'Jardim Azul');
    await _type(tester, AssetEditor.valueKey, '30000000');
    await _tap(tester, find.byKey(AssetEditor.rentedKey));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(AssetEditor.billFromKey),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Jardim Azul',
    );
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetRentMissing), findsOneWidget);
    await _type(tester, AssetEditor.rentKey, '160000');
    await _type(tester, AssetEditor.billFromKey, ' ');
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.text(l10n.assetBillFromMissing), findsOneWidget);
    await _type(tester, AssetEditor.billFromKey, 'Jardim Azul');
    await _type(tester, AssetEditor.passThroughKey, 'gás');
    await _tap(tester, find.byKey(AssetEditor.saveKey));

    expect(find.text(l10n.assetAdded), findsOneWidget);
    expect(find.text(l10n.rentChargeNoBill), findsOneWidget);

    await _act(tester, 'asset-home', AssetsScreen.editKey);
    expect(find.byKey(AssetEditor.rentKey), findsOneWidget);
    await _tap(tester, find.byKey(AssetEditor.rentedKey));
    expect(find.byKey(AssetEditor.rentKey), findsNothing);
    await _tap(tester, find.byKey(AssetEditor.saveKey));
    expect(find.byKey(AssetsScreen.rentSendKey), findsNothing);
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
