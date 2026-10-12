import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

final FutureProviderFamily<SafeToSpend, EntityKind> safeToSpendOfProvider =
    FutureProvider.autoDispose.family<SafeToSpend, EntityKind>(
      (ref, entity) async =>
          (await ref.watch(loadSafeToSpendProvider)(entity)).orThrow,
      retry: noRetry,
    );

/// The person's figure, which the home screen widget also shows.
final FutureProvider<SafeToSpend> safeToSpendProvider = safeToSpendOfProvider(
  EntityKind.personal,
);

final FutureProvider<SafeToSpend> companySafeToSpendProvider =
    safeToSpendOfProvider(EntityKind.company);

class NetWorthPeriodController extends Notifier<NetWorthPeriod> {
  @override
  NetWorthPeriod build() => NetWorthPeriod.twelveMonths;

  NetWorthPeriod get period => state;

  set period(NetWorthPeriod period) => state = period;
}

/// One window for the home card and the net worth screen.
final netWorthPeriodProvider =
    NotifierProvider<NetWorthPeriodController, NetWorthPeriod>(
      NetWorthPeriodController.new,
    );

final FutureProvider<NetWorth> netWorthProvider =
    FutureProvider.autoDispose<NetWorth>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      final period = ref.watch(netWorthPeriodProvider);
      return (await ref.watch(loadNetWorthProvider)(scope, period)).orThrow;
    }, retry: noRetry);
