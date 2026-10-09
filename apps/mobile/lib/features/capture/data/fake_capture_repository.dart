import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

final class FakeCaptureRepository implements CaptureRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  late final DateTime _start = _clock.now();
  late List<Mailbox> _mailboxes = [
    Mailbox(
      id: 'mailbox-personal',
      address: 'marina.souza@exemplo.com',
      owner: EntityKind.personal,
      lastReadAt: _start.subtract(const Duration(hours: 3)),
      billsFound: 3,
      emailsScanned: 214,
    ),
  ];
  late List<DdaEnrollment> _dda = [
    DdaEnrollment(
      owner: EntityKind.company,
      bank: 'Banco Atlântico PJ',
      lastBatchAt: _start.subtract(const Duration(hours: 6)),
      boletos: 2,
      enabled: true,
    ),
  ];

  Future<Result<CaptureSources>> _current() async {
    await Future<void>.delayed(latency);
    return Ok(CaptureSources(mailboxes: _mailboxes, dda: _dda));
  }

  @override
  Future<Result<CaptureSources>> sources() => _current();

  @override
  Future<Result<CaptureSources>> readNow(String mailboxId) {
    if (!_mailboxes.any((m) => m.id == mailboxId)) {
      return Future.value(const Err(NotFoundFailure()));
    }
    _mailboxes = [
      for (final m in _mailboxes)
        if (m.id != mailboxId)
          m
        else
          Mailbox(
            id: m.id,
            address: m.address,
            owner: m.owner,
            lastReadAt: _clock.now(),
            billsFound: m.billsFound,
            emailsScanned: m.emailsScanned + 4,
          ),
    ];
    return _current();
  }

  @override
  Future<Result<CaptureSources>> disconnect(String mailboxId) {
    _mailboxes = [
      for (final m in _mailboxes)
        if (m.id != mailboxId) m,
    ];
    return _current();
  }

  @override
  Future<Result<CaptureSources>> setDda(EntityKind owner, {required bool on}) {
    _dda = [
      for (final d in _dda)
        if (d.owner != owner)
          d
        else
          DdaEnrollment(
            owner: d.owner,
            bank: d.bank,
            lastBatchAt: d.lastBatchAt,
            boletos: d.boletos,
            enabled: on,
          ),
    ];
    return _current();
  }

  final List<LocalFile> submitted = [];

  @override
  Future<Result<Uri>> mailboxAuthorizationUrl(EntityKind owner) async {
    await Future<void>.delayed(latency);
    return Ok(
      Uri.https('accounts.example.com', '/o/oauth2/auth', {
        'scope': 'mail.readonly',
        'state': owner.name,
      }),
    );
  }

  /// Mirrors the server: an empty file fails, one over the cap is too large
  /// and a file named like `sem-codigo` has no code to read.
  @override
  Future<Result<CaptureOutcome>> submitFile(
    LocalFile file,
    EntityKind owner, {
    Money? amount,
    CalendarDate? dueDate,
  }) async {
    await Future<void>.delayed(latency);
    if (file.bytes.isEmpty) return const Err(ValidationFailure('empty file'));
    if (file.bytes.length > maxUploadBytes) {
      return Ok(CaptureFileTooLarge(file.bytes.length));
    }
    if (file.name.contains('sem-codigo')) {
      return const Ok(CaptureNothingFound());
    }
    if (file.name.contains('sem-valor') && amount == null) {
      return const Ok(CaptureDetailsNeeded(amount: true));
    }
    submitted.add(file);
    return Ok(BillCaptured(billId: 'captured-file-${submitted.length}'));
  }

  final List<BillDraft> drafts = [];

  /// Like the server, a Pix QR without an amount and a bare key wait for
  /// the amount before the bill exists.
  @override
  Future<Result<CaptureOutcome>> capture(BillDraft draft) async {
    await Future<void>.delayed(latency);
    final pix = draft.pixCode;
    final qr = pix == null ? null : parsePixBrCode(pix);
    final openQr = draft.paymentCode == null && qr != null && qr.amount == null;
    final needsAmount =
        (draft.pixKey != null || openQr) && draft.amount == null;
    if (needsAmount) return const Ok(CaptureDetailsNeeded(amount: true));
    drafts.add(draft);
    return Ok(BillCaptured(billId: 'captured-${drafts.length}'));
  }
}
