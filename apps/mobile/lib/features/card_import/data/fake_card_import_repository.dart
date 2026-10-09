import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

final class FakeCardImportRepository implements CardImportRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;

  @override
  Future<Result<CardStatement>> statement() async {
    await Future<void>.delayed(latency);
    final today = CalendarDate.brazilToday(_clock.now());
    return Ok(
      CardStatement(
        id: 'statement-viagem',
        card: 'Cartão Viagem',
        issuer: 'Banco Tradicional',
        closing: today.addDays(-3),
        due: today.addDays(7),
        rate: 54_900,
        iofBps: 350,
        lines: [
          StatementLine(
            id: 'line-hotel',
            merchant: 'Hotel Porto Azul',
            date: today.addDays(-10),
            amount: const Money(41_200, currency: 'USD'),
          ),
          StatementLine(
            id: 'line-metro',
            merchant: 'Metro Pass',
            date: today.addDays(-9),
            amount: const Money(3_300, currency: 'USD'),
          ),
          StatementLine(
            id: 'line-cafe',
            merchant: 'Café Lumen',
            date: today.addDays(-8),
            amount: const Money(1_840, currency: 'USD'),
            needsReview: true,
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<CardStatement>> upload(LocalFile file, EntityKind owner) =>
      statement();

  @override
  Future<Result<String>> createBill(
    CardStatement statement,
    Set<String> lineIds,
  ) async {
    await Future<void>.delayed(latency);
    final total = StatementTotals.of(statement, lineIds).total;
    if (total.cents <= 0) return const Err(ValidationFailure('total'));
    return const Ok('bill-card-viagem');
  }
}
