import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';

/// Fictional rails per entity. Personal has no bank approval step, so its
/// ladder jumps from 1 to 3.
final class FakeRailsRepository implements RailsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  DateTime? _lastTest;

  final List<PaymentRail> _rails = [
    const PaymentRail(
      id: 'rail-pf-pix',
      kind: RailKind.pixApi,
      owner: EntityKind.personal,
      step: 1,
      institution: 'Banco Aurora',
      status: RailStatus.active,
    ),
    const PaymentRail(
      id: 'rail-pf-reserve',
      kind: RailKind.reserveFunding,
      owner: EntityKind.personal,
      step: 1,
      institution: 'Banco Aurora',
      status: RailStatus.active,
    ),
    const PaymentRail(
      id: 'rail-pf-approval',
      kind: RailKind.bankApproval,
      owner: EntityKind.personal,
      step: 2,
      institution: '',
      status: RailStatus.unavailable,
    ),
    const PaymentRail(
      id: 'rail-pf-assisted',
      kind: RailKind.assisted,
      owner: EntityKind.personal,
      step: 3,
      institution: '',
      status: RailStatus.always,
    ),
    const PaymentRail(
      id: 'rail-pj-pix',
      kind: RailKind.pixApi,
      owner: EntityKind.company,
      step: 1,
      institution: 'Aurora PJ',
      status: RailStatus.active,
    ),
    const PaymentRail(
      id: 'rail-pj-boleto',
      kind: RailKind.boletoApi,
      owner: EntityKind.company,
      step: 1,
      institution: 'Aurora PJ',
      status: RailStatus.active,
    ),
    const PaymentRail(
      id: 'rail-pj-tax',
      kind: RailKind.taxApi,
      owner: EntityKind.company,
      step: 1,
      institution: 'Aurora PJ',
      status: RailStatus.active,
    ),
    const PaymentRail(
      id: 'rail-pj-approval',
      kind: RailKind.bankApproval,
      owner: EntityKind.company,
      step: 2,
      institution: 'Atlântico PJ',
      status: RailStatus.needsAuthorization,
    ),
    const PaymentRail(
      id: 'rail-pj-assisted',
      kind: RailKind.assisted,
      owner: EntityKind.company,
      step: 3,
      institution: '',
      status: RailStatus.always,
    ),
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  int _indexOf(String id) => _rails.indexWhere((rail) => rail.id == id);

  @override
  Future<Result<List<PaymentRail>>> rails(EntityKind owner) async {
    await _wait();
    return Ok([
      for (final rail in _rails)
        if (rail.owner == owner) rail,
    ]);
  }

  @override
  Future<Result<PaymentRail>> authorize(String id) async {
    await _wait();
    final index = _indexOf(id);
    if (index < 0) return const Err(NotFoundFailure());
    final rail = _rails[index].withStatus(RailStatus.active);
    _rails[index] = rail;
    return Ok(rail);
  }

  @override
  Future<Result<RailCredentials>> credentials(String id) async {
    await _wait();
    final index = _indexOf(id);
    if (index < 0 || !_rails[index].configurable) {
      return const Err(NotFoundFailure());
    }
    final today = CalendarDate.brazilToday(_clock.now());
    return Ok(
      RailCredentials(
        certificateName: _rails[index].owner == EntityKind.personal
            ? 'aurora-pf.pfx'
            : 'aurora-pj.pfx',
        certificateValidUntil: const CalendarDate(2027, 3, 2),
        apiKeyHint: '3f9a',
        lastTestAt:
            _lastTest ??
            DateTime.utc(today.year, today.month, today.day, 11, 12),
      ),
    );
  }

  @override
  Future<Result<List<RailCheck>>> test(String id) async {
    await _wait();
    if (_indexOf(id) < 0) return const Err(NotFoundFailure());
    _lastTest = _clock.now();
    return const Ok([
      RailCheck(kind: RailCheckKind.certificate, passed: true, millis: 182),
      RailCheck(kind: RailCheckKind.apiKey, passed: true, millis: 64),
      RailCheck(kind: RailCheckKind.scope, passed: true),
      RailCheck(kind: RailCheckKind.payerAccount, passed: true, millis: 210),
    ]);
  }

  @override
  Future<Result<void>> remove(String id) async {
    await _wait();
    final index = _indexOf(id);
    if (index < 0) return const Err(NotFoundFailure());
    _rails.removeAt(index);
    return const Ok(null);
  }
}
