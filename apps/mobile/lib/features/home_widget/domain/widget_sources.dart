import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/insights/domain/insights_repository.dart';
import 'package:cashdeck/features/outlook/domain/outlook_repository.dart';

/// The repositories a background refresh reads, opened for one server
/// session. [close] drops the connection, and the token with it, once the
/// refresh is over.
final class WidgetSources {
  const new({
    required this.outlook,
    required this.bills,
    required this.insights,
    this.close = _nothing,
  });

  final OutlookRepository outlook;
  final BillsRepository bills;
  final InsightsRepository insights;
  final void Function() close;
}

void _nothing() {}
