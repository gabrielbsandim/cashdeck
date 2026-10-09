import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/pasted_code.dart';
import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  const personal = EntityKind.personal;

  test('a scanned code fills the field it pays with', () {
    expect(
      BillDraft.fromScanned(
        const ScannedCode(kind: ScannedKind.pix, value: '000201'),
        personal,
      ),
      const BillDraft(
        owner: personal,
        channel: CaptureChannel.camera,
        pixCode: '000201',
      ),
    );
    expect(
      BillDraft.fromScanned(
        const ScannedCode(kind: ScannedKind.taxGuide, value: '858'),
        EntityKind.company,
        channel: CaptureChannel.share,
      ).paymentCode,
      '858',
    );
  });

  test('a pasted code fills the field it pays with', () {
    final payload = testPixCode();

    expect(
      BillDraft.fromPasted(
        PastedPixCode(parsePixBrCode(payload)!),
        personal,
      ).pixCode,
      payload,
    );
    expect(
      BillDraft.fromPasted(const PastedBarcode('237'), personal).paymentCode,
      '237',
    );
    final key = BillDraft.fromPasted(
      const PastedPixKey(PixKeyType.email, 'a@b.co'),
      personal,
      channel: CaptureChannel.share,
    );
    expect(key.pixKey, 'a@b.co');
    expect(key.channel, CaptureChannel.share);
  });

  test('copyWith adds what the user typed and keeps the rest', () {
    const draft = BillDraft(
      owner: personal,
      channel: CaptureChannel.manual,
      paymentCode: '237',
      payee: 'Escola Exemplo',
    );

    final filled = draft.copyWith(
      amount: const Money(500),
      dueDate: testToday,
      pixCode: '000201',
    );

    expect(filled.amount, const Money(500));
    expect(filled.dueDate, testToday);
    expect(filled.pixCode, '000201');
    expect(filled.paymentCode, '237');
    expect(filled.payee, 'Escola Exemplo');
    expect(draft.copyWith(), draft);
    expect(draft.props, hasLength(8));
  });

  test('outcomes compare by value', () {
    expect(const BillCaptured(billId: 'b1'), const BillCaptured(billId: 'b1'));
    expect(const BillCaptured(billId: 'b1', duplicate: true).props, [
      'b1',
      true,
    ]);
    expect(const CaptureDetailsNeeded(amount: true).props, [true]);
    expect(const CaptureFileTooLarge(9).props, [9]);
    expect(const CaptureNothingFound().props, isEmpty);
  });
}
