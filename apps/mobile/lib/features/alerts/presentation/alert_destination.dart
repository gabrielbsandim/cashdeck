import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';

typedef _Route = String Function(String id);

/// The data key naming the record an alert is about, and its screen.
const Map<AlertKind, (String, _Route)> _records = {
  AlertKind.unusualPurchase: ('transactionId', AppRoutes.transaction),
  AlertKind.cardChargeCaptured: ('transactionId', AppRoutes.transaction),
  AlertKind.subscriptionChanged: ('key', AppRoutes.subscription),
  AlertKind.cardBillAboveAverage: ('accountId', AppRoutes.cardBills),
};

const Map<AlertKind, String> _screens = {
  AlertKind.bankSyncStale: AppRoutes.settingsConnections,
  AlertKind.invoiceNotIssued: AppRoutes.settingsCompany,
};

/// The screen an alert is about, else its bill; null when it has neither.
String? alertDestination(
  AlertKind kind,
  Map<String, String> data, {
  String? billId,
}) {
  final screen = _screens[kind];
  if (screen != null) return screen;
  final month = data['month'];
  if (kind == AlertKind.monthlyRecap && month != null) {
    return AppRoutes.recap(month, entity: data['entity']);
  }
  final record = _records[kind];
  final id = record == null ? null : data[record.$1];
  if (record != null && id != null) return record.$2(id);
  return billId == null ? null : AppRoutes.bill(billId);
}
