import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/files/plain_pdf.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';

/// The two transfers Início Consolidado lists, ids shared with its fake.
final class FakeTransfersRepository implements TransfersRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 250)});

  final Clock _clock;
  final Duration latency;

  static const _company = TransferParty(
    owner: EntityKind.company,
    holder: 'Estúdio Vento Sul',
    account: 'Aurora PJ ••7702',
  );
  static const _person = TransferParty(
    owner: EntityKind.personal,
    holder: 'Marina Souza',
    account: 'Corrente Aurora ••4410',
  );

  @override
  Future<Result<TransferDetail>> transfer(String id) async {
    await Future<void>.delayed(latency);
    final today = CalendarDate.brazilToday(_clock.now());
    DateTime at(int back, int hour, int minute) {
      final day = today.addDays(-back);
      return DateTime.utc(day.year, day.month, day.day, hour + 3, minute);
    }

    return switch (id) {
      'transfer-distribution' => Ok(
        TransferDetail(
          id: id,
          kind: TransferKind.profitDistribution,
          amount: const Money(500_000),
          at: at(2, 10, 15),
          rail: 'Pix',
          from: _company,
          to: _person,
          document: 'ata-distribuicao-set.pdf',
        ),
      ),
      'transfer-prolabore' => Ok(
        TransferDetail(
          id: id,
          kind: TransferKind.proLabore,
          amount: const Money(780_000),
          at: at(1, 9, 0),
          rail: 'Pix',
          from: _company,
          to: _person,
        ),
      ),
      _ => const Err(NotFoundFailure()),
    };
  }

  @override
  Future<Result<LocalFile>> document(String id) async {
    final detail = await transfer(id);
    return switch (detail) {
      Ok(:final value) when value.document != null => Ok(
        LocalFile(
          name: value.document!,
          mimeType: 'application/pdf',
          bytes: plainPdf([
            value.document!,
            '${value.from.holder} -> ${value.to.holder}',
            MoneyFormat.format(value.amount),
          ]),
        ),
      ),
      Ok() => const Err(NotFoundFailure()),
      Err(:final failure) => Err(failure),
    };
  }
}
