import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// The alert types the server raises; [other] keeps a newer server's types
/// readable by an older app.
enum AlertKind {
  billCaptured('BILL_CAPTURED'),
  billNeedsAmount('BILL_NEEDS_AMOUNT'),
  billDueSoon('BILL_DUE_SOON'),
  paymentNeedsConfirmation('PAYMENT_NEEDS_CONFIRMATION'),
  paymentPaid('PAYMENT_PAID'),
  paymentMovedDown('PAYMENT_MOVED_DOWN'),
  paymentAssisted('PAYMENT_ASSISTED'),
  approvalPending('APPROVAL_PENDING'),
  lowBalance('LOW_BALANCE'),
  invoiceIssued('INVOICE_ISSUED'),
  invoiceFailed('INVOICE_FAILED'),
  cardBillClosed('CARD_BILL_CLOSED'),
  other('OTHER');

  new(this.wire);

  final String wire;

  static AlertKind fromWire(String wire) =>
      values.where((kind) => kind.wire == wire).firstOrNull ?? other;

  /// The types a user can mute.
  static List<AlertKind> get mutable =>
      values.where((kind) => kind != other).toList();
}

final class AppAlert extends Equatable {
  const new({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.billId,
    this.readAt,
    this.data = const {},
  });

  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? billId;
  final DateTime? readAt;
  final Map<String, String> data;

  bool get unread => readAt == null;

  /// A bill that fell to assisted says whether a Pix copy-and-paste waits.
  bool get hasPixCode => data['hasPixCode'] == 'true';

  AppAlert read(DateTime at) => AppAlert(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    billId: billId,
    readAt: readAt ?? at,
    data: data,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    body,
    createdAt,
    billId,
    readAt,
    data,
  ];
}

final class AlertPage extends Equatable {
  const new({required this.items, this.nextCursor});

  final List<AppAlert> items;
  final String? nextCursor;

  @override
  List<Object?> get props => [items, nextCursor];
}

abstract interface class AlertsRepository {
  Future<Result<AlertPage>> list({String? cursor});

  Future<Result<int>> unreadCount();

  Future<Result<AppAlert>> markRead(String id);

  Future<Result<int>> markAllRead();

  /// The muted state of every type the server knows.
  Future<Result<Map<AlertKind, bool>>> settings();

  Future<Result<Map<AlertKind, bool>>> setMuted(
    AlertKind kind, {
    required bool muted,
  });

  /// [locale] picks the language of this device's push text.
  Future<Result<void>> registerDevice(
    String token,
    String platform, {
    required String locale,
  });

  Future<Result<void>> removeDevice(String token);
}
