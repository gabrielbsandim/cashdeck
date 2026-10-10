import 'dart:math' as math;

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';

/// A fictional buy, sale, payout or tax, some days before today.
typedef _Movement = ({
  String id,
  InvestmentMovementKind kind,
  int daysAgo,
  int cents,
  double? quantity,
  double? unitPrice,
});

_Movement _move(
  String id,
  InvestmentMovementKind kind,
  int daysAgo,
  int cents, {
  double? quantity,
  double? unitPrice,
}) => (
  id: id,
  kind: kind,
  daysAgo: daysAgo,
  cents: cents,
  quantity: quantity,
  unitPrice: unitPrice,
);

/// Fictional positions in two institutions, due around today, valued back in
/// time from a made up yearly yield and their movements.
final class FakeInvestmentsRepository implements InvestmentsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  List<InvestmentPosition> get _positions => [
    InvestmentPosition(
      id: 'cdb-aurora',
      owner: EntityKind.personal,
      institutionId: 'aurora',
      institution: 'Banco Aurora',
      name: 'CDB Banco Aurora',
      kind: InvestmentKind.fixedIncome,
      subtype: 'CDB',
      issuer: 'Banco Aurora S.A.',
      balance: const Money(1_052_340),
      invested: const Money(1_000_000),
      profit: const Money(52_340),
      profitPercent: 5.23,
      rate: const InvestmentRate(percent: 102, index: 'CDI'),
      dueOn: _today.addDays(540),
      valuedOn: _today.addDays(-1),
    ),
    InvestmentPosition(
      id: 'tesouro-ipca',
      owner: EntityKind.personal,
      institutionId: 'horizonte',
      institution: 'Corretora Horizonte',
      name: 'Tesouro IPCA+ 2035',
      kind: InvestmentKind.fixedIncome,
      subtype: 'TREASURY',
      issuer: 'Tesouro Nacional',
      balance: const Money(830_000),
      invested: const Money(800_000),
      profit: const Money(30_000),
      profitPercent: 3.75,
      quantity: 2.5,
      rate: const InvestmentRate(index: 'IPCA', fixedAnnual: 6.2),
      dueOn: _today.addDays(3300),
    ),
    InvestmentPosition(
      id: 'lci-aurora',
      owner: EntityKind.personal,
      institutionId: 'aurora',
      institution: 'Banco Aurora',
      name: 'LCI Banco Aurora',
      kind: InvestmentKind.fixedIncome,
      subtype: 'LCI',
      issuer: 'Banco Aurora S.A.',
      balance: const Money(515_000),
      invested: const Money(500_000),
      profit: const Money(15_000),
      profitPercent: 3,
      rate: const InvestmentRate(percent: 95, index: 'CDI'),
      dueOn: _today.addDays(200),
    ),
    const InvestmentPosition(
      id: 'multimercado',
      owner: EntityKind.personal,
      institutionId: 'horizonte',
      institution: 'Corretora Horizonte',
      name: 'Horizonte Multimercado FIC',
      kind: InvestmentKind.fund,
      subtype: 'MULTIMARKET_FUND',
      balance: Money(412_000),
      invested: Money(420_000),
      profit: Money(-8_000),
      profitPercent: -1.9,
      lastMonthRate: 0.4,
      lastTwelveMonthsRate: 7.8,
    ),
    const InvestmentPosition(
      id: 'fii',
      owner: EntityKind.personal,
      institutionId: 'horizonte',
      institution: 'Corretora Horizonte',
      name: 'ABCD11',
      kind: InvestmentKind.equity,
      subtype: 'REAL_ESTATE_FUND',
      issuer: 'Fundo Imobiliário Exemplo',
      pending: true,
      balance: Money(250_000),
      quantity: 25,
    ),
    InvestmentPosition(
      id: 'cdb-empresa',
      owner: EntityKind.company,
      institutionId: 'aurora',
      institution: 'Banco Aurora',
      name: 'CDB Banco Aurora Empresas',
      kind: InvestmentKind.fixedIncome,
      subtype: 'CDB',
      issuer: 'Banco Aurora S.A.',
      balance: const Money(2_000_000),
      invested: const Money(1_950_000),
      profit: const Money(50_000),
      profitPercent: 2.56,
      rate: const InvestmentRate(percent: 104, index: 'CDI'),
      dueOn: _today.addDays(90),
    ),
  ];

  static const Map<String, double> _annualYield = {
    'cdb-aurora': 11.2,
    'tesouro-ipca': 9.8,
    'lci-aurora': 10.1,
    'multimercado': -2.4,
    'fii': 6.5,
    'cdb-empresa': 11.6,
  };

  static const _cdiAnnual = 10.5;

  static final Map<String, List<_Movement>> _movements = {
    'cdb-aurora': [
      _move('m-1', InvestmentMovementKind.buy, 420, 1_000_000, quantity: 1000),
    ],
    'tesouro-ipca': [
      _move(
        'm-2',
        InvestmentMovementKind.buy,
        20,
        200_000,
        quantity: 0.5,
        unitPrice: 4000,
      ),
      _move('m-3', InvestmentMovementKind.income, 60, 12_400),
      _move(
        'm-4',
        InvestmentMovementKind.buy,
        510,
        600_000,
        quantity: 2,
        unitPrice: 3000,
      ),
    ],
    'lci-aurora': [
      _move('m-5', InvestmentMovementKind.buy, 200, 500_000, quantity: 500),
    ],
    'multimercado': [
      _move(
        'm-6',
        InvestmentMovementKind.buy,
        300,
        420_000,
        quantity: 3150.4,
        unitPrice: 1.3332,
      ),
    ],
    'fii': [
      _move(
        'm-7',
        InvestmentMovementKind.buy,
        3,
        250_000,
        quantity: 25,
        unitPrice: 100,
      ),
    ],
    'cdb-empresa': [
      _move('m-8', InvestmentMovementKind.sell, 10, 100_000, quantity: 100),
      _move('m-9', InvestmentMovementKind.tax, 10, 2_300),
      _move('m-10', InvestmentMovementKind.buy, 150, 2_050_000, quantity: 2050),
    ],
  };

  static int _days(PerformancePeriod period) => switch (period) {
    PerformancePeriod.week => 7,
    PerformancePeriod.month => 30,
    PerformancePeriod.year => 365,
  };

  static Iterable<_Movement> _movesOf(Iterable<InvestmentPosition> positions) =>
      [for (final position in positions) ...?_movements[position.id]];

  /// Buys add to the value from their day on, sales take from it; a fund or
  /// a stock also wobbles around its yield.
  static double _valueAt(InvestmentPosition position, int daysAgo) {
    if (daysAgo == 0) return position.balance.cents.toDouble();
    var later = 0;
    for (final move in _movesOf([position])) {
      if (move.daysAgo >= daysAgo) continue;
      later += _signed(move);
    }
    final growth = math.pow(
      1 + (_annualYield[position.id] ?? 0) / 100,
      daysAgo / 365,
    );
    final wobble = switch (position.kind) {
      InvestmentKind.fund ||
      InvestmentKind.equity => 1 + 0.012 * math.sin(daysAgo / 6),
      _ => 1.0,
    };
    return math.max(0, (position.balance.cents - later) / growth * wobble);
  }

  /// A buy as money in, a sale as money out, anything else as no flow.
  static int _signed(_Movement move) => switch (move.kind) {
    InvestmentMovementKind.buy => move.cents,
    InvestmentMovementKind.sell => -move.cents,
    _ => 0,
  };

  static int _valueOf(Iterable<InvestmentPosition> positions, int daysAgo) =>
      positions
          .fold<double>(0, (sum, position) => sum + _valueAt(position, daysAgo))
          .round();

  static double _round(double value) => (value * 100).round() / 100;

  /// The start value, the flows inside the window and the yield, with its
  /// percent by Modified Dietz as the API computes it.
  static ({int start, int buys, int sells, int gain, double? percent}) _summary(
    Iterable<InvestmentPosition> positions,
    int days,
  ) {
    final start = _valueOf(positions, days);
    final end = positions.fold(0, (sum, item) => sum + item.balance.cents);
    final inside = [
      for (final move in _movesOf(positions))
        if (move.daysAgo < days) move,
    ];
    final buys = inside.fold(
      0,
      (sum, move) => sum + math.max(0, _signed(move)),
    );
    final sells = inside.fold(
      0,
      (sum, move) => sum - math.min(0, _signed(move)),
    );
    final gain = end - start - buys + sells;
    final base = inside.fold(
      start.toDouble(),
      (sum, move) => sum + move.daysAgo / days * _signed(move),
    );
    return (
      start: start,
      buys: buys,
      sells: sells,
      gain: gain,
      percent: base <= 0 ? null : _round(gain * 100 / base),
    );
  }

  InvestmentPerformance _performance(
    List<InvestmentPosition> held,
    PerformancePeriod period, {
    bool withPositions = true,
  }) {
    final days = _days(period);
    final today = _today;
    final step = period == PerformancePeriod.year ? 7 : 1;
    final summary = _summary(held, days);
    PositionPerformance own(InvestmentPosition position) {
      final summary = _summary([position], days);
      return PositionPerformance(
        id: position.id,
        start: Money(summary.start),
        end: position.balance,
        yieldAmount: Money(summary.gain),
        yieldPercent: summary.percent,
      );
    }

    final positions = [if (withPositions) ...held.map(own)]
      ..sort((a, b) => b.yieldAmount.compareTo(a.yieldAmount));
    return InvestmentPerformance(
      period: period,
      from: today.addDays(-days),
      to: today,
      start: Money(summary.start),
      end: _sum(held.map((position) => position.balance)),
      contributions: Money(summary.buys),
      withdrawals: Money(summary.sells),
      yieldAmount: Money(summary.gain),
      yieldPercent: summary.percent,
      cdiPercent: _round(
        (math.pow(1 + _cdiAnnual / 100, days / 365) - 1) * 100,
      ),
      estimated: period != PerformancePeriod.week,
      series: [
        for (var daysAgo = days; daysAgo > 0; daysAgo -= step)
          PerformancePoint(
            today.addDays(-daysAgo),
            Money(_valueOf(held, daysAgo)),
          ),
        PerformancePoint(today, Money(_valueOf(held, 0))),
      ],
      positions: positions,
    );
  }

  static bool _inScope(EntityScope scope, EntityKind owner) => switch (scope) {
    EntityScope.personal => owner == EntityKind.personal,
    EntityScope.company => owner == EntityKind.company,
    EntityScope.consolidated => true,
  };

  static Money _sum(Iterable<Money?> values) => values.fold(
    const Money(0),
    (sum, value) => sum + (value ?? const Money(0)),
  );

  @override
  Future<Result<Investments>> investments(EntityScope scope) async {
    await Future<void>.delayed(latency);
    final held = [
      for (final position in _positions)
        if (_inScope(scope, position.owner)) position,
    ]..sort((a, b) => b.balance.cents.compareTo(a.balance.cents));
    final byInstitution = <String, List<InvestmentPosition>>{};
    final byKind = <InvestmentKind, List<InvestmentPosition>>{};
    for (final position in held) {
      (byInstitution[position.institutionId] ??= []).add(position);
      (byKind[position.kind] ??= []).add(position);
    }
    return Ok(
      Investments(
        total: _sum(held.map((position) => position.balance)),
        invested: _sum(held.map((position) => position.invested)),
        profit: _sum(held.map((position) => position.profit)),
        syncedAt: _clock.now().subtract(const Duration(hours: 2)),
        institutions: [
          for (final MapEntry(:key, :value) in byInstitution.entries)
            InstitutionHoldings(
              institutionId: key,
              institution: value.first.institution,
              total: _sum(value.map((position) => position.balance)),
              count: value.length,
            ),
        ],
        kinds: [
          for (final MapEntry(:key, :value) in byKind.entries)
            KindHoldings(
              kind: key,
              total: _sum(value.map((position) => position.balance)),
              count: value.length,
            ),
        ],
        positions: held,
      ),
    );
  }

  @override
  Future<Result<InvestmentPerformance>> performance(
    EntityScope scope,
    PerformancePeriod period,
  ) async {
    await Future<void>.delayed(latency);
    final held = [
      for (final position in _positions)
        if (_inScope(scope, position.owner)) position,
    ];
    return Ok(_performance(held, period));
  }

  @override
  Future<Result<InvestmentDetail>> position(
    String id,
    PerformancePeriod period,
  ) async {
    await Future<void>.delayed(latency);
    final position = _positions.where((item) => item.id == id).firstOrNull;
    if (position == null) return const Err(NotFoundFailure());
    final today = _today;
    return Ok(
      InvestmentDetail(
        position: position,
        performance: _performance([position], period, withPositions: false),
        movements: [
          for (final move in _movements[id] ?? const <_Movement>[])
            InvestmentMovement(
              id: move.id,
              kind: move.kind,
              occurredOn: today.addDays(-move.daysAgo),
              amount: Money(move.cents),
              quantity: move.quantity,
              unitPrice: move.unitPrice,
            ),
        ],
      ),
    );
  }
}
