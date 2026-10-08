import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';

final class FakeIssuerRepository implements IssuerRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  IssuerSetup? _saved;

  static const codes = [
    ServiceCode('1.07', 'Suporte técnico em TI'),
    ServiceCode('1.03', 'Processamento de dados'),
    ServiceCode('17.01', 'Assessoria ou consultoria'),
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<Result<IssuerSetup>> setup() async {
    await _wait();
    final today = CalendarDate.brazilToday(_clock.now());
    return Ok(
      _saved ??
          IssuerSetup(
            kind: IssuerKind.national,
            city: 'Florianópolis',
            certificateName: 'estudio-vento-sul.pfx',
            certificateExpiresOn: today.addDays(37),
            municipalRegistration: '4.412.887-3',
            serviceCode: codes.first,
          ),
    );
  }

  @override
  Future<Result<List<ServiceCode>>> serviceCodes() async {
    await _wait();
    return const Ok(codes);
  }

  @override
  Future<Result<IssuerSetup>> save(IssuerSetup setup) async {
    await _wait();
    if (setup.municipalRegistration.trim().isEmpty) {
      return const Err(ValidationFailure('municipalRegistration'));
    }
    _saved = setup;
    return Ok(setup);
  }

  @override
  Future<Result<TestEmission>> emitTest(IssuerSetup setup) async {
    await _wait();
    return const Ok(
      TestEmission(
        protocol: '2026-000184',
        elapsed: Duration(milliseconds: 1800),
      ),
    );
  }

  @override
  Future<Result<IssuerSetup>> uploadCertificate(
    LocalFile file,
    String password,
    CalendarDate expiresOn,
  ) async {
    if (password.isEmpty) {
      await _wait();
      return const Err(ValidationFailure('password'));
    }
    final current = switch (await setup()) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    final next = IssuerSetup(
      kind: current.kind,
      city: current.city,
      certificateName: file.name,
      certificateExpiresOn: expiresOn,
      municipalRegistration: current.municipalRegistration,
      serviceCode: current.serviceCode,
    );
    _saved = next;
    return Ok(next);
  }
}
