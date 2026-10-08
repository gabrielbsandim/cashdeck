import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';

/// Only the condominium bill was paid by a rail, so only it has a proof.
final class FakeReceiptsRepository implements ReceiptsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 250)});

  final Clock _clock;
  final Duration latency;

  @override
  Future<Result<Receipt>> receipt(String billId) async {
    await Future<void>.delayed(latency);
    if (billId != 'bill-condo') return Ok(Receipt(billId: billId));
    final day = CalendarDate.brazilToday(_clock.now()).addDays(-3);
    return Ok(
      Receipt(
        billId: billId,
        proof: BankProof(
          rail: 'Pix via API',
          amount: const Money(78_000),
          paidAt: DateTime.utc(day.year, day.month, day.day, 10, 2, 14),
          payer: 'Marina Souza · Corrente Aurora ••4410',
          receiver: 'Condomínio Jardim',
          transactionId: 'E12345678202610050702a9c4f3d1',
          authentication: '8F3A-21C9-77D0',
        ),
      ),
    );
  }
}
