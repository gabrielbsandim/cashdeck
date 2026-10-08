import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

enum IssuerKind { national, municipal }

enum CertificateState { valid, expiringSoon, expired }

/// Forty-five days ahead is when renewing an A1 certificate starts to be
/// urgent, since the issuer refuses an expired one.
CertificateState certificateStateOf(
  CalendarDate expiresOn,
  CalendarDate today,
) {
  final days = today.daysUntil(expiresOn);
  if (days < 0) return CertificateState.expired;
  if (days <= 45) return CertificateState.expiringSoon;
  return CertificateState.valid;
}

final class ServiceCode extends Equatable {
  const new(this.code, this.description);

  final String code;
  final String description;

  @override
  List<Object?> get props => [code, description];
}

final class IssuerSetup extends Equatable {
  const new({
    required this.kind,
    required this.city,
    required this.certificateName,
    required this.certificateExpiresOn,
    required this.municipalRegistration,
    required this.serviceCode,
  });

  final IssuerKind kind;
  final String city;
  final String certificateName;
  final CalendarDate certificateExpiresOn;
  final String municipalRegistration;
  final ServiceCode serviceCode;

  IssuerSetup copyWith({
    IssuerKind? kind,
    String? municipalRegistration,
    ServiceCode? serviceCode,
  }) => IssuerSetup(
    kind: kind ?? this.kind,
    city: city,
    certificateName: certificateName,
    certificateExpiresOn: certificateExpiresOn,
    municipalRegistration: municipalRegistration ?? this.municipalRegistration,
    serviceCode: serviceCode ?? this.serviceCode,
  );

  @override
  List<Object?> get props => [
    kind,
    city,
    certificateName,
    certificateExpiresOn,
    municipalRegistration,
    serviceCode,
  ];
}

final class TestEmission extends Equatable {
  const new({required this.protocol, required this.elapsed});

  final String protocol;
  final Duration elapsed;

  @override
  List<Object?> get props => [protocol, elapsed];
}

abstract interface class IssuerRepository {
  Future<Result<IssuerSetup>> setup();

  Future<Result<List<ServiceCode>>> serviceCodes();

  Future<Result<IssuerSetup>> save(IssuerSetup setup);

  Future<Result<TestEmission>> emitTest(IssuerSetup setup);

  /// Sends the A1 certificate and its password; the server seals both and
  /// reads the expiry date from the certificate.
  Future<Result<IssuerSetup>> uploadCertificate(
    LocalFile file,
    String password,
  );
}
