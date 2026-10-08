import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';

const Map<String, RailKind> _kinds = {
  'PIX_API': RailKind.pixApi,
  'BOLETO_API': RailKind.boletoApi,
  'TAX_API': RailKind.taxApi,
  'RESERVE_FUNDING': RailKind.reserveFunding,
  'BANK_APPROVAL': RailKind.bankApproval,
  'ASSISTED': RailKind.assisted,
};

const Map<String, RailStatus> _statuses = {
  'ACTIVE': RailStatus.active,
  'NEEDS_AUTHORIZATION': RailStatus.needsAuthorization,
  'UNAVAILABLE': RailStatus.unavailable,
  'ALWAYS': RailStatus.always,
};

const Map<String, RailCheckKind> _checks = {
  'CERTIFICATE': RailCheckKind.certificate,
  'API_KEY': RailCheckKind.apiKey,
  'SCOPE': RailCheckKind.scope,
  'PAYER_ACCOUNT': RailCheckKind.payerAccount,
};

PaymentRail railFromJson(JsonMap json) => PaymentRail(
  id: readString(json, 'id'),
  kind: readEnum(json, 'kind', _kinds),
  owner: readEntityKind(json, 'owner'),
  step: readInt(json, 'step'),
  institution: readString(json, 'institution'),
  status: readEnum(json, 'status', _statuses),
);

RailCredentials credentialsFromJson(JsonMap json) => RailCredentials(
  certificateName: readOptionalString(json, 'certificateName'),
  certificateValidUntil: readOptionalDate(json, 'certificateValidUntil'),
  apiKeyHint: readOptionalString(json, 'apiKeyHint'),
  lastTestAt: readOptionalDateTime(json, 'lastTestAt'),
);

RailCheck checkFromJson(JsonMap json) => RailCheck(
  kind: readEnum(json, 'kind', _checks),
  passed: readBool(json, 'passed'),
  millis: readOptionalInt(json, 'millis'),
);
