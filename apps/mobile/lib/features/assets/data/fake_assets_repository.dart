import 'dart:convert';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// What the offline table answers for any FIPE code.
const fakeFipePrice = Money(8_950_000);

/// A fictional home bought with a loan and rented out, and a car priced by
/// the FIPE table, kept in memory.
final class FakeAssetsRepository implements AssetsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _next = 0;

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  late final Map<String, Asset> _assets = {
    for (final asset in [
      Asset(
        id: 'asset-home',
        entity: EntityKind.personal,
        kind: AssetKind.property,
        name: 'Apartamento',
        acquiredOn: CalendarDate(_today.year - 3, 3, 10),
        value: const Money(62_000_000),
        valuedOn: _today,
        change: const Money(7_000_000),
        changePercent: 12.7,
        loan: const AssetLoan(
          id: 'loan-home',
          name: 'Banco Exemplo 1001',
          balance: Money(17_400_000),
        ),
        equity: const Money(44_600_000),
        rental: AssetRental(
          rent: const Money(160_000),
          passThrough: const ['gás'],
          billFrom: 'Jardim Exemplo',
          charge: RentCharge(
            billId: 'bill-condo',
            dueDate: CalendarDate(_today.year, _today.month, 10),
            billTotal: const Money(59_769),
            passedOn: const [
              BillLine(description: 'Consumo de gás', amount: Money(13_665)),
            ],
            total: const Money(173_665),
            ownerCost: const Money(46_104),
            attachmentId: 'attachment-condo',
            installment: const Money(108_500),
            result: const Money(5_396),
          ),
        ),
      ),
      Asset(
        id: 'asset-car',
        entity: EntityKind.personal,
        kind: AssetKind.vehicle,
        name: 'Hatch Exemplo 1.0 Flex',
        acquiredOn: CalendarDate(_today.year - 2, 1, 15),
        value: fakeFipePrice,
        valuedOn: CalendarDate(_today.year, _today.month, 1),
        change: const Money(-450_000),
        changePercent: -4.8,
        fipe: const FipeVehicle(
          type: VehicleType.car,
          code: '001234-5',
          modelYear: 2022,
        ),
        equity: fakeFipePrice,
      ),
    ])
      asset.id: asset,
  };

  AssetsSummary _summary() {
    final items = _assets.values.toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    Money total(Money Function(Asset) pick) =>
        items.fold(const Money(0), (sum, asset) => sum + pick(asset));
    return AssetsSummary(
      items: items,
      value: total((asset) => asset.value),
      loanDebt: total((asset) => asset.loan?.balance ?? const Money(0)),
      equity: total((asset) => asset.equity),
    );
  }

  Future<Result<Asset>> _replace(
    String id,
    Asset Function(Asset) change,
  ) async {
    await Future<void>.delayed(latency);
    final asset = _assets[id];
    if (asset == null) return const Err(NotFoundFailure());
    return Ok(_assets[id] = change(asset));
  }

  static const _models = {
    '10': 'Hatch Exemplo 1.0 Flex',
    '11': 'Sedan Exemplo 2.0 Turbo',
  };

  @override
  Future<Result<List<VehicleOption>>> brands(VehicleType type) async {
    await Future<void>.delayed(latency);
    return const Ok([
      VehicleOption(code: '1', name: 'Marca Exemplo'),
      VehicleOption(code: '2', name: 'Outra Marca'),
    ]);
  }

  @override
  Future<Result<List<VehicleOption>>> years(
    VehicleType type,
    String brand,
  ) async {
    await Future<void>.delayed(latency);
    return Ok([
      for (var year = _today.year + 1; year > _today.year - 4; year--)
        VehicleOption(code: '$year', name: '$year'),
    ]);
  }

  @override
  Future<Result<List<VehicleOption>>> models(
    VehicleType type,
    String brand,
    int modelYear,
  ) async {
    await Future<void>.delayed(latency);
    return Ok([
      for (final MapEntry(:key, :value) in _models.entries)
        VehicleOption(code: key, name: value, year: '$modelYear-5'),
    ]);
  }

  @override
  Future<Result<CatalogVehicle>> price(
    VehicleType type,
    String brand,
    VehicleOption model,
  ) async {
    await Future<void>.delayed(latency);
    final name = _models[model.code];
    final year = int.tryParse(model.year?.split('-').first ?? '');
    if (name == null || year == null) return const Err(NotFoundFailure());
    return Ok(
      CatalogVehicle(
        fipe: FipeVehicle(
          type: type,
          code: '0012${model.code}-5',
          modelYear: year,
        ),
        model: name,
        price: fakeFipePrice,
      ),
    );
  }

  @override
  Future<Result<AssetsSummary>> list() async {
    await Future<void>.delayed(latency);
    return Ok(_summary());
  }

  @override
  Future<Result<Asset>> create(AssetDraft draft) async {
    await Future<void>.delayed(latency);
    final fipe = draft.kind == AssetKind.vehicle ? draft.fipe : null;
    final value = fipe == null || draft.value.cents > 0
        ? draft.value
        : fakeFipePrice;
    final asset = Asset(
      id: 'asset-${_next++}',
      entity: EntityKind.personal,
      kind: draft.kind,
      name: draft.name.trim().isEmpty
          ? 'FIPE ${fipe?.code}'
          : draft.name.trim(),
      acquiredOn: draft.acquiredOn,
      value: value,
      valuedOn: _today,
      change: const Money(0),
      changePercent: 0,
      fipe: fipe,
      equity: value,
      rental: _rentalOf(draft.rental, null),
    );
    return Ok(_assets[asset.id] = asset);
  }

  @override
  Future<Result<Asset>> edit(Asset before, AssetDraft draft) {
    final priced = draft.kind == AssetKind.vehicle && draft.byFipe;
    final fipe = priced ? draft.fipe : null;
    final value = switch ((priced, fipe != null && fipe != before.fipe)) {
      (_, true) => fakeFipePrice,
      (true, false) => before.value,
      (false, _) => draft.value,
    };
    return _replace(before.id, (asset) {
      final loan = draft.loanId == asset.loan?.id ? asset.loan : null;
      final name = draft.name.trim();
      return Asset(
        id: asset.id,
        entity: asset.entity,
        kind: asset.kind,
        name: name.isEmpty ? asset.name : name,
        acquiredOn: draft.acquiredOn,
        value: value,
        valuedOn: _today,
        change: asset.change + value - asset.value,
        fipe: fipe,
        loan: loan,
        equity: value - (loan?.balance ?? const Money(0)),
        rental: _rentalOf(draft.rental, asset.rental),
      );
    });
  }

  // The charge comes from a captured bill, which this table does not keep.
  AssetRental? _rentalOf(RentalDraft? draft, AssetRental? before) =>
      switch (draft) {
        null => null,
        final draft => AssetRental(
          rent: draft.rent,
          passThrough: draft.words,
          billFrom: draft.billFrom.trim(),
          charge: before?.charge,
        ),
      };

  @override
  Future<Result<LocalFile>> rentBill(RentCharge charge) async {
    await Future<void>.delayed(latency);
    if (charge.attachmentId == null) return const Err(NotFoundFailure());
    return Ok(
      LocalFile(
        name: 'boleto.pdf',
        bytes: utf8.encode('%PDF-1.4 fake'),
        mimeType: 'application/pdf',
      ),
    );
  }

  @override
  Future<Result<Asset>> revalue(String id, Money value) => _replace(
    id,
    (asset) => Asset(
      id: asset.id,
      entity: asset.entity,
      kind: asset.kind,
      name: asset.name,
      acquiredOn: asset.acquiredOn,
      value: value,
      valuedOn: _today,
      change: asset.change + value - asset.value,
      fipe: asset.fipe,
      loan: asset.loan,
      equity: value - (asset.loan?.balance ?? const Money(0)),
      rental: asset.rental,
    ),
  );

  @override
  Future<Result<Asset>> markSold(String id, CalendarDate on) => _replace(
    id,
    (asset) => Asset(
      id: asset.id,
      entity: asset.entity,
      kind: asset.kind,
      name: asset.name,
      acquiredOn: asset.acquiredOn,
      soldOn: on,
      value: const Money(0),
      valuedOn: asset.valuedOn,
      change: asset.change - asset.value,
      fipe: asset.fipe,
      equity: const Money(0),
    ),
  );

  @override
  Future<Result<void>> delete(String id) async {
    await Future<void>.delayed(latency);
    return _assets.remove(id) == null
        ? const Err(NotFoundFailure())
        : const Ok(null);
  }
}
