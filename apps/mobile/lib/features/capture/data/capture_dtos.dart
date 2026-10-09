import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:dio/dio.dart';

CaptureSources captureSourcesFromJson(JsonMap json) => CaptureSources(
  mailboxes: [
    for (final mailbox in readMapList(json, 'mailboxes'))
      Mailbox(
        id: readString(mailbox, 'id'),
        address: readString(mailbox, 'address'),
        owner: readEntityKind(mailbox, 'owner'),
        lastReadAt: readOptionalDateTime(mailbox, 'lastReadAt'),
        billsFound: readInt(mailbox, 'billsFound'),
        emailsScanned: readInt(mailbox, 'emailsScanned'),
      ),
  ],
  dda: [
    for (final dda in readMapList(json, 'dda'))
      DdaEnrollment(
        owner: readEntityKind(dda, 'owner'),
        bank: readString(dda, 'bank'),
        lastBatchAt: readOptionalDateTime(dda, 'lastBatchAt'),
        boletos: readInt(dda, 'boletos'),
        enabled: readBool(dda, 'enabled'),
      ),
  ],
);

const Map<CaptureChannel, String> _channels = {
  CaptureChannel.camera: 'CAMERA',
  CaptureChannel.share: 'SHARE',
  CaptureChannel.manual: 'MANUAL',
};

/// The `POST /bills` capture body, without the entity id.
JsonMap captureBody(BillDraft draft) => {
  'source': _channels[draft.channel],
  'paymentCode': ?draft.paymentCode,
  'pixCode': ?draft.pixCode,
  'pixKey': ?draft.pixKey,
  'amountCents': ?draft.amount?.cents,
  'dueDate': ?draft.dueDate?.iso,
  'payee': ?_blankToNull(draft.payee),
};

String? _blankToNull(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// The capture answers the user can act on; anything else stays an error.
CaptureOutcome? captureOutcomeOf(Response<Object?>? response, {int? fileSize}) {
  final status = response?.statusCode;
  final code = _errorCode(response?.data);
  return switch ((status, code, fileSize)) {
    (422, 'AMOUNT_REQUIRED', _) => const CaptureDetailsNeeded(amount: true),
    (422, 'DUE_DATE_REQUIRED', _) => const CaptureDetailsNeeded(amount: false),
    (413, _, final int size) => CaptureFileTooLarge(size),
    (422, _, int()) => const CaptureNothingFound(),
    _ => null,
  };
}

String? _errorCode(Object? data) {
  if (data is! Map) return null;
  final error = data['error'];
  if (error is! Map) return null;
  final code = error['code'];
  return code is String ? code : null;
}
