import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// Fictional bills around today, one per state of the payment ladder. Marks
/// and confirmations live in memory for the session.
final class FakeBillsRepository implements BillsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  final Map<String, Bill> _changed = {};

  static const List<LadderStep> _personalPlan = [
    LadderStep.automatic,
    LadderStep.assisted,
  ];
  static const List<LadderStep> _companyPlan = LadderStep.values;
  static const List<LadderStep> _taxPlan = [
    LadderStep.automatic,
    LadderStep.assisted,
  ];

  /// 07:00 in Brazil on [day], when the ladder runs.
  static DateTime _morning(CalendarDate day, {int minutes = 0}) =>
      DateTime.utc(day.year, day.month, day.day, 10, minutes);

  List<Bill> _seed() {
    final today = CalendarDate.brazilToday(_clock.now());
    final taxDue = today.addDays(12);
    return [
      Bill(
        id: 'bill-internet',
        payee: 'Internet Fibra Sul',
        amount: const Money(11_990),
        dueDate: today.addDays(-2),
        kind: BillKind.boleto,
        owner: EntityKind.personal,
        status: BillStatus.pending,
        source: BillSource.email,
        plan: _personalPlan,
        paymentCode: '23793.38128 60000.000003 00000.000400 1 98760000011990',
        attempts: [
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API',
            at: _morning(today.addDays(-2)),
            outcome: AttemptOutcome.failed,
            reason: 'Saldo insuficiente na reserva',
          ),
        ],
      ),
      Bill(
        id: 'bill-energy',
        payee: 'Energia Lumina',
        amount: const Money(28_740),
        dueDate: today.addDays(4),
        kind: BillKind.boleto,
        owner: EntityKind.personal,
        status: BillStatus.scheduled,
        source: BillSource.email,
        plan: _personalPlan,
        paymentCode: '23793.38128 60000.000003 00000.000400 1 98760000028740',
      ),
      Bill(
        id: 'bill-rent',
        payee: 'Aluguel',
        amount: const Money(240_000),
        dueDate: today.addDays(7),
        kind: BillKind.boleto,
        owner: EntityKind.personal,
        status: BillStatus.pending,
        source: BillSource.share,
        plan: _personalPlan,
        paymentCode: '34191.79001 01043.510047 91020.150008 1 10070000240000',
        attempts: [
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API',
            at: _morning(today),
            outcome: AttemptOutcome.waiting,
            reason: 'Acima do limite por pagamento, confirmação pedida no app',
          ),
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API',
            at: _morning(today, minutes: 300),
            outcome: AttemptOutcome.failed,
            reason: 'Sem confirmação no prazo',
          ),
        ],
      ),
      Bill(
        id: 'bill-gym',
        payee: 'Academia Ritmo',
        amount: const Money(14_990),
        dueDate: today.addDays(9),
        kind: BillKind.pixKey,
        owner: EntityKind.personal,
        status: BillStatus.needsConfirmation,
        source: BillSource.chat,
        plan: _personalPlan,
      ),
      Bill(
        id: 'bill-condo',
        payee: 'Condomínio Jardim',
        amount: const Money(78_000),
        dueDate: today.addDays(-3),
        kind: BillKind.pixQr,
        owner: EntityKind.personal,
        status: BillStatus.paid,
        source: BillSource.email,
        plan: _personalPlan,
        paidAt: _morning(today.addDays(-3), minutes: 2),
        paidBy: PaidBy.rail,
        attempts: [
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API',
            at: _morning(today.addDays(-3), minutes: 2),
            outcome: AttemptOutcome.succeeded,
          ),
        ],
      ),
      Bill(
        id: 'bill-coworking',
        payee: 'Coworking Ponte',
        amount: const Money(120_000),
        dueDate: today.addDays(7),
        kind: BillKind.boleto,
        owner: EntityKind.company,
        status: BillStatus.awaitingApproval,
        source: BillSource.dda,
        plan: _companyPlan,
        paymentCode: '00190.00009 01234.567890 12345.678901 2 10070000120000',
        attempts: [
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API · Banco Aurora',
            at: _morning(today),
            outcome: AttemptOutcome.failed,
            reason: 'limite diário do trilho atingido',
          ),
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Pix via API · Banco Aurora',
            at: _morning(today, minutes: 30),
            outcome: AttemptOutcome.failed,
            reason: 'Nova tentativa, mesmo motivo',
          ),
          PaymentAttempt(
            step: LadderStep.bankApproval,
            rail: 'Banco Atlântico',
            at: _morning(today, minutes: 31),
            outcome: AttemptOutcome.waiting,
          ),
        ],
      ),
      Bill(
        id: 'bill-das',
        payee: 'DAS · set/2026',
        amount: const Money(147_600),
        dueDate: taxDue,
        kind: BillKind.taxBarcode,
        owner: EntityKind.company,
        status: BillStatus.scheduled,
        source: BillSource.email,
        plan: _taxPlan,
        paymentCode: '85890000014 7 76000328262 2 01000000000 5 00000000000 0',
      ),
      Bill(
        id: 'bill-darf',
        payee: 'DARF 0561 · IRRF',
        amount: const Money(31_240),
        dueDate: taxDue,
        kind: BillKind.taxBarcode,
        owner: EntityKind.company,
        status: BillStatus.pending,
        source: BillSource.manual,
        plan: _taxPlan,
        paymentCode: '85810000003 1 12400385261 0 05610000000 2 00000000000 9',
        attempts: [
          PaymentAttempt(
            step: LadderStep.automatic,
            rail: 'Guias via API · Banco Aurora',
            at: _morning(today),
            outcome: AttemptOutcome.failed,
            reason: 'Guia não aceita pela API',
          ),
        ],
      ),
      Bill(
        id: 'bill-gps',
        payee: 'GPS · INSS',
        amount: const Money(85_800),
        dueDate: taxDue,
        kind: BillKind.taxBarcode,
        owner: EntityKind.company,
        status: BillStatus.scheduled,
        source: BillSource.manual,
        plan: _taxPlan,
        paymentCode: '85820000008 5 85800270000 1 00000000000 3 00000000000 4',
      ),
    ];
  }

  List<Bill> _bills() => [
    for (final bill in _seed()) _changed[bill.id] ?? bill,
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<Result<List<Bill>>> list() async {
    await _wait();
    return Ok(_bills());
  }

  @override
  Future<Result<Bill>> get(String id) async {
    await _wait();
    final bill = _bills().where((bill) => bill.id == id).firstOrNull;
    if (bill == null) return const Err(NotFoundFailure());
    return Ok(bill);
  }

  @override
  Future<Result<Bill>> markPaid(String id) async {
    final found = await get(id);
    if (found case Ok(:final value)) {
      final paid = value.markedPaid(_clock.now());
      _changed[id] = paid;
      return Ok(paid);
    }
    return found;
  }

  @override
  Future<Result<Bill>> confirmPayment(String id) async {
    final found = await get(id);
    if (found case Ok(:final value)) {
      final confirmed = Bill(
        id: value.id,
        payee: value.payee,
        amount: value.amount,
        dueDate: value.dueDate,
        kind: value.kind,
        owner: value.owner,
        status: BillStatus.scheduled,
        source: value.source,
        plan: value.plan,
        paymentCode: value.paymentCode,
        attempts: value.attempts,
      );
      _changed[id] = confirmed;
      return Ok(confirmed);
    }
    return found;
  }
}
