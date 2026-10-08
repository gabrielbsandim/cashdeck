import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/files/plain_pdf.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';

/// Only the condominium bill was paid by a rail, so only it has a proof.
final class FakeReceiptsRepository implements ReceiptsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 250)});

  final Clock _clock;
  final Duration latency;
  final Map<String, List<Attachment>> _attached = {};

  BankProof? _proofOf(String billId) {
    if (billId != 'bill-condo') return null;
    final day = CalendarDate.brazilToday(_clock.now()).addDays(-3);
    return BankProof(
      rail: 'Pix via API',
      amount: const Money(78_000),
      paidAt: DateTime.utc(day.year, day.month, day.day, 10, 2, 14),
      payer: 'Marina Souza · Corrente Aurora ••4410',
      receiver: 'Condomínio Jardim',
      transactionId: 'E12345678202610050702a9c4f3d1',
      authentication: '8F3A-21C9-77D0',
    );
  }

  Receipt _receiptOf(String billId) => Receipt(
    billId: billId,
    proof: _proofOf(billId),
    attachments: [...?_attached[billId]],
  );

  @override
  Future<Result<Receipt>> receipt(String billId) async {
    await Future<void>.delayed(latency);
    return Ok(_receiptOf(billId));
  }

  @override
  Future<Result<LocalFile>> document(String billId) async {
    await Future<void>.delayed(latency);
    final proof = _proofOf(billId);
    if (proof == null) return const Err(NotFoundFailure());
    return Ok(
      LocalFile(
        name: 'comprovante-$billId.pdf',
        mimeType: 'application/pdf',
        bytes: plainPdf([
          'Comprovante de pagamento',
          proof.receiver,
          MoneyFormat.format(proof.amount),
          proof.paidAt.toIso8601String(),
          ?proof.transactionId,
        ]),
      ),
    );
  }

  @override
  Future<Result<Receipt>> attach(String billId, LocalFile file) async {
    await Future<void>.delayed(latency);
    final list = _attached.putIfAbsent(billId, () => []);
    list.add(
      Attachment(id: 'attachment-${list.length + 1}', fileName: file.name),
    );
    return Ok(_receiptOf(billId));
  }
}
