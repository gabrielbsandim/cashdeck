import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/domain/investments_repository.dart';

/// Fictional positions in two institutions, due around today.
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
}
