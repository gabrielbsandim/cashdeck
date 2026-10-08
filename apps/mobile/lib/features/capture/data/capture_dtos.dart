import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';

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
