import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/home/domain/home_repository.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';

/// Fictional balances around today. Approved drafts and issued invoices
/// live in memory for the session.
final class FakeHomeRepository implements HomeRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  final Set<String> _done = {};

  static const _personalBalance = Money(1_874_230);
  static const _companyCash = Money(4_618_000);

  CalendarDate get _today => CalendarDate.brazilToday(_clock.now());

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<Result<PersonalSummary>> personal() async {
    await _wait();
    final now = _clock.now();
    const restaurants = BudgetSummary(
      category: BudgetCategory.restaurants,
      spent: Money(62_400),
      limit: Money(60_000),
    );
    return Ok(
      PersonalSummary(
        balance: _personalBalance,
        sync: SyncInfo(
          accountCount: 5,
          syncedAt: now.subtract(const Duration(minutes: 4)),
        ),
        reserve: const ReserveSummary(
          institution: 'Banco Aurora',
          product: 'CDB liquidez diária',
          balance: Money(620_000),
          monthYield: Money(4_812),
          coverDays: 23,
          cdiPercent: 101,
        ),
        forecast: CashForecast.project(
          from: _today,
          start: _personalBalance,
          dailySpend: const Money(8_500),
          days: 30,
          floor: const Money(900_000),
          events: const {
            2: Money(-11_990),
            4: Money(-28_740),
            7: Money(-240_000),
            12: Money(-78_000),
            15: Money(-45_000),
            20: Money(-183_044),
            24: Money(-9_620),
            28: Money(780_000),
          },
        ),
        budgets: const [
          BudgetSummary(
            category: BudgetCategory.transport,
            spent: Money(15_200),
            limit: Money(40_000),
          ),
          BudgetSummary(
            category: BudgetCategory.groceries,
            spent: Money(98_400),
            limit: Money(120_000),
          ),
          restaurants,
        ],
        alerts: [
          AssistedPaymentAlert(
            billId: 'bill-rent',
            payee: 'Aluguel',
            reason: 'Acima do limite por pagamento, sem confirmação no app',
            at: now.subtract(const Duration(hours: 3)),
          ),
          BudgetExceededAlert(
            budget: restaurants,
            at: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
    );
  }

  CompanySummary _company() {
    final today = _today;
    return CompanySummary(
      cash: _companyCash,
      sync: SyncInfo(
        accountCount: 2,
        syncedAt: _clock.now().subtract(const Duration(minutes: 6)),
      ),
      billed: const Money(1_984_000),
      invoiceCount: 3,
      dasEstimate: const Money(146_022),
      dasDue: today.addDays(43),
      inss: TaxEstimate(amount: const Money(93_231), due: today.addDays(11)),
      drafts: [
        if (!_done.contains('draft-pomar'))
          InvoiceDraft(
            id: 'draft-pomar',
            customer: 'Pomar Digital',
            amount: const Money(800_000),
            recurring: true,
            issueOn: today.addDays(2),
          ),
      ],
      unbilled: [
        if (!_done.contains('receipt-pix-lia'))
          UnbilledReceipt(
            id: 'receipt-pix-lia',
            payer: 'Lia Moreira',
            amount: const Money(120_000),
            receivedOn: today.addDays(-5),
          ),
      ],
    );
  }

  @override
  Future<Result<FundingPlan>> funding() async {
    await _wait();
    return const Ok(
      FundingPlan(
        balance: Money(42_000),
        monthlyAverage: Money(218_500),
        months: 3,
        upcoming: Money(96_300),
        topUp: Money(54_300),
      ),
    );
  }

  @override
  Future<Result<CompanySummary>> company() async {
    await _wait();
    return Ok(_company());
  }

  @override
  Future<Result<ConsolidatedSummary>> consolidated() async {
    await _wait();
    final today = _today;
    return Ok(
      ConsolidatedSummary(
        personal: _personalBalance,
        company: _companyCash,
        externalIn: const Money(920_000),
        externalOut: const Money(-825_842),
        transfers: [
          InternalTransfer(
            id: 'transfer-distribution',
            kind: InternalTransferKind.profitDistribution,
            amount: const Money(500_000),
            on: today.addDays(-2),
          ),
          InternalTransfer(
            id: 'transfer-prolabore',
            kind: InternalTransferKind.proLabore,
            amount: const Money(780_000),
            on: today.addDays(-1),
          ),
        ],
      ),
    );
  }

  Future<Result<CompanySummary>> _settle(String id, List<String> open) async {
    await _wait();
    if (!open.contains(id)) return const Err(NotFoundFailure());
    _done.add(id);
    return Ok(_company());
  }

  @override
  Future<Result<CompanySummary>> approveDraft(String id) =>
      _settle(id, [for (final draft in _company().drafts) draft.id]);

  @override
  Future<Result<CompanySummary>> issueInvoiceFor(String receiptId) =>
      _settle(receiptId, [for (final r in _company().unbilled) r.id]);
}
