import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

typedef _Seed = (
  int daysBack,
  String account,
  int cents,
  String description,
  String? category,
  CategorySource? source,
);

/// Fictional transactions over the last weeks for both entities, a few still
/// without a category. Changes live in memory for the session.
final class FakeTransactionsRepository implements TransactionsRepository {
  new(
    this._clock, {
    this.latency = const Duration(milliseconds: 250),
    this.pageSize = 15,
  });

  final Clock _clock;
  final Duration latency;
  final int pageSize;
  List<Transaction>? _rows;

  static const accountsList = [
    TransactionAccount(
      id: 'acc-pf-checking',
      name: 'Corrente Aurora ••4410',
      owner: EntityKind.personal,
      institution: 'Banco Aurora',
    ),
    TransactionAccount(
      id: 'acc-pf-card',
      name: 'Cartão Horizonte ••9021',
      owner: EntityKind.personal,
      institution: 'Horizonte',
    ),
    TransactionAccount(
      id: 'acc-pj-checking',
      name: 'Aurora PJ ••7702',
      owner: EntityKind.company,
      institution: 'Banco Aurora',
    ),
  ];

  static const List<_Seed> _seeds = [
    (
      0,
      'acc-pf-card',
      -4_590,
      'Padaria Trigo Bom',
      'cat-restaurants',
      CategorySource.rule,
    ),
    (0, 'acc-pf-checking', -12_000, 'Posto Estrada Azul', null, null),
    (
      0,
      'acc-pj-checking',
      650_000,
      'Cliente Atlas Software',
      'cat-income',
      CategorySource.user,
    ),
    (
      1,
      'acc-pf-card',
      -23_480,
      'Mercado Bom Preço',
      'cat-groceries',
      CategorySource.ai,
    ),
    (1, 'acc-pf-checking', -780_000, 'Pix enviado Pro-labore', null, null),
    (
      1,
      'acc-pj-checking',
      -780_000,
      'Pro-labore setembro',
      'cat-salary',
      CategorySource.user,
    ),
    (
      2,
      'acc-pf-card',
      -3_990,
      'Streaming Lumen',
      'cat-subscriptions',
      CategorySource.rule,
    ),
    (2, 'acc-pj-checking', -500_000, 'Distribuição de lucros', null, null),
    (2, 'acc-pf-checking', 500_000, 'Distribuição de lucros', null, null),
    (
      3,
      'acc-pf-card',
      -6_750,
      'Farmácia Vida Plena',
      'cat-health',
      CategorySource.ai,
    ),
    (
      3,
      'acc-pj-checking',
      -14_900,
      'Coworking Ponte',
      'cat-services',
      CategorySource.rule,
    ),
    (
      4,
      'acc-pf-card',
      -2_890,
      'Mobilidade Rota Certa',
      'cat-transport',
      CategorySource.ai,
    ),
    (4, 'acc-pf-card', -18_900, 'Restaurante Sabor da Ilha', null, null),
    (
      5,
      'acc-pj-checking',
      -9_990,
      'Software Nuvem Clara',
      'cat-subscriptions',
      CategorySource.ai,
    ),
    (
      5,
      'acc-pf-checking',
      -28_740,
      'Energia Lumina',
      'cat-utilities',
      CategorySource.rule,
    ),
    (
      6,
      'acc-pf-card',
      -15_620,
      'Mercado Bom Preço',
      'cat-groceries',
      CategorySource.ai,
    ),
    (7, 'acc-pf-card', -2_590, 'Mobilidade Rota Certa', null, null),
    (
      8,
      'acc-pj-checking',
      -48_000,
      'DAS Simples Nacional',
      'cat-taxes',
      CategorySource.rule,
    ),
    (
      9,
      'acc-pf-checking',
      -11_990,
      'Internet Fibra Sul',
      'cat-utilities',
      CategorySource.user,
    ),
    (
      10,
      'acc-pf-card',
      -32_000,
      'Livraria Página Nova',
      'cat-education',
      CategorySource.ai,
    ),
    (
      11,
      'acc-pj-checking',
      420_000,
      'Cliente Orla Design',
      'cat-income',
      CategorySource.rule,
    ),
    (
      12,
      'acc-pf-card',
      -8_700,
      'Cinema Estrela',
      'cat-leisure',
      CategorySource.ai,
    ),
    (
      13,
      'acc-pf-card',
      -21_300,
      'Mercado Bom Preço',
      'cat-groceries',
      CategorySource.ai,
    ),
    (
      14,
      'acc-pf-checking',
      -150_000,
      'Aluguel Residencial',
      'cat-housing',
      CategorySource.user,
    ),
    (
      15,
      'acc-pj-checking',
      -2_500,
      'Tarifa bancária',
      'cat-fees',
      CategorySource.rule,
    ),
    (
      16,
      'acc-pf-card',
      -4_200,
      'Padaria Trigo Bom',
      'cat-restaurants',
      CategorySource.rule,
    ),
    (
      17,
      'acc-pf-card',
      -9_800,
      'Posto Estrada Azul',
      'cat-fuel',
      CategorySource.ai,
    ),
    (
      18,
      'acc-pj-checking',
      -19_900,
      'Contabilidade Prisma',
      'cat-services',
      CategorySource.user,
    ),
    (
      19,
      'acc-pf-card',
      -5_400,
      'Mobilidade Rota Certa',
      'cat-transport',
      CategorySource.ai,
    ),
    (
      20,
      'acc-pf-checking',
      -60_000,
      'Aplicação Tesouro',
      'cat-investments',
      CategorySource.rule,
    ),
  ];

  static const _transfers = {
    'Distribuição de lucros': 'transfer-distribution',
    'Pro-labore setembro': 'transfer-prolabore',
    'Pix enviado Pro-labore': 'transfer-prolabore',
  };

  static EntityKind _ownerOf(String accountId) =>
      accountsList.firstWhere((account) => account.id == accountId).owner;

  List<Transaction> _seed() {
    final today = CalendarDate.brazilToday(_clock.now());
    return [
      for (final (index, seed) in _seeds.indexed)
        _transaction(index, seed, today),
    ];
  }

  static Transaction _transaction(int index, _Seed seed, CalendarDate today) {
    final (back, account, cents, description, category, source) = seed;
    final transferId = _transfers[description];
    final kind = switch ((transferId, cents.isNegative)) {
      (String(), _) => TransactionKind.transfer,
      (null, true) => TransactionKind.expense,
      (null, false) => TransactionKind.income,
    };
    return Transaction(
      id: 'tx-${index + 1}',
      accountId: account,
      owner: _ownerOf(account),
      amount: Money(cents),
      bookedOn: today.addDays(-back),
      description: description,
      kind: kind,
      categoryId: category,
      transferId: transferId,
      categorizedBy: source,
      categoryConfidence: source == CategorySource.ai ? 0.86 : null,
    );
  }

  List<Transaction> get _all => _rows ??= _seed();

  @override
  Future<Result<TransactionPage>> list(
    TransactionQuery query, {
    String? cursor,
  }) async {
    await Future<void>.delayed(latency);
    final matching = _all.where(query.matches).toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, matching.length);
    return Ok(
      TransactionPage(
        items: matching.sublist(start.clamp(0, matching.length), end),
        nextCursor: end < matching.length ? '$end' : null,
      ),
    );
  }

  @override
  Future<Result<TransactionUpdateResult>> update(
    String id,
    TransactionUpdate update,
  ) async {
    await Future<void>.delayed(latency);
    final index = _all.indexWhere((row) => row.id == id);
    if (index < 0) return const Err(NotFoundFailure());
    final current = _all[index];
    final categoryId = update.categoryId;
    final changed = _with(
      current,
      categoryId: categoryId,
      note: update.note,
      source: categoryId == null ? null : CategorySource.user,
    );
    _all[index] = changed;
    var similar = 0;
    if (categoryId != null && update.applyToSimilar) {
      similar = _applyToSimilar(changed, categoryId);
    }
    return Ok(
      TransactionUpdateResult(transaction: changed, similarUpdated: similar),
    );
  }

  int _applyToSimilar(Transaction source, String categoryId) {
    var count = 0;
    for (final (index, row) in _all.indexed) {
      final similar =
          row.id != source.id &&
          row.owner == source.owner &&
          row.description.toLowerCase() == source.description.toLowerCase() &&
          row.categorizedBy != CategorySource.user;
      if (!similar) continue;
      _all[index] = _with(
        row,
        categoryId: categoryId,
        source: CategorySource.rule,
      );
      count++;
    }
    return count;
  }

  static Transaction _with(
    Transaction row, {
    String? categoryId,
    String? note,
    CategorySource? source,
  }) {
    final clearedNote = note?.trim();
    return Transaction(
      id: row.id,
      accountId: row.accountId,
      owner: row.owner,
      amount: row.amount,
      bookedOn: row.bookedOn,
      description: row.description,
      kind: row.kind,
      categoryId: categoryId ?? row.categoryId,
      transferId: row.transferId,
      invoiceId: row.invoiceId,
      note: switch (clearedNote) {
        null => row.note,
        '' => null,
        final String text => text,
      },
      categorizedBy: source ?? row.categorizedBy,
      categoryConfidence: source == null ? row.categoryConfidence : null,
    );
  }

  @override
  Future<Result<List<TransactionAccount>>> accounts() async {
    await Future<void>.delayed(latency);
    return const Ok(accountsList);
  }
}

/// The built-in categories, with the keys the server seeds.
final class FakeCategoriesRepository implements CategoriesRepository {
  const new({this.latency = const Duration(milliseconds: 150)});

  final Duration latency;

  static const keys = [
    'groceries',
    'restaurants',
    'transport',
    'fuel',
    'housing',
    'utilities',
    'health',
    'education',
    'leisure',
    'shopping',
    'subscriptions',
    'travel',
    'taxes',
    'fees',
    'salary',
    'income',
    'investments',
    'transfers',
    'services',
    'other',
  ];

  @override
  Future<Result<List<Category>>> list() async {
    await Future<void>.delayed(latency);
    return Ok([
      for (final key in keys)
        Category(id: 'cat-$key', key: key, name: key, icon: key),
      const Category(id: 'cat-pets', name: 'Pets'),
    ]);
  }
}
